import Foundation

public enum RuleOrigin: String, CaseIterable, Codable, Identifiable, Sendable {
    case ai
    case learned
    case custom
    case builtIn

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ai:
            "AI Applied"
        case .learned:
            "Learned"
        case .custom:
            "Custom"
        case .builtIn:
            "Built-in"
        }
    }
}

public enum RuleReviewIssue: String, CaseIterable, Codable, Identifiable, Sendable {
    case conflict
    case duplicate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .conflict:
            "Conflicting result"
        case .duplicate:
            "Duplicate match"
        }
    }
}

public struct RuleReviewRecord: Identifiable, Equatable, Codable, Sendable {
    public var rule: Rule
    public var origin: RuleOrigin
    public var matchedSegmentCount: Int
    public var issues: Set<RuleReviewIssue>

    public init(
        rule: Rule,
        origin: RuleOrigin,
        matchedSegmentCount: Int,
        issues: Set<RuleReviewIssue>
    ) {
        self.rule = rule
        self.origin = origin
        self.matchedSegmentCount = matchedSegmentCount
        self.issues = issues
    }

    public var id: UUID { rule.id }
}
