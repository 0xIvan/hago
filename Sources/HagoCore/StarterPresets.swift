import Foundation

public struct StarterPreset: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var rules: [Rule]
}

public enum StarterPresets {
    public static let catalogVersion = 1
    public static let packs: [StarterPreset] = [
        StarterPreset(id: "general-work", name: "General Work", summary: "Shared tools stay unresolved until you confirm their purpose.", rules: []),
        StarterPreset(id: "software-development", name: "Software Development", summary: "Dedicated editors and local development sites are Work. Shared tools still need context.", rules: [
            app("40000000-0000-0000-0000-000000000001", "Xcode", "com.apple.dt.Xcode"),
            app("40000000-0000-0000-0000-000000000002", "Visual Studio Code", "com.microsoft.VSCode"),
            app("40000000-0000-0000-0000-000000000003", "Cursor", "com.todesktop.230313mzl4w4u92"),
            app("40000000-0000-0000-0000-000000000004", "Android Studio", "com.google.android.studio"),
            app("40000000-0000-0000-0000-000000000005", "IntelliJ IDEA", "com.jetbrains.intellij"),
            Rule(id: UUID(uuidString: "40000000-0000-0000-0000-000000000006")!, name: "Local development", priority: 500,
                 enabled: true, isBuiltIn: true, action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
                 conditions: [RuleCondition(field: .host, operation: .equals, value: "localhost")], origin: .preset, presetID: "software-development")
        ])
    ]

    private static func app(_ id: String, _ name: String, _ bundle: String) -> Rule {
        Rule(id: UUID(uuidString: id)!, name: "\(name) is Work", priority: 500, enabled: true, isBuiltIn: true,
             action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
             conditions: [RuleCondition(field: .bundleIdentifier, operation: .equals, value: bundle)],
             origin: .preset, presetID: "software-development")
    }
}

public struct RuleImpactPreview: Sendable {
    public var affectedCount: Int
    public var affectedSeconds: TimeInterval
    public var examples: [String]
}

public struct CorrectionLearningSuggestion: Identifiable, Sendable {
    public var id: String
    public var rule: Rule
    public var days: Int
    public var evidenceKey: String
}
