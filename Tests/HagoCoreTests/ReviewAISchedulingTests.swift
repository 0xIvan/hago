import Foundation
import Testing
@testable import HagoCore

@Suite @MainActor
struct ReviewAISchedulingTests {
    private let context = ReviewAIAnalysisContext(harness: .codex, model: "test", reasoning: .low)

    @Test func scheduleRunsOnceAfterMissedIntervals() {
        let now = Date()
        var state = ReviewAIScheduleState()
        #expect(state.isDue(at: now, enabled: true, isRunning: false))
        #expect(!state.isDue(at: now, enabled: false, isRunning: false))
        #expect(!state.isDue(at: now, enabled: true, isRunning: true))
        state.begin(at: now, interval: .twoHours)
        let wake = now.addingTimeInterval(30_000)
        #expect(state.isDue(at: wake, enabled: true, isRunning: false))
        state.begin(at: wake, interval: .twoHours)
        #expect(state.nextRunAt == wake.addingTimeInterval(7_200))
        #expect(!state.isDue(at: wake, enabled: true, isRunning: false))
        state.finish(at: wake, analyzedGroups: 0, appliedRules: 0)
        #expect(state.outcome == .noChanges)
    }

    @Test func launchDefersOnlyOverdueScheduledRuns() {
        let launch = Date()
        var state = ReviewAIScheduleState()
        state.nextRunAt = launch.addingTimeInterval(-60)
        state.deferOverdueRunAfterLaunch(at: launch, interval: .twoHours)
        #expect(state.nextRunAt == launch.addingTimeInterval(7_200))
        #expect(!state.isDue(at: launch, enabled: true, isRunning: false))

        state.nextRunAt = launch.addingTimeInterval(300)
        state.deferOverdueRunAfterLaunch(at: launch, interval: .twoHours)
        #expect(state.nextRunAt == launch.addingTimeInterval(300))
    }

    @Test func stopAndInterruptedRunWaitUntilNextInterval() {
        let now = Date()
        var state = ReviewAIScheduleState()
        state.begin(at: now, interval: .twoHours)
        state.recoverAfterRestart(at: now.addingTimeInterval(10), interval: .twoHours)
        #expect(state.outcome == .interrupted)
        #expect(state.nextRunAt == now.addingTimeInterval(7_210))
        state.stop(at: now, interval: .hourly)
        #expect(state.outcome == .stopped)
        #expect(!state.isDue(at: now, enabled: true, isRunning: false))
        state.fail("Unavailable")
        state.fail("Unavailable")
        state.fail("Unavailable")
        #expect(state.consecutiveFailures == 3)
        state.finish(at: now, analyzedGroups: 1, appliedRules: 0)
        #expect(state.consecutiveFailures == 0)
    }

