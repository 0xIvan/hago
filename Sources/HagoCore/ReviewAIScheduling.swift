import CryptoKit
import Foundation

public enum ReviewAIScheduleInterval: Int, CaseIterable, Codable, Sendable {
    case hourly = 3_600
    case twoHours = 7_200
    case fourHours = 14_400
    case daily = 86_400

    public var title: String {
        switch self {
        case .hourly: "Every hour"
        case .twoHours: "Every two hours"
        case .fourHours: "Every four hours"
        case .daily: "Every 24 hours"
        }
    }
}

public enum ReviewAIScheduleOutcome: String, Codable, Sendable {
    case running, completed, noChanges, failed, stopped, interrupted
}

public struct ReviewAIScheduleState: Equatable, Codable, Sendable {
    public var nextRunAt: Date?
    public var lastAttemptAt: Date?
    public var lastCompletedAt: Date?
    public var outcome: ReviewAIScheduleOutcome?
    public var message: String?
    public var consecutiveFailures = 0

    public init() {}

    public func isDue(at date: Date, enabled: Bool, isRunning: Bool) -> Bool {
        enabled && !isRunning && nextRunAt.map { $0 <= date } != false
    }

    public mutating func deferOverdueRunAfterLaunch(at date: Date, interval: ReviewAIScheduleInterval) {
        guard nextRunAt.map({ $0 <= date }) != false else { return }
        nextRunAt = date.addingTimeInterval(TimeInterval(interval.rawValue))
    }

    public mutating func begin(at date: Date, interval: ReviewAIScheduleInterval) {
        lastAttemptAt = date
        // Schedule from this attempt, not an old deadline: waking causes one catch-up only.
        nextRunAt = date.addingTimeInterval(TimeInterval(interval.rawValue))
        outcome = .running
        message = "Analyzing new or changed Review groups."
    }

    public mutating func finish(at date: Date, analyzedGroups: Int, appliedRules: Int) {
        lastCompletedAt = date
        consecutiveFailures = 0
        outcome = analyzedGroups == 0 ? .noChanges : .completed
        message = analyzedGroups == 0
            ? "No new or changed groups to analyze."
            : "Checked \(analyzedGroups) groups; applied \(appliedRules) rules. Recommendations are in Review."
    }

    public mutating func fail(_ message: String) {
        outcome = .failed
        self.message = message
        consecutiveFailures += 1
    }

    public mutating func stop(at date: Date, interval: ReviewAIScheduleInterval) {
        outcome = .stopped
        message = "Analysis stopped."
        nextRunAt = date.addingTimeInterval(TimeInterval(interval.rawValue))
    }

    public mutating func recoverAfterRestart(at date: Date, interval: ReviewAIScheduleInterval) {
        guard outcome == .running else { return }
        outcome = .interrupted
        message = "The previous run was interrupted. It will retry at the next scheduled time."
        nextRunAt = date.addingTimeInterval(TimeInterval(interval.rawValue))
    }
}

public struct ReviewAIAnalysisContext: Equatable, Codable, Sendable {
    public var harness: ReviewAIHarnessKind
    public var model: String?
    public var reasoning: ReviewAIReasoningEffort?
    public var profession: ReviewAIProfession

    public init(harness: ReviewAIHarnessKind, model: String?, reasoning: ReviewAIReasoningEffort?, profession: ReviewAIProfession = .notSpecified) {
        self.harness = harness
        self.model = model
        self.reasoning = reasoning
        self.profession = profession
    }

    public func fingerprint(for group: ReviewAISuggestionGroup) throws -> String {
        // Counts, elapsed time, condition UUIDs, and sample order are not new evidence.
        struct Evidence: Encodable {
            var version = 1
            var context: ReviewAIAnalysisContext
            var groupID: String
            var samples: [[String]]
            var relatedRules: [[String]]
        }
        let samples = Set(group.samples.map {
            [$0.appName, $0.bundleIdentifier, $0.windowTitle, $0.url ?? ""]
        }).sorted { $0.lexicographicallyPrecedes($1) }
        let related = group.relatedRules.map {
            [$0.field.rawValue, $0.operation.rawValue, $0.value.lowercased(), $0.kind.rawValue]
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(Evidence(context: self, groupID: group.id, samples: samples, relatedRules: related))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ReviewAICachedSuggestion: Codable, Sendable {
    public var fingerprint: String
    public var suggestion: ReviewAISuggestion
    public var analyzedAt: Date
    public var automaticApplicationAttempted: Bool

    public init(fingerprint: String, suggestion: ReviewAISuggestion, analyzedAt: Date, automaticApplicationAttempted: Bool = false) {
        self.fingerprint = fingerprint
        self.suggestion = suggestion
        self.analyzedAt = analyzedAt
        self.automaticApplicationAttempted = automaticApplicationAttempted
    }
}

public struct ReviewAIAnalysisResult: Sendable {
    public var summary: ReviewAIRunSummary?
    public var analyzedGroups: Int
    public var reconciledEntries: Int
}

public enum ReviewAIAnalysisError: Error, LocalizedError {
    case alreadyRunning
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "Review analysis is already running."
        case .invalidResponse: "The AI response did not match the requested groups."
        }
    }
}

@MainActor
public final class ReviewAIAnalysisService {
    public private(set) var isRunning = false
    private let store: HagoStore

