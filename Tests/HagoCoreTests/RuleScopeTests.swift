import Foundation
import Testing
@testable import HagoCore

/// Editing a rule in the simple editor rewrites its conditions from its scope,
/// so every parsed shape must rebuild to the same match.
@Suite
struct RuleScopeTests {
    @Test
    func parsedScopesRebuildTheSameConditions() {
        let shapes: [[RuleCondition]] = [
            [condition(.bundleIdentifier, .equals, "com.tinyspeck.slackmacgap")],
            [condition(.bundleIdentifier, .equals, "com.hnc.Discord"), condition(.windowTitle, .contains, "#work")],
            [condition(.bundleIdentifier, .equals, "com.apple.Notes"), condition(.windowTitle, .equals, "Standup")],
            [condition(.host, .domain, "github.com")],
            [condition(.host, .equals, "www.figma.com")],
            [condition(.host, .domain, "google.com"), condition(.windowTitle, .contains, "Acme")],
            [condition(.host, .equals, "github.com"), condition(.url, .equals, "https://github.com/acme/repo")],
            [condition(.url, .startsWith, "https://github.com/acme")],
            [condition(.url, .equals, "about:blank")],
            [condition(.windowTitle, .contains, "Dashlane")]
        ]

        for conditions in shapes {
            let scope = RuleScope(conditions: conditions)
            #expect(scope != nil)
            let rebuilt = scope?.conditions ?? []
            let snapshots = [
                ActivitySnapshot(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", processIdentifier: 1,
                                 windowTitle: "general", url: nil, source: .macOS),
                ActivitySnapshot(appName: "Discord", bundleIdentifier: "com.hnc.Discord", processIdentifier: 1,
                                 windowTitle: "#work | Acme", url: nil, source: .macOS),
                ActivitySnapshot(appName: "Notes", bundleIdentifier: "com.apple.Notes", processIdentifier: 1,
                                 windowTitle: "Standup", url: nil, source: .macOS),
                chrome("https://github.com/acme/repo", title: "Acme repo"),
                chrome("https://docs.github.com/en", title: "Docs"),
                chrome("https://www.figma.com/file/1", title: "Design"),
                chrome("https://mail.google.com/u/0", title: "Inbox - Acme"),
                chrome("https://github.com/acme/repo/issues", title: "Issues"),
                chrome("about:blank", title: "Dashlane")
            ]
            for snapshot in snapshots {
                #expect(matches(conditions, snapshot) == matches(rebuilt, snapshot), "\(conditions) vs \(rebuilt)")
            }
        }
    }

    @Test
    func advancedShapesStayCustom() {
        #expect(RuleScope(conditions: [condition(.appName, .contains, "Slack")]) == nil)
        #expect(RuleScope(conditions: [condition(.url, .regex, "^https://")]) == nil)
        #expect(RuleScope(conditions: [condition(.url, .contains, "figma")]) == nil)
        #expect(RuleScope(conditions: [condition(.bundleIdentifier, .equals, "a"), condition(.host, .equals, "b.com")]) == nil)
    }

    private func matches(_ conditions: [RuleCondition], _ snapshot: ActivitySnapshot) -> Bool {
        ActivityClassifier().matches(
            rule: Rule(name: "", priority: 1, enabled: true, isBuiltIn: false,
                       action: RuleAction(kind: .work, categoryID: nil, projectID: nil), conditions: conditions),
            snapshot: snapshot
        )
    }

    private func chrome(_ url: String, title: String) -> ActivitySnapshot {
        ActivitySnapshot(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 1,
                         windowTitle: title, url: url, source: .chrome)
    }

    private func condition(_ field: RuleField, _ operation: RuleOperation, _ value: String) -> RuleCondition {
        RuleCondition(field: field, operation: operation, value: value)
    }
}
