import Foundation

public enum ReviewAIRuleChange: String, Codable, Sendable {
    case created
    case reenabled
    case reused
}

public enum ReviewAIDecisionDisposition: String, Codable, Sendable {
    case pendingAutomaticApply
    case automaticallyApplied
    case recommended
    case rejected
    case stale
}

public enum ReviewAIRunStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case undone
    case partiallyUndone
}

public struct ReviewAIRunSummary: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var harness: ReviewAIHarnessKind
    public var harnessVersion: String?
    public var decisionCount: Int
    public var automaticallyAppliedCount: Int
    public var recommendationCount: Int
    public var status: ReviewAIRunStatus

    public init(
        id: UUID,
        createdAt: Date,
        harness: ReviewAIHarnessKind,
        harnessVersion: String?,
        decisionCount: Int,
        automaticallyAppliedCount: Int,
        recommendationCount: Int,
        status: ReviewAIRunStatus
    ) {
        self.id = id
        self.createdAt = createdAt
        self.harness = harness
        self.harnessVersion = harnessVersion
        self.decisionCount = decisionCount
        self.automaticallyAppliedCount = automaticallyAppliedCount
        self.recommendationCount = recommendationCount
        self.status = status
    }
}

public enum ReviewAIAppliedRuleState: String, Codable, Sendable {
    case unchanged
    case changed
    case removed
}

public struct ReviewAIAppliedRule: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var ruleID: UUID
    public var confidence: Double
    public var reason: String
    public var ruleChange: ReviewAIRuleChange
    public var appliedCondition: RuleCondition
    public var appliedKind: ActivityKind
    public var currentRule: Rule?
    public var state: ReviewAIAppliedRuleState

    public init(
        id: UUID,
        ruleID: UUID,
        confidence: Double,
        reason: String,
        ruleChange: ReviewAIRuleChange,
        appliedCondition: RuleCondition,
        appliedKind: ActivityKind,
        currentRule: Rule?,
        state: ReviewAIAppliedRuleState
    ) {
        self.id = id
        self.ruleID = ruleID
        self.confidence = confidence
        self.reason = reason
        self.ruleChange = ruleChange
        self.appliedCondition = appliedCondition
        self.appliedKind = appliedKind
        self.currentRule = currentRule
        self.state = state
    }
}

public struct ReviewAIUndoResult: Equatable, Sendable {
    public var revertedRuleCount: Int
    public var unchangedRuleCount: Int
    public var conflictCount: Int

    public init(revertedRuleCount: Int, unchangedRuleCount: Int, conflictCount: Int) {
        self.revertedRuleCount = revertedRuleCount
        self.unchangedRuleCount = unchangedRuleCount
        self.conflictCount = conflictCount
    }
}
