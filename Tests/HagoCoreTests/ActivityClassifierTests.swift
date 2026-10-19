import Foundation
import Testing
import HagoCore

@Suite
struct ActivityClassifierTests {
    private let classifier = ActivityClassifier()
    private let rules = SeedData.rules

    @Test
    func cursorIsWork() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Cursor", title: "Example Project"),
            rules: rules
        )

        #expect(result.kind == .work)
        #expect(result.projectID == nil)
    }

    @Test
    func visualStudioCodeIsWorkWithoutARecognizedRepository() {
        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Code",
                bundleIdentifier: "com.microsoft.VSCode",
                title: "Untitled-1"
            ),
            rules: rules
        )

        #expect(result.kind == .work)
        #expect(result.projectID == nil)
    }

    @Test
    func visualStudioCodeRepositoryRuleAssignsTheProjectBeforeTheAppFallback() {
        let projectID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let repositoryRule = Rule(
            name: "Reflekt repository",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: projectID
            ),
            conditions: [
                RuleCondition(field: .windowTitle, operation: .contains, value: "Reflekt")
            ]
        )

        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Code",
                bundleIdentifier: "com.microsoft.VSCode",
                title: "chat-messages.tsx — Reflekt-UI"
            ),
            rules: rules + [repositoryRule]
        )

        #expect(result.kind == .work)
        #expect(result.projectID == projectID)
        #expect(result.ruleID == repositoryRule.id)
    }

    @Test
    func localhostChromeIsWork() {
        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Google Chrome",
                title: "Local app",
                url: "http://localhost:5173/dashboard"
            ),
            rules: rules
        )

        #expect(result.kind == .work)
    }

    @Test
    func finderIsPersonal() {
        let result = classifier.classify(snapshot: snapshot(appName: "Finder"), rules: rules)

        #expect(result.kind == .personal)
    }

    @Test
    func discordJianYangWorkChannelIsWork() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Discord", title: "#work | Jian Yang - Discord"),
            rules: rules
        )

        #expect(result.kind == .work)
        #expect(result.categoryID == SeedData.workCategoryID)
    }

    @Test
    func otherDiscordChannelsArePersonal() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Discord", title: "#general | Jian Yang - Discord"),
            rules: rules
        )

        #expect(result.kind == .personal)
    }

    @Test
    func discordWithoutACapturedTitleNeedsReview() {
        for title in ["", "  \n"] {
            let activity = snapshot(appName: "Discord", title: title)
            let result = classifier.classify(snapshot: activity, rules: rules)
            #expect(result.kind == .review)
            #expect(result.ruleID == nil)
            #expect(classifier.classify(snapshot: activity, rules: []).kind == .review)
        }
    }

    @Test
    func explicitDiscordRulesStillApplyWithoutATitle() {
        for kind in [ActivityKind.work, .personal, .ignored] {
            let explicitRule = Rule(
                name: "Explicit Discord classification",
                priority: 20,
                enabled: true,
                isBuiltIn: false,
                action: RuleAction(kind: kind, categoryID: nil, projectID: nil),
                conditions: [RuleCondition(field: .appName, operation: .equals, value: "Discord")]
            )
            let result = classifier.classify(snapshot: snapshot(appName: "Discord"), rules: rules + [explicitRule])
            #expect(result.kind == kind)
            #expect(result.ruleID == explicitRule.id)
        }
    }

    @Test
    func missingDiscordTitleDoesNotOverrideAnIgnoreRule() {
        let ignoreRule = Rule(
            name: "Ignore Discord",
            priority: 10,
            enabled: true,
            isBuiltIn: true,
            action: RuleAction(kind: .ignored, categoryID: nil, projectID: nil),
            conditions: [RuleCondition(field: .appName, operation: .equals, value: "Discord")]
        )
        let result = classifier.classify(snapshot: snapshot(appName: "Discord"), rules: rules + [ignoreRule])
        #expect(result.kind == .ignored)
    }

    @Test
    func chromeExtensionPagesAreIgnored() {
        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Google Chrome",
                title: "Extension",
                url: "chrome-extension://example/options.html"
            ),
            rules: rules
        )

        #expect(result.kind == .ignored)
    }

    @Test
    func privateSnapshotIsIgnored() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Google Chrome", title: "Example", isPrivate: true),
            rules: []
        )

        #expect(result.kind == .ignored)
    }

    @Test
    func loginwindowIsIgnored() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "loginwindow", bundleIdentifier: "com.apple.loginwindow"),
            rules: []
        )

        #expect(result.kind == .ignored)
    }

    @Test
    func unknownChromeNeedsReview() {
        let result = classifier.classify(
            snapshot: snapshot(appName: "Google Chrome", title: "Search"),
            rules: rules
        )

        #expect(result.kind == .review)
    }

    @Test
    func domainRuleMatchesRootAndSubdomainsButNotLookalikes() {
        let domainRule = Rule(
            name: "Emirates domain",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .personal, categoryID: SeedData.personalCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .host, operation: .domain, value: "emirates.com")
            ]
        )

        let root = classifier.classify(
            snapshot: snapshot(appName: "Google Chrome", url: "https://emirates.com"),
            rules: [domainRule]
        )
        let subdomain = classifier.classify(
            snapshot: snapshot(appName: "Google Chrome", url: "https://accounts.emirates.com"),
            rules: [domainRule]
        )
        let lookalike = classifier.classify(
            snapshot: snapshot(appName: "Google Chrome", url: "https://notemirates.com"),
            rules: [domainRule]
        )

        #expect(root.kind == .personal)
        #expect(subdomain.kind == .personal)
        #expect(lookalike.kind == .review)
    }

    @Test
    func generatedBrowserAppRuleDoesNotOverrideReview() {
        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Google Chrome",
                title: "Different host",
                url: "https://different.example.com"
            ),
            rules: [
                Rule(
                    name: "Remember Google Chrome",
                    priority: 150,
                    enabled: true,
                    isBuiltIn: false,
                    action: RuleAction(kind: .ignored, categoryID: nil, projectID: nil),
                    conditions: [
                        RuleCondition(field: .appName, operation: .equals, value: "Google Chrome")
                    ]
                )
            ]
        )

        #expect(result.kind == .review)
    }

    @Test
    func explicitBrowserAppRuleStillApplies() {
        let result = classifier.classify(
            snapshot: snapshot(
                appName: "Google Chrome",
                title: "Different host",
                url: "https://different.example.com"
            ),
            rules: [
                Rule(
                    name: "Ignore all Chrome",
                    priority: 150,
                    enabled: true,
                    isBuiltIn: false,
                    action: RuleAction(kind: .ignored, categoryID: nil, projectID: nil),
                    conditions: [
                        RuleCondition(field: .appName, operation: .equals, value: "Google Chrome")
                    ]
                )
            ]
        )

        #expect(result.kind == .ignored)
    }

    private func snapshot(
        appName: String,
        bundleIdentifier: String? = nil,
        title: String = "",
        url: String? = nil,
        isPrivate: Bool = false
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier ?? (appName == "Google Chrome" ? "com.google.Chrome" : "test.\(appName)"),
            processIdentifier: 1,
            windowTitle: title,
            url: url,
            source: url == nil ? .macOS : .chrome,
            isPrivate: isPrivate
        )
    }
}
