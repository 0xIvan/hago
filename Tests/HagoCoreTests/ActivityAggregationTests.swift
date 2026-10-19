import Foundation
import Testing
@testable import HagoCore

struct ActivityAggregationTests {
    @Test
    func reviewCombinesRepeatedWindowsWithoutMixingChannels() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let missing = (0..<600).map { index in
            classifiedSegment(start: start.addingTimeInterval(Double(index) * 120), duration: 60,
                              appName: "Discord", windowTitle: "", kind: .review)
        }
        let titled = classifiedSegment(start: start, duration: 90, appName: "Discord", windowTitle: "#work", kind: .review)
        let classified = classifiedSegment(start: start, duration: 45, appName: "Discord", windowTitle: "", kind: .work)
        let groups = ActivityAggregation.reviewGroups(from: missing + [titled, classified])
        let group = try #require(groups.first { $0.segmentCount == 600 })
        #expect(groups.count == 2)
        #expect(group.duration == 36_000)
        #expect(Set(group.segmentIDs) == Set(missing.map(\.id)))
        #expect(group.firstStartedAt == start)
        #expect(group.lastEndedAt == missing.last?.segment.endedAt)
    }

    @Test
    func groupsChromeSegmentsByHostAndClassification() {
        let start = Date(timeIntervalSince1970: 1_000)
        let segments = [
            classifiedSegment(
                start: start,
                duration: 60,
                url: "https://example.com/first",
                kind: .work
            ),
            classifiedSegment(
                start: start.addingTimeInterval(120),
                duration: 90,
                url: "https://example.com/second",
                kind: .work
            ),
            classifiedSegment(
                start: start.addingTimeInterval(240),
                duration: 30,
                url: "https://example.com/personal",
                kind: .personal
            )
        ]

        let groups = ActivityAggregation.groups(from: segments)
            .sorted { $0.kind.rawValue < $1.kind.rawValue }

        #expect(groups.count == 2)
        #expect(groups[0].name == "example.com")
        #expect(groups[0].duration == 30)
        #expect(groups[0].segmentCount == 1)
        #expect(groups[0].segmentIDs.count == 1)
        #expect(groups[1].name == "example.com")
        #expect(groups[1].duration == 150)
        #expect(groups[1].segmentCount == 2)
        #expect(groups[1].segmentIDs.count == 2)
    }

    @Test
    func groupsMacSegmentsByApp() {
        let start = Date(timeIntervalSince1970: 2_000)
        let segments = [
            classifiedSegment(start: start, duration: 45, appName: "Xcode"),
            classifiedSegment(start: start.addingTimeInterval(60), duration: 75, appName: "Xcode")
        ]

        let group = ActivityAggregation.groups(from: segments).first

        #expect(group?.name == "Xcode")
        #expect(group?.duration == 120)
        #expect(group?.segmentCount == 2)
    }

    @Test
    func recordsAllAppliedRulesForAGroupWithoutDuplicates() {
        let start = Date(timeIntervalSince1970: 3_000)
        let firstRuleID = UUID()
        let secondRuleID = UUID()
        let segments = [
            classifiedSegment(start: start, duration: 30, ruleID: firstRuleID),
            classifiedSegment(start: start.addingTimeInterval(60), duration: 30, ruleID: firstRuleID),
            classifiedSegment(start: start.addingTimeInterval(120), duration: 30, ruleID: secondRuleID)
        ]

        let group = ActivityAggregation.groups(from: segments).first

        #expect(group?.appliedRuleIDs == [firstRuleID, secondRuleID])
    }

    private func classifiedSegment(
        start: Date,
        duration: TimeInterval,
        appName: String = "Google Chrome",
        url: String? = nil,
        windowTitle: String = "Test",
        kind: ActivityKind = .work,
        ruleID: UUID? = nil
    ) -> ClassifiedSegment {
        let segment = ActivitySegment(
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            snapshot: ActivitySnapshot(
                appName: appName,
                bundleIdentifier: "test.\(appName)",
                processIdentifier: 1,
                windowTitle: windowTitle,
                url: url,
                source: url == nil ? .macOS : .chrome
            )
        )

        return ClassifiedSegment(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: kind,
                categoryID: nil,
                projectID: nil,
                ruleID: ruleID,
                isManual: false
            ),
            projectName: nil,
            categoryName: nil,
            ruleName: nil
        )
    }
}