    public init(store: HagoStore) {
        self.store = store
    }

    public func currentRequest() throws -> ReviewAISuggestionRequest {
        ReviewAISuggestionRequest(
            reviewSegments: try store.reviewSegments().filter { !$0.classification.isManual },
            existingRules: try store.loadRules()
        )
    }

    public func savedSuggestions(context: ReviewAIAnalysisContext) throws -> [ReviewAISuggestion] {
        let request = try currentRequest()
        let cache = try store.loadReviewAICache()
        return try request.groups.compactMap { group in
            guard let saved = cache[group.id], saved.fingerprint == (try context.fingerprint(for: group)) else { return nil }
            var suggestion = saved.suggestion
            suggestion.affectedCount = group.affectedCount
            suggestion.affectedDuration = group.affectedDuration
            suggestion.samples = group.samples
            suggestion.relatedRuleKinds = group.relatedRules.map(\.kind)
            return suggestion
        }
    }

    public func analyze(
        provider: any ReviewAISuggestionProviding,
        context: ReviewAIAnalysisContext,
        harnessVersion: String?,
        automaticallyApply: Bool,
        force: Bool = false
    ) async throws -> ReviewAIAnalysisResult {
        guard !isRunning else { throw ReviewAIAnalysisError.alreadyRunning }
        isRunning = true
        defer { isRunning = false }
        try Task.checkCancellation()
        let reconciled = try store.reconcileReviewWithExistingRules()
        let request = try currentRequest()
        let cache = try store.loadReviewAICache()
        let pending = try request.groups.filter { group in
            if force { return true }
            return cache[group.id]?.fingerprint != (try context.fingerprint(for: group))
        }
        let pendingIDs = Set(pending.map(\.id))
        // Enabling automatic application can reuse saved advice, with all safety checks repeated.
        let reusable = automaticallyApply && !force ? request.groups.filter {
            !pendingIDs.contains($0.id) && cache[$0.id]?.automaticApplicationAttempted == false
        } : []
        // Bounded batches let unchanged recommendations drop out and older pending groups advance.
        let batch = Array(pending.prefix(50))
        let cachedBatch = Array(reusable.prefix(50 - batch.count))
        let allGroups = batch + cachedBatch
        guard !allGroups.isEmpty else {
            return ReviewAIAnalysisResult(summary: nil, analyzedGroups: 0, reconciledEntries: reconciled)
        }
        let signatures = try Dictionary(uniqueKeysWithValues: allGroups.map { ($0.id, try context.fingerprint(for: $0)) })
        let response = batch.isEmpty ? [] : try await provider.suggestions(for: ReviewAISuggestionRequest(groups: batch))
        try Task.checkCancellation()
        guard response.count == batch.count, Set(response.map(\.id)) == Set(batch.map(\.id)),
              response.allSatisfy({ $0.confidence.isFinite && (0...1).contains($0.confidence) }) else {
            throw ReviewAIAnalysisError.invalidResponse
        }
        let currentGroups = Dictionary(uniqueKeysWithValues: try currentRequest().groups.map { ($0.id, $0) })
        let recommendations = response + cachedBatch.compactMap { cache[$0.id]?.suggestion }
        let valid = try recommendations.compactMap { suggestion -> ReviewAISuggestion? in
            guard let group = currentGroups[suggestion.id],
                  signatures[group.id] == (try context.fingerprint(for: group)) else { return nil }
            // Never accept a model-provided expansion of the app's selected matching condition.
            var checked = suggestion
            checked.proposedRuleCondition = group.proposedRuleCondition
            checked.affectedCount = group.affectedCount
            checked.affectedDuration = group.affectedDuration
            checked.samples = group.samples
            checked.relatedRuleKinds = group.relatedRules.map(\.kind)
            return checked
        }
        try Task.checkCancellation()
        guard !valid.isEmpty else {
            return ReviewAIAnalysisResult(summary: nil, analyzedGroups: 0, reconciledEntries: reconciled)
        }
        let summary = try store.processReviewAISuggestions(
            valid, harness: context.harness, harnessVersion: harnessVersion,
            automaticallyApply: automaticallyApply
        )
        try store.saveReviewAICache(valid.map {
            ReviewAICachedSuggestion(
                fingerprint: signatures[$0.id]!, suggestion: $0,
                analyzedAt: pendingIDs.contains($0.id) ? Date() : cache[$0.id]!.analyzedAt,
                automaticApplicationAttempted: automaticallyApply
            )
        })
        return ReviewAIAnalysisResult(summary: summary, analyzedGroups: valid.count, reconciledEntries: reconciled)
    }
}
