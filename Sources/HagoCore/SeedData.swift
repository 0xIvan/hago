import Foundation

public enum SeedData {
    public static let workCategoryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    public static let personalCategoryID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    public static let reviewCategoryID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    public static var categories: [Category] {
        [
            Category(id: workCategoryID, name: "Work", kind: .work, colorHex: "#2563EB"),
            Category(id: personalCategoryID, name: "Personal", kind: .personal, colorHex: "#16A34A"),
            Category(id: reviewCategoryID, name: "Needs Review", kind: .review, colorHex: "#D97706")
        ]
    }

    public static var projects: [Project] {
        []
    }

    public static var rules: [Rule] {
        ignoreRules
    }

    private static var ignoreRules: [Rule] {
        [
            rule(
                id: "00000000-0000-0000-0000-000000000003",
                name: "Ignore Chrome extension pages",
                priority: 10,
                kind: .ignored,
                field: .url,
                operation: .startsWith,
                value: "chrome-extension://"
            ),
            rule(
                id: "00000000-0000-0000-0000-000000000004",
                name: "Ignore incognito windows",
                priority: 10,
                kind: .ignored,
                field: .windowTitle,
                operation: .contains,
                value: "Incognito"
            )
        ]
    }

    private static func rule(
        id: String,
        name: String,
        priority: Int,
        kind: ActivityKind,
        projectID: UUID? = nil,
        field: RuleField,
        operation: RuleOperation,
        value: String
    ) -> Rule {
        Rule(
            id: UUID(uuidString: id)!,
            name: name,
            priority: priority,
            enabled: true,
            isBuiltIn: true,
            action: RuleAction(
                kind: kind,
                categoryID: categoryID(for: kind),
                projectID: projectID
            ),
            conditions: [
                RuleCondition(field: field, operation: operation, value: value)
            ]
        )
    }

    private static func categoryID(for kind: ActivityKind) -> UUID? {
        switch kind {
        case .work:
            workCategoryID
        case .personal:
            personalCategoryID
        case .review:
            reviewCategoryID
        case .ignored:
            nil
        }
    }
}