    @Test func oldSettingsDoNotEnableSchedulingOrScheduledApply() throws {
        let data = Data(#"{"selectedHarness":"codex","automaticallyApplyHighConfidence":true}"#.utf8)
        let settings = try JSONDecoder().decode(ReviewAISettings.self, from: data)
        #expect(!settings.scheduleEnabled)
        #expect(settings.scheduleInterval == .twoHours)
        #expect(!settings.automaticallyApplyScheduledReviews)
        #expect(settings.automaticallyApplyHighConfidence)
        var enabled = settings
        enabled.scheduleEnabled = true
        enabled.scheduleInterval = .fourHours
        enabled.automaticallyApplyScheduledReviews = true
        #expect(try JSONDecoder().decode(ReviewAISettings.self, from: JSONEncoder().encode(enabled)) == enabled)
    }

    @Test func fingerprintIgnoresCountsDurationOrderAndConditionIDs() throws {
        var group = sampleGroup()
        group.samples.append(ReviewAISuggestionSample(appName: "Other", bundleIdentifier: "other", windowTitle: "Evidence", url: nil, duration: 5))
        let original = try context.fingerprint(for: group)
        group.affectedCount += 10
        group.affectedDuration += 100
        group.samples[0].duration += 100
        group.samples.reverse()
        group.proposedRuleCondition.id = UUID()
        #expect(try context.fingerprint(for: group) == original)
        group.samples[0].windowTitle = "Changed evidence"
        #expect(try context.fingerprint(for: group) != original)
        var otherContext = context
        otherContext.model = "other-model"
        #expect(try otherContext.fingerprint(for: sampleGroup()) != context.fingerprint(for: sampleGroup()))
        group = sampleGroup()
        let beforeRule = try context.fingerprint(for: group)
        group.relatedRules = [ReviewAIRelatedRule(field: .host, operation: .equals, value: "test.example", kind: .personal)]
        #expect(try context.fingerprint(for: group) != beforeRule)
    }

    @Test func recommendationsAndScheduleSurviveRestartWithoutAnotherAICall() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let rulesBefore = try store.loadRules().count
        let provider = CountingReviewProvider()
        let service = ReviewAIAnalysisService(store: store)
        let first = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        #expect(first.summary?.automaticallyAppliedCount == 0)
        #expect(try store.loadRules().count == rulesBefore)
        #expect(try store.reviewSegments().count == 1)
        var state = ReviewAIScheduleState()
        state.begin(at: Date(), interval: .twoHours)
        state.fail("Test failure")
        try store.saveReviewAIScheduleState(state)
        let reopened = try HagoStore(databaseURL: directory.appendingPathComponent("test.sqlite"))
        #expect(try reopened.loadReviewAIScheduleState() == state)
        try saveEntry(in: reopened)
        let restarted = ReviewAIAnalysisService(store: reopened)
        let saved = try #require(try restarted.savedSuggestions(context: context).first)
        #expect(saved.affectedCount == 2)
        #expect(saved.affectedDuration == 120)
        let second = try await restarted.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        #expect(second.analyzedGroups == 0)
        #expect(await provider.callCount == 1)
        #expect(try reopened.mostRecentReviewAIRun()?.id == first.summary?.id)
    }

