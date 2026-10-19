import Foundation

public enum ReviewAISuggestionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case work
    case personal
    case ignored
    case unsure

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .work:
            "Work"
        case .personal:
            "Personal"
        case .ignored:
            "Ignored"
        case .unsure:
            "Unsure"
        }
    }

    var activityKind: ActivityKind? {
        switch self {
        case .work:
            .work
        case .personal:
            .personal
        case .ignored:
            .ignored
        case .unsure:
            nil
        }
    }
}

public struct ReviewAISuggestionSample: Equatable, Codable, Sendable {
    public var appName: String
    public var bundleIdentifier: String
    public var windowTitle: String
    public var url: String?
    public var duration: TimeInterval

    public init(
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        url: String?,
        duration: TimeInterval
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
        self.duration = duration
    }
}

public struct ReviewAISuggestionGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var proposedRuleCondition: RuleCondition
    public var affectedCount: Int
    public var affectedDuration: TimeInterval
    public var samples: [ReviewAISuggestionSample]
    public var relatedRules: [ReviewAIRelatedRule]

    public init(
        id: String,
        proposedRuleCondition: RuleCondition,
        affectedCount: Int,
        affectedDuration: TimeInterval,
        samples: [ReviewAISuggestionSample],
        relatedRules: [ReviewAIRelatedRule] = []
    ) {
        self.id = id
        self.proposedRuleCondition = proposedRuleCondition
        self.affectedCount = affectedCount
        self.affectedDuration = affectedDuration
        self.samples = samples
        self.relatedRules = relatedRules
    }
}

public struct ReviewAIRelatedRule: Equatable, Codable, Sendable {
    public var field: RuleField
    public var operation: RuleOperation
    public var value: String
    public var kind: ActivityKind

    public init(field: RuleField, operation: RuleOperation, value: String, kind: ActivityKind) {
        self.field = field
        self.operation = operation
        self.value = value
        self.kind = kind
    }
}

public struct ReviewAISuggestionRequest: Equatable, Sendable {
    public var groups: [ReviewAISuggestionGroup]

    public init(groups: [ReviewAISuggestionGroup]) {
        self.groups = groups
    }

    public init(reviewSegments: [ClassifiedSegment], existingRules: [Rule] = [], sampleLimit: Int = 3) {
        groups = ReviewAISuggestionGrouper().groups(
            from: reviewSegments,
            existingRules: existingRules,
            sampleLimit: sampleLimit
        )
    }
}

public struct ReviewAISuggestion: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var kind: ReviewAISuggestionKind
    public var confidence: Double
    public var reason: String
    public var proposedRuleCondition: RuleCondition?
    public var affectedCount: Int
    public var affectedDuration: TimeInterval
    public var samples: [ReviewAISuggestionSample]
    public var relatedRuleKinds: [ActivityKind]

    public init(
        id: String? = nil,
        kind: ReviewAISuggestionKind,
        confidence: Double,
        reason: String,
        proposedRuleCondition: RuleCondition?,
        affectedCount: Int,
        affectedDuration: TimeInterval,
        samples: [ReviewAISuggestionSample],
        relatedRuleKinds: [ActivityKind] = []
    ) {
        self.id = id ?? ReviewAISuggestion.stableID(
            kind: kind,
            condition: proposedRuleCondition,
            affectedCount: affectedCount
        )
        self.kind = kind
        self.confidence = confidence
        self.reason = reason
        self.proposedRuleCondition = proposedRuleCondition
        self.affectedCount = affectedCount
        self.affectedDuration = affectedDuration
        self.samples = samples
        self.relatedRuleKinds = relatedRuleKinds
    }

    private static func stableID(
        kind: ReviewAISuggestionKind,
        condition: RuleCondition?,
        affectedCount: Int
    ) -> String {
        [
            kind.rawValue,
            condition?.field.rawValue ?? "none",
            condition?.operation.rawValue ?? "none",
            condition?.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "none",
            String(affectedCount)
        ]
            .joined(separator: "|")
    }
}

public protocol ReviewAISuggestionProviding: Sendable {
    func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion]
}


public enum ReviewAISuggestionValidationResult: Equatable, Sendable {
    case applyAllowed
    case manualOnly(String)
    case rejected(String)

    public var canApply: Bool {
        self == .applyAllowed
    }
}

