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

    private func classifiedSegment(
        appName: String = "Google Chrome",
        url: String?,
        title: String = "",
        source: ActivitySource = .chrome
    ) -> ClassifiedSegment {
        let segment = ActivitySegment(
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            snapshot: ActivitySnapshot(
                appName: appName,
                bundleIdentifier: appName == "Google Chrome" ? "com.google.Chrome" : "test.\(appName)",
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