    @Test func enablingAutomaticApplyReusesSavedAdvice() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let service = ReviewAIAnalysisService(store: store)
        let provider = CountingReviewProvider()
        _ = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        let result = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: true)
        #expect(result.summary?.automaticallyAppliedCount == 1)
        #expect(await provider.callCount == 1)
        #expect(try store.reviewSegments().isEmpty)
        let run = try #require(result.summary)
        _ = try store.undoReviewAIRun(id: run.id)
        let afterUndo = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: true)
        #expect(afterUndo.analyzedGroups == 0)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test func manualAnalysisCanReconsiderUnchangedGroups() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let service = ReviewAIAnalysisService(store: store)
        let provider = CountingReviewProvider()
        _ = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        _ = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false, force: true)
        #expect(await provider.callCount == 2)
    }

    @Test func changingProfessionInvalidatesSavedRecommendations() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let service = ReviewAIAnalysisService(store: store)
        let provider = CountingReviewProvider()
        _ = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        #expect(try service.savedSuggestions(context: context).count == 1)

        var updatedContext = context
        updatedContext.profession = .softwareDeveloper
        #expect(try service.savedSuggestions(context: updatedContext).isEmpty)
        let result = try await service.analyze(provider: provider, context: updatedContext, harnessVersion: nil, automaticallyApply: false)
        #expect(result.analyzedGroups == 1)
        #expect(await provider.callCount == 2)
        #expect(try service.savedSuggestions(context: updatedContext).count == 1)
        #expect(result.summary?.automaticallyAppliedCount == 0)
    }

    @Test func existingRuleCoverageDoesNotCreateAnotherRuleOrCallAI() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        try saveEntry(in: store, manual: true)
        try store.saveRule(Rule(
            name: "Known work", priority: 150, enabled: true, isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [RuleCondition(field: .host, operation: .equals, value: "test.example")]
        ))
        let before = try store.loadRules().count
        let provider = CountingReviewProvider()
        let result = try await ReviewAIAnalysisService(store: store).analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: true)
        #expect(result.reconciledEntries == 1)
        #expect(await provider.callCount == 0)
        #expect(try store.loadRules().count == before)
        #expect(try store.reviewSegments().count == 1)
        #expect(try store.reviewSegments().first?.classification.isManual == true)
    }

    @Test func overlappingRunsAreRejectedAndCancellationDoesNotApplyOrCache() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let before = try store.loadRules().count
        let service = ReviewAIAnalysisService(store: store)
        let provider = GatedReviewProvider()
        let task = Task { try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: true) }
        await provider.waitUntilStarted()
        #expect(service.isRunning)
        do {
            _ = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: true)
            Issue.record("Overlapping run was accepted")
        } catch ReviewAIAnalysisError.alreadyRunning {
        }
        task.cancel()
        await provider.finish()
        do {
            _ = try await task.value
            Issue.record("Cancelled run completed")
        } catch is CancellationError {
        }
        #expect(!service.isRunning)
        #expect(try store.loadReviewAICache().isEmpty)
        #expect(try store.loadRules().count == before)
        #expect(try store.mostRecentReviewAIRun() == nil)
    }

    @Test func userChangesDuringAnalysisMakeTheResponseStale() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try saveEntry(in: store)
        let service = ReviewAIAnalysisService(store: store)
        let provider = GatedReviewProvider()
        let task = Task { try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: true) }
        await provider.waitUntilStarted()
        try store.overrideSegment(id: id, kind: .personal, projectID: nil, categoryID: SeedData.personalCategoryID)
        await provider.finish()
        let result = try await task.value
        #expect(result.analyzedGroups == 0)
        #expect(try store.loadReviewAICache().isEmpty)
        #expect(try store.recentSegments(limit: 1).first?.classification.kind == .personal)
    }

    @Test func automaticRulesDoNotChangeAlreadyClassifiedHistory() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let personalID = try saveEntry(in: store, kind: .personal)
        let before = try store.loadRules().count
        let result = try await ReviewAIAnalysisService(store: store).analyze(provider: CountingReviewProvider(), context: context, harnessVersion: nil, automaticallyApply: true)
        #expect(result.summary?.automaticallyAppliedCount == 0)
        #expect(try store.loadRules().count == before)
        #expect(try store.recentSegments(limit: 10).first { $0.id == personalID }?.classification.kind == .personal)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test func automaticRulesPreserveProjectsAndManualClassifications() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = Project(name: "Keep project", colorHex: "#123456", isArchived: false)
        try store.saveProject(project)
        let id = try saveEntry(in: store, projectID: project.id)
        let manualID = try saveEntry(in: store, kind: .personal, manual: true)
        let result = try await ReviewAIAnalysisService(store: store).analyze(provider: CountingReviewProvider(), context: context, harnessVersion: nil, automaticallyApply: true)
        #expect(result.summary?.automaticallyAppliedCount == 1)
        let entries = try store.recentSegments(limit: 10)
        #expect(entries.first { $0.id == id }?.classification.projectID == project.id)
        #expect(entries.first { $0.id == manualID }?.classification.kind == .personal)
        #expect(entries.first { $0.id == manualID }?.classification.isManual == true)
    }

    @Test func batchesAdvancePastPreviouslyReviewedGroups() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<52 { try saveEntry(in: store, host: "site\(index).example") }
        let service = ReviewAIAnalysisService(store: store)
        let provider = CountingReviewProvider()
        let first = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        let second = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        #expect(first.analyzedGroups == 50)
        #expect(second.analyzedGroups == 2)
        #expect(try store.loadReviewAICache().count == 52)
    }

    @Test func conflictingRelatedRuleBlocksAutomaticApply() {
        var suggestion = reviewAnswers(for: ReviewAISuggestionRequest(groups: [sampleGroup()]))[0]
        suggestion.relatedRuleKinds = [.personal]
        #expect(!ReviewAISuggestionValidator().automaticValidationResult(for: suggestion).canApply)
    }

    @Test func changedEvidenceIsAnalyzedButCannotBroadenTheRule() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let service = ReviewAIAnalysisService(store: store)
        let provider = CountingReviewProvider()
        _ = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        var changedContext = context
        changedContext.reasoning = .high
        _ = try await service.analyze(provider: provider, context: changedContext, harnessVersion: nil, automaticallyApply: false)
        #expect(await provider.callCount == 2)
        _ = try await service.analyze(provider: InvalidReviewProvider(broadenRule: true), context: context, harnessVersion: nil, automaticallyApply: true)
        let rule = try #require(try store.loadRules().first { $0.name == "Remember test.example as work" })
        #expect(rule.conditions.first?.field == .host)
        #expect(rule.conditions.first?.value == "test.example")
    }

    @Test func invalidResponseDoesNotSavePartialDecisions() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let service = ReviewAIAnalysisService(store: store)
        do {
            _ = try await service.analyze(provider: InvalidReviewProvider(broadenRule: false), context: context, harnessVersion: nil, automaticallyApply: true)
            Issue.record("Invalid response was accepted")
        } catch ReviewAIAnalysisError.invalidResponse {
        }
        #expect(!service.isRunning)
        #expect(try store.loadReviewAICache().isEmpty)
        #expect(try store.mostRecentReviewAIRun() == nil)
    }

    @Test func recommendationRunDoesNotHideTheLastAppliedRun() async throws {
        let (directory, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveEntry(in: store)
        let service = ReviewAIAnalysisService(store: store)
        let provider = CountingReviewProvider()
        let applied = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: true)
        try saveEntry(in: store, host: "second.example")
        let recommended = try await service.analyze(provider: provider, context: context, harnessVersion: nil, automaticallyApply: false)
        #expect(try store.mostRecentReviewAIRun()?.id == recommended.summary?.id)
        #expect(try store.mostRecentReviewAIRun(appliedRulesOnly: true)?.id == applied.summary?.id)
    }

    private func fixture() throws -> (URL, HagoStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return (directory, try HagoStore(databaseURL: directory.appendingPathComponent("test.sqlite")))
    }

    @discardableResult
    private func saveEntry(in store: HagoStore, host: String = "test.example", kind: ActivityKind = .review, manual: Bool = false, projectID: UUID? = nil) throws -> UUID {
        let start = Date().addingTimeInterval(-120)
        let segment = ActivitySegment(startedAt: start, endedAt: start.addingTimeInterval(60), snapshot: ActivitySnapshot(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 1, windowTitle: "Test", url: "https://\(host)", source: .chrome))
        try store.save(segment: segment, classification: SegmentClassification(segmentID: segment.id, kind: kind, categoryID: nil, projectID: projectID, ruleID: nil, isManual: manual))
        return segment.id
    }

    private func sampleGroup() -> ReviewAISuggestionGroup {
        ReviewAISuggestionGroup(id: "host|equals|test.example", proposedRuleCondition: RuleCondition(field: .host, operation: .equals, value: "test.example"), affectedCount: 1, affectedDuration: 60, samples: [ReviewAISuggestionSample(appName: "Chrome", bundleIdentifier: "chrome", windowTitle: "Test", url: nil, duration: 60)])
    }
}