public struct ReviewAISuggestionValidator: Sendable {
    public static let minimumRecommendationConfidence = 0.75
    public static let minimumAutomaticApplyConfidence = 0.95

    public init() {}

    public func validationResult(for suggestion: ReviewAISuggestion) -> ReviewAISuggestionValidationResult {
        guard suggestion.kind != .unsure else {
            return .manualOnly("Unsure suggestions need a manual decision.")
        }

        guard let condition = suggestion.proposedRuleCondition else {
            return .rejected("Missing proposed rule condition.")
        }

        let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return .rejected("Empty rule condition.")
        }

        guard supported(condition: condition) else {
            return .rejected("Unsupported rule condition.")
        }

        guard !isBroadBrowserRule(condition: condition, samples: suggestion.samples) else {
            return .rejected("Browser app rules are too broad.")
        }

        return .applyAllowed
    }

    public func automaticValidationResult(
        for suggestion: ReviewAISuggestion,
        minimumConfidence: Double = Self.minimumAutomaticApplyConfidence
    ) -> ReviewAISuggestionValidationResult {
        guard suggestion.kind == .work || suggestion.kind == .personal else {
            return .manualOnly("Only Work and Personal suggestions can be applied automatically.")
        }

        guard suggestion.confidence >= minimumConfidence else {
            return .manualOnly("Confidence is below the automatic apply threshold.")
        }

        guard Set(suggestion.relatedRuleKinds).count <= 1 else {
            return .manualOnly("Related rules have conflicting results.")
        }
        guard suggestion.relatedRuleKinds.allSatisfy({ $0 == suggestion.kind.activityKind }) else {
            return .manualOnly("The suggestion conflicts with an existing rule.")
        }

        return validationResult(for: suggestion)
    }

    private func supported(condition: RuleCondition) -> Bool {
        switch condition.field {
        case .host:
            condition.operation == .equals || condition.operation == .domain
        case .url:
            condition.operation == .equals
        case .appName, .bundleIdentifier:
            condition.operation == .equals
        case .windowTitle:
            condition.operation == .contains || condition.operation == .equals
        }
    }

    private func isBroadBrowserRule(condition: RuleCondition, samples: [ReviewAISuggestionSample]) -> Bool {
        switch condition.field {
        case .appName, .bundleIdentifier:
            return isBrowserText(condition.value)
        case .windowTitle:
            return samples.contains { sample in
                isBrowserText(sample.appName) || isBrowserText(sample.bundleIdentifier)
            }
        case .host, .url:
            return false
        }
    }

    private func isBrowserText(_ value: String) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedValue.contains("chrome")
            || normalizedValue.contains("safari")
            || normalizedValue.contains("arc")
            || normalizedValue.contains("firefox")
    }
}

public struct ReviewAISuggestionGrouper: Sendable {
    public init() {}

    public func groups(
        from reviewSegments: [ClassifiedSegment],
        existingRules: [Rule] = [],
        sampleLimit: Int = 3
    ) -> [ReviewAISuggestionGroup] {
        var groupsByID: [String: [ClassifiedSegment]] = [:]
        var conditionsByID: [String: RuleCondition] = [:]

        for item in reviewSegments where item.classification.kind == .review {
            guard let condition = condition(for: item.segment.snapshot) else {
                continue
            }

            let id = groupID(for: condition)
            groupsByID[id, default: []].append(item)
            conditionsByID[id] = condition
        }

        return groupsByID.map { id, items in
            let condition = conditionsByID[id]!

            let sortedItems = items.sorted { first, second in
                first.segment.startedAt > second.segment.startedAt
            }

            return ReviewAISuggestionGroup(
                id: id,
                proposedRuleCondition: condition,
                affectedCount: items.count,
                affectedDuration: items.reduce(0) { $0 + $1.segment.duration },
                samples: sortedItems.prefix(sampleLimit).map { item in
                    sample(from: item, condition: condition)
                },
                relatedRules: relatedRules(for: condition, in: existingRules)
            )
        }
        .sorted { first, second in
            if first.affectedDuration == second.affectedDuration {
                return first.proposedRuleCondition.value.localizedCaseInsensitiveCompare(
                    second.proposedRuleCondition.value
                ) == .orderedAscending
            }

            return first.affectedDuration > second.affectedDuration
        }
    }

