import Foundation
import Testing
import HagoCore

@Suite
struct RememberedRuleFactoryTests {
    private let factory = RememberedRuleFactory()



    @Test
    func browserSegmentWithoutURLDoesNotCreateAppWideRule() {
        let rule = factory.rule(
            from: classifiedSegment(url: nil, title: ""),
            kind: .ignored,
            categoryID: nil
        )

        #expect(rule == nil)
    }


    @Test
    func untitledDiscordCannotCreateAnAppWideRule() {
        for kind in [ActivityKind.work, .personal, .ignored] {
            #expect(factory.rule(
                from: classifiedSegment(appName: "Discord", url: nil, title: "  ", source: .macOS),
                kind: kind,
                categoryID: nil
            ) == nil)
        }
    }

    /// Older builds stored Chrome's front tab under the web app, so an "always" rule for the app
    /// must leave those sites alone or remembering it would refile unrelated history.
    @Test
    func chromeWebAppCanBeRememberedWithoutClaimingMiscapturedSites() throws {
        let webApp = "com.google.Chrome.app.hnpfjngllnobngcgfapefoaidbinmjnm"
        let rule = try #require(factory.rule(
            from: classifiedSegment(appName: "WhatsApp Web", bundleIdentifier: webApp, url: nil, source: .macOS),
            kind: .personal,
            categoryID: nil
        ))
        let classifier = ActivityClassifier()
        let appOnly = classifiedSegment(appName: "WhatsApp Web", bundleIdentifier: webApp, url: nil, source: .macOS)
        let miscaptured = classifiedSegment(appName: "WhatsApp Web", bundleIdentifier: webApp, url: "https://github.com/pulls")

        #expect(classifier.classify(snapshot: appOnly.segment.snapshot, rules: [rule]).kind == .personal)
        #expect(classifier.classify(snapshot: miscaptured.segment.snapshot, rules: [rule]).kind == .review)
    }

    private func classifiedSegment(
        appName: String = "Google Chrome",
        bundleIdentifier: String? = nil,
        url: String?,
        title: String = "",
        source: ActivitySource = .chrome
    ) -> ClassifiedSegment {
        let segment = ActivitySegment(
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            snapshot: ActivitySnapshot(
                appName: appName,
                bundleIdentifier: bundleIdentifier ?? (appName == "Google Chrome" ? "com.google.Chrome" : "test.\(appName)"),
                processIdentifier: 1,
                windowTitle: title,
                url: url,
                source: source
            )
        )

        return ClassifiedSegment(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            ),
            projectName: nil,
            categoryName: nil,
            ruleName: nil
        )
    }
}
