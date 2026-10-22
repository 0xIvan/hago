import Foundation

public enum RuleField: String, CaseIterable, Codable, Identifiable, Sendable {
    case appName
    case bundleIdentifier
    case windowTitle
    case url
    case host

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .appName:
            "App"
        case .bundleIdentifier:
            "Bundle ID"
        case .windowTitle:
            "Window Title"
        case .url:
            "URL"
        case .host:
            "Host"
        }
    }
}

public enum RuleOperation: String, CaseIterable, Codable, Identifiable, Sendable {
    case contains
    case equals
    case domain
    case startsWith
    case endsWith
    case regex

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .contains:
            "contains"
        case .equals:
            "equals"
        case .domain:
            "is domain or subdomain of"
        case .startsWith:
            "starts with"
        case .endsWith:
            "ends with"
        case .regex:
            "matches regex"
        }
    }
}

public struct RuleCondition: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var field: RuleField
    public var operation: RuleOperation
    public var value: String

    public init(
        id: UUID = UUID(),
        field: RuleField,
        operation: RuleOperation,
        value: String
    ) {
        self.id = id
        self.field = field
        self.operation = operation
        self.value = value
    }
}

public struct RuleAction: Equatable, Codable, Sendable {
    public var kind: ActivityKind
    public var categoryID: UUID?
    public var projectID: UUID?

    public init(kind: ActivityKind, categoryID: UUID?, projectID: UUID?) {
        self.kind = kind
        self.categoryID = categoryID
        self.projectID = projectID
    }
}

public enum ClassificationRuleOrigin: String, Codable, Sendable {
    case legacy
    case user
    case preset
    case ai
}

public struct Rule: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var priority: Int
    public var enabled: Bool
    public var isBuiltIn: Bool
    public var action: RuleAction
    public var conditions: [RuleCondition]
    public var origin: ClassificationRuleOrigin?
    public var presetID: String?
    public var parentRuleID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        priority: Int,
        enabled: Bool,
        isBuiltIn: Bool,
        action: RuleAction,
        conditions: [RuleCondition],
        origin: ClassificationRuleOrigin? = nil,
        presetID: String? = nil,
        parentRuleID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.priority = priority
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
        self.action = action
        self.conditions = conditions
        self.origin = origin
        self.presetID = presetID
        self.parentRuleID = parentRuleID
    }
}

public struct Category: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ActivityKind
    public var colorHex: String

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ActivityKind,
        colorHex: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
    }
}

public struct Project: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        isArchived: Bool
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isArchived = isArchived
    }
}

public struct ClassificationResult: Equatable, Sendable {
    public var kind: ActivityKind
    public var categoryID: UUID?
    public var projectID: UUID?
    public var ruleID: UUID?
    public var reason: String

    public init(kind: ActivityKind, categoryID: UUID?, projectID: UUID?, ruleID: UUID?, reason: String = "Needs context") {
        self.reason = reason
        self.kind = kind
        self.categoryID = categoryID
        self.projectID = projectID
        self.ruleID = ruleID
    }
}