    private func condition(for snapshot: ActivitySnapshot) -> RuleCondition? {
        guard !snapshot.isDiscordWithoutTitle else { return nil }

        let host = snapshot.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty {
            return RuleCondition(field: .host, operation: .equals, value: host)
        }

        if let url = snapshot.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            return RuleCondition(field: .url, operation: .equals, value: url)
        }

        if isBrowser(snapshot: snapshot) {
            return nil
        }

        let windowTitle = snapshot.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if windowTitle.count >= 4 {
            return RuleCondition(field: .windowTitle, operation: .contains, value: windowTitle)
        }

        let appName = snapshot.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else {
            return nil
        }

        return RuleCondition(field: .appName, operation: .equals, value: appName)
    }

    private func groupID(for condition: RuleCondition) -> String {
        [
            condition.field.rawValue,
            condition.operation.rawValue,
            condition.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
            .joined(separator: "|")
    }

    private func relatedRules(for condition: RuleCondition, in rules: [Rule]) -> [ReviewAIRelatedRule] {
        rules
            .filter(\.enabled)
            .flatMap { rule in
                rule.conditions.compactMap { existingCondition -> ReviewAIRelatedRule? in
                    guard conditionsAreRelated(condition, existingCondition) else {
                        return nil
                    }
                    return ReviewAIRelatedRule(
                        field: existingCondition.field,
                        operation: existingCondition.operation,
                        value: existingCondition.value,
                        kind: rule.action.kind
                    )
                }
            }
            .sorted { first, second in
                let firstExact = first.value.caseInsensitiveCompare(condition.value) == .orderedSame
                let secondExact = second.value.caseInsensitiveCompare(condition.value) == .orderedSame
                if firstExact != secondExact {
                    return firstExact
                }
                return first.value.localizedCaseInsensitiveCompare(second.value) == .orderedAscending
            }
            .prefix(8)
            .map { $0 }
    }

    private func conditionsAreRelated(_ proposed: RuleCondition, _ existing: RuleCondition) -> Bool {
        if proposed.field == .host, existing.field == .host {
            return siteFamily(proposed.value) == siteFamily(existing.value)
        }

        guard proposed.field == existing.field else {
            return false
        }
        let proposedValue = proposed.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existingValue = existing.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return proposedValue == existingValue
    }

    private func siteFamily(_ host: String) -> String {
        let labels = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: ".")
            .map(String.init)
        guard labels.count > 2 else {
            return labels.joined(separator: ".")
        }

        let commonSecondLevelSuffixes: Set<String> = [
            "co.uk", "com.au", "co.jp", "co.nz", "co.za", "com.br", "com.cn",
            "com.hk", "com.mx", "com.sg", "com.tr", "com.tw"
        ]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let labelCount = commonSecondLevelSuffixes.contains(lastTwo) ? 3 : 2
        return labels.suffix(labelCount).joined(separator: ".")
    }

    private func sample(from item: ClassifiedSegment, condition: RuleCondition) -> ReviewAISuggestionSample {
        ReviewAISuggestionSample(
            appName: trimmed(item.segment.appName, limit: 80),
            bundleIdentifier: trimmed(item.segment.bundleIdentifier, limit: 120),
            windowTitle: trimmed(item.segment.windowTitle, limit: 120),
            url: condition.field == .url ? trimmed(item.segment.url, limit: 180) : nil,
            duration: item.segment.duration
        )
    }

    private func trimmed(_ value: String?, limit: Int) -> String? {
        guard let value else {
            return nil
        }

        return trimmedString(value, limit: limit)
    }

    private func trimmed(_ value: String, limit: Int) -> String {
        trimmedString(value, limit: limit)
    }

    private func trimmedString(_ value: String, limit: Int) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.count > limit else {
            return trimmedValue
        }

        return String(trimmedValue.prefix(limit))
    }

    private func isBrowser(snapshot: ActivitySnapshot) -> Bool {
        let appName = snapshot.appName.lowercased()
        let bundleIdentifier = snapshot.bundleIdentifier.lowercased()

        return appName.contains("chrome")
            || appName.contains("safari")
            || appName.contains("arc")
            || appName.contains("firefox")
            || bundleIdentifier.contains("chrome")
            || bundleIdentifier.contains("safari")
            || bundleIdentifier.contains("arc")
            || bundleIdentifier.contains("firefox")
    }
}