private func reviewAnswers(for request: ReviewAISuggestionRequest) -> [ReviewAISuggestion] {
    request.groups.map {
        ReviewAISuggestion(id: $0.id, kind: .work, confidence: 0.99, reason: "Test recommendation", proposedRuleCondition: $0.proposedRuleCondition, affectedCount: $0.affectedCount, affectedDuration: $0.affectedDuration, samples: $0.samples)
    }
}

private actor CountingReviewProvider: ReviewAISuggestionProviding {
    private(set) var callCount = 0

    func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        callCount += 1
        return reviewAnswers(for: request)
    }
}

private struct InvalidReviewProvider: ReviewAISuggestionProviding {
    var broadenRule: Bool

    func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        guard broadenRule else { return [] }
        return reviewAnswers(for: request).map {
            var suggestion = $0
            suggestion.proposedRuleCondition = RuleCondition(field: .appName, operation: .equals, value: "Google Chrome")
            return suggestion
        }
    }
}

private actor GatedReviewProvider: ReviewAISuggestionProviding {
    private var request: ReviewAISuggestionRequest?
    private var completion: CheckedContinuation<[ReviewAISuggestion], any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        self.request = request
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard request == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        completion?.resume(returning: reviewAnswers(for: request!))
        completion = nil
    }
}
