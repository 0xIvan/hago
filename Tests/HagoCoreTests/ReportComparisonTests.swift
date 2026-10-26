import Foundation
import Testing

@testable import HagoCore

@Suite
struct ReportComparisonTests {
    @Test
    func partialWeekAlignsTrackingDaysAndLocalClockBeforeFourAM() throws {
        let calendar = try calendar("UTC")
        let now = try date("2026-10-22T03:30:00Z")
        let window = ReportComparisonWindow(for: .week, containing: now, now: now, calendar: calendar)
        #expect(window.currentPeriod.start == (try date("2026-10-19T04:00:00Z")))
        #expect(window.currentPeriod.end == (try date("2026-10-26T04:00:00Z")))
        #expect(window.currentData.end == now)
        #expect(window.previousData.end == (try date("2026-10-15T03:30:00Z")))
        #expect(window.comparesElapsedPortion)
    }

    @Test
    func monthlyComparisonClampsShorterPriorMonthsWithoutRollingForward() throws {
        let calendar = try calendar("UTC")
        let march29 = try date("2026-03-29T12:00:00Z")
        let short = ReportComparisonWindow(for: .month, containing: march29, now: march29, calendar: calendar)
        #expect(short.previousData == short.previousPeriod)
        #expect(short.previousData.end == (try date("2026-03-01T04:00:00Z")))
        let march28 = try date("2026-03-28T12:00:00Z")
        let partial = ReportComparisonWindow(for: .month, containing: march28, now: march28, calendar: calendar)
        #expect(partial.previousData.end == (try date("2026-02-28T12:00:00Z")))
    }

    @Test
    func historicalPeriodsCompareInFullAndFuturePeriodsHaveNoElapsedTime() throws {
        let calendar = try calendar("UTC")
        let now = try date("2026-10-22T12:00:00Z")
        for kind in [ReportPeriodKind.week, .month] {
            let old = ReportComparisonWindow(
                for: kind, containing: try date("2025-12-25T12:00:00Z"), now: now, calendar: calendar)
            #expect(old.currentData == old.currentPeriod)
            #expect(old.previousData == old.previousPeriod)
            #expect(!old.comparesElapsedPortion)
            let future = ReportComparisonWindow(
                for: kind, containing: try date("2027-01-25T12:00:00Z"), now: now, calendar: calendar)
            #expect(future.currentData.duration == 0)
            #expect(future.previousData.duration == 0)
        }
    }

    @Test
    func calendarAlignmentDoesNotShiftPriorClockTimeAcrossDaylightSaving() throws {
        let calendar = try calendar("America/New_York")
        let now = try date("2026-03-09T02:00:00Z")
        let window = ReportComparisonWindow(for: .week, containing: now, now: now, calendar: calendar)
        #expect(calendar.component(.hour, from: window.previousData.end) == 22)
        #expect(window.previousData.end == (try date("2026-03-02T03:00:00Z")))
        #expect(window.previousData.duration - window.currentData.duration == 3_600)
    }

    @Test
    func reportAggregationClipsBothPeriodsAndRetainsCanonicalBucketsWithoutEditingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HagoStore(databaseURL: directory.appendingPathComponent("report.sqlite"))
        let period = HagoCalendar.shared.weekInterval(containing: try date("2026-10-22T12:00:00Z"))
        let now = Calendar.current.date(byAdding: .day, value: 2, to: period.start)!.addingTimeInterval(3_600)
        let window = ReportComparisonWindow(for: .week, containing: now, now: now)
        let snapshot = ActivitySnapshot(
            appName: "Report fixture", bundleIdentifier: "test.report", processIdentifier: 1, windowTitle: "Fixture",
            url: nil, source: .macOS)
        var saved: [ActivitySegment] = []
        for cutoff in [window.currentData.end, window.previousData.end] {
            let segment = ActivitySegment(
                startedAt: cutoff.addingTimeInterval(-60), endedAt: cutoff.addingTimeInterval(60), snapshot: snapshot)
            try store.save(
                segment: segment,
                classification: SegmentClassification(
                    segmentID: segment.id, kind: .work, categoryID: nil, projectID: nil, ruleID: nil, isManual: true))
            saved.append(segment)
        }
        let comparison = try store.reportComparison(for: .week, containing: now, now: now)
        #expect(comparison.current.workSeconds == 60)
        #expect(comparison.previous.workSeconds == 60)
        #expect(comparison.current.startDate == window.currentPeriod.start)
        #expect(comparison.current.endDate == window.currentPeriod.end)
        #expect(comparison.current.buckets.count == 7)
        #expect(comparison.current.buckets.reduce(0) { $0 + $1.workSeconds } == 60)
        #expect(comparison.previous.buckets.count == 7)
        #expect(try store.reportSummary(for: .week, containing: now).workSeconds == 120)
        #expect(try store.previousReportSummary(for: .week, containing: now).workSeconds == 120)
        for segment in saved {
            let day = try store.activitySegments(for: segment.startedAt)
            #expect(day.contains { $0.segment == segment })
        }
    }

    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }
}
