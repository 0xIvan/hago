import Foundation
import Testing
import HagoCore

struct ActivityTimelineTests {
    @Test
    func preservesClockTimesAndClipsBothDayBoundaries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HagoStore(databaseURL: directory.appendingPathComponent("hago.sqlite"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z"))
        let interval = HagoCalendar.shared.dayInterval(containing: date)
        let segments = [
            segment(start: interval.end.addingTimeInterval(-600), duration: 1_200, kind: .review),
            segment(start: interval.start.addingTimeInterval(-900), duration: 1_800, kind: .work),
            segment(start: interval.start.addingTimeInterval(2_700), duration: 2_700, kind: .personal),
            segment(start: interval.start.addingTimeInterval(7_200), duration: 3_600, kind: .ignored),
            segment(start: interval.start.addingTimeInterval(-7_200), duration: 600, kind: .work),
            segment(start: interval.end, duration: 600, kind: .work)
        ]
        for item in segments {
            try store.save(segment: item.segment, classification: item.classification)
        }

        let entries = try store.dayTimeline(for: date)

        #expect(entries.count == 3)
        #expect(entries.map(\.classification.kind) == [.work, .personal, .review])
        #expect(entries.first?.segment.startedAt == interval.start)
        #expect(entries.first?.segment.endedAt == interval.start.addingTimeInterval(900))
        #expect(entries.last?.segment.endedAt == interval.end)
        #expect(entries[1].segment.startedAt == segments[2].segment.startedAt)
        #expect(entries[1].segment.duration == 2_700)

        let summary = try store.daySummary(for: date)
        #expect(summary.workSeconds == 900)
        #expect(summary.personalSeconds == 2_700)
        #expect(summary.reviewSeconds == 600)
        #expect(summary.topApps.first { $0.kind == .work }?.seconds == 900)

        let beforeCutoff = try store.dayTimeline(for: interval.end.addingTimeInterval(-60))
        #expect(beforeCutoff == entries)
        let nextDay = try store.dayTimeline(for: interval.end)
        #expect(nextDay.first?.segment.startedAt == interval.end)
        #expect(nextDay.first?.segment.duration == 600)
        #expect(try store.daySummary(for: interval.end).reviewSeconds == 600)
    }

    @Test
    func emptyDayHasNoTimelineEntries() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 24 * 3_600)
        #expect(ActivityAggregation.timeline(from: [], in: interval).isEmpty)
    }

    @Test
    func preservesIdleGapsBetweenActivities() {
        let start = Date(timeIntervalSince1970: 0)
        let first = segment(start: start, duration: 120, kind: .work)
        let second = segment(start: start.addingTimeInterval(3_600), duration: 60, kind: .work)
        let ignored = segment(start: start.addingTimeInterval(120), duration: 900, kind: .ignored)
        let interval = DateInterval(start: start, duration: 24 * 3_600)
        let entries = ActivityAggregation.timeline(from: [second, ignored, first], in: interval)

        #expect(entries.map(\.id) == [first.id, second.id])
        #expect(entries[0].segment.startedAt == first.segment.startedAt)
        #expect(entries[0].segment.endedAt == first.segment.endedAt)
        #expect(entries[1].segment.startedAt == second.segment.startedAt)
        #expect(entries[1].segment.endedAt == second.segment.endedAt)
        #expect(entries[1].segment.startedAt.timeIntervalSince(entries[0].segment.endedAt) == 3_480)
    }

    @Test
    func mergesTouchingActivityOfTheSameKindWithoutChangingCoverage() {
        let start = Date(timeIntervalSince1970: 0)
        let first = segment(start: start, duration: 60, kind: .work)
        var second = segment(start: start.addingTimeInterval(60), duration: 120, kind: .work)
        second.segment.appName = "Another App"
        let third = segment(start: start.addingTimeInterval(180), duration: 30, kind: .personal)
        let spans = ActivityAggregation.timelineSpans(from: [third, second, first])

        #expect(spans.count == 2)
        #expect(spans[0].kind == .work)
        #expect(spans[0].startedAt == first.segment.startedAt)
        #expect(spans[0].endedAt == second.segment.endedAt)
        #expect(spans[1].kind == .personal)
        #expect(spans[1].startedAt == third.segment.startedAt)
        #expect(spans.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) } == 210)
    }

    @Test
    func neverMergesAcrossRealGapsIgnoredTimeOrClassificationChanges() {
        let start = Date(timeIntervalSince1970: 0)
        let entries = [
            segment(start: start, duration: 5, kind: .work),
            segment(start: start.addingTimeInterval(5.5), duration: 5, kind: .work),
            segment(start: start.addingTimeInterval(10.5), duration: 5, kind: .personal),
            segment(start: start.addingTimeInterval(15.5), duration: 5, kind: .work),
            segment(start: start.addingTimeInterval(20.5), duration: 5, kind: .ignored),
            segment(start: start.addingTimeInterval(25.5), duration: 5, kind: .work)
        ]
        let spans = ActivityAggregation.timelineSpans(from: entries)

        #expect(spans.count == 5)
        #expect(spans.map(\.kind) == [.work, .work, .personal, .work, .work])
        #expect(spans[1].startedAt.timeIntervalSince(spans[0].endedAt) == 0.5)
        #expect(spans[4].startedAt.timeIntervalSince(spans[3].endedAt) == 5)
        #expect(spans.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) } == 25)
    }

    private func segment(start: Date, duration: TimeInterval, kind: ActivityKind) -> ClassifiedSegment {
        let segment = ActivitySegment(
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            snapshot: ActivitySnapshot(
                appName: "Timeline Test",
                bundleIdentifier: "test.timeline",
                processIdentifier: 1,
                windowTitle: "Test",
                url: nil,
                source: .macOS
            )
        )
        return ClassifiedSegment(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: kind,
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
