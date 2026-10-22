import Foundation
import Testing
import HagoCore

struct TimelineViewportTests {
    @Test
    func defaultsToTheFullTrackingDayIncludingBeforeTheDayCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let expected = DateInterval(start: try date("2026-09-10T04:00:00Z"), end: try date("2026-09-11T04:00:00Z"))

        for time in ["2026-09-10T14:00:00Z", "2026-09-11T03:00:00Z"] {
            #expect(TimelineViewport.defaultInterval(for: try date(time), calendar: calendar) == expected)
        }
    }

    @Test
    func zoomKeepsTheTimeUnderThePointerAtTheSamePosition() throws {
        let bounds = DateInterval(start: try date("2026-09-10T04:00:00Z"), duration: 24 * 3_600)
        let original = DateInterval(start: try date("2026-09-10T08:00:00Z"), duration: 16 * 3_600)
        let zoomed = TimelineViewport.zoom(original, by: 0.5, around: 0.25, within: bounds)

        #expect(zoomed.start == (try date("2026-09-10T10:00:00Z")))
        #expect(zoomed.end == (try date("2026-09-10T18:00:00Z")))
        #expect(zoomed.start.addingTimeInterval(zoomed.duration * 0.25) == original.start.addingTimeInterval(original.duration * 0.25))
        #expect(TimelineViewport.zoom(zoomed, by: 2, around: 0.25, within: bounds) == original)
    }

    @Test
    func zoomIsLimitedToFifteenMinutesAndTheFullHagoDay() {
        let bounds = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 24 * 3_600)
        let zoomedIn = TimelineViewport.zoom(bounds, by: 0.0001, around: 0.5, within: bounds)
        #expect(zoomedIn.duration == 15 * 60)
        #expect(TimelineViewport.zoom(zoomedIn, by: 1_000, around: 0.5, within: bounds) == bounds)
    }

    @Test
    func zoomClampsBothEdgesWithoutChangingTheRequestedDuration() {
        let bounds = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 24 * 3_600)
        let firstHour = DateInterval(start: bounds.start, duration: 3_600)
        let lastHour = DateInterval(start: bounds.end.addingTimeInterval(-3_600), duration: 3_600)

        let atStart = TimelineViewport.zoom(firstHour, by: 2, around: 1, within: bounds)
        #expect(atStart.start == bounds.start)
        #expect(atStart.duration == 7_200)
        let atEnd = TimelineViewport.zoom(lastHour, by: 2, around: 0, within: bounds)
        #expect(atEnd.end == bounds.end)
        #expect(atEnd.duration == 7_200)
    }

    @Test
    func defaultAxisIncludesBothTrackingDayBoundariesOnWholeHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let interval = TimelineViewport.defaultInterval(for: try date("2026-09-10T13:23:00Z"), calendar: calendar)
        let ticks = TimelineViewport.axisDates(in: interval, calendar: calendar)

        #expect(ticks.first == interval.start)
        #expect(ticks.last == interval.end)
        #expect(ticks.map { calendar.component(.hour, from: $0) } == [4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 0, 2, 4])
        #expect(ticks.allSatisfy { calendar.component(.minute, from: $0) == 0 })
    }

    @Test
    func halfHourLabelsDoNotShiftWithTheViewport() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let interval = DateInterval(start: try date("2026-09-10T13:23:00Z"), duration: 4 * 3_600)
        let shifted = DateInterval(start: interval.start.addingTimeInterval(60), duration: interval.duration)
        let ticks = TimelineViewport.axisDates(in: interval, calendar: calendar)

        #expect(ticks == TimelineViewport.axisDates(in: shifted, calendar: calendar))
        #expect(ticks.first == (try date("2026-09-10T13:30:00Z")))
        #expect(ticks.last == (try date("2026-09-10T17:00:00Z")))
        #expect(ticks.allSatisfy { calendar.component(.minute, from: $0).isMultiple(of: 30) })
    }

    @Test
    func closeZoomUsesQuarterHourClockLabels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let interval = DateInterval(start: try date("2026-09-10T13:23:42Z"), duration: 90 * 60)
        let ticks = TimelineViewport.axisDates(in: interval, calendar: calendar)

        #expect(ticks.map { calendar.component(.minute, from: $0) } == [30, 45, 0, 15, 30, 45])
        #expect(ticks.allSatisfy { calendar.component(.second, from: $0) == 0 })
    }

    @Test
    func panningRevealsEarlierAndLaterTimesWithoutChangingZoom() throws {
        let bounds = DateInterval(start: try date("2026-09-10T04:00:00Z"), duration: 24 * 3_600)
        let interval = DateInterval(start: try date("2026-09-10T13:00:00Z"), duration: 2 * 3_600)

        let later = TimelineViewport.pan(interval, by: 3_600, within: bounds)
        #expect(later.start == (try date("2026-09-10T14:00:00Z")))
        #expect(later.end == (try date("2026-09-10T16:00:00Z")))
        #expect(later.duration == interval.duration)

        let earlier = TimelineViewport.pan(interval, by: -3_600, within: bounds)
        #expect(earlier.start == (try date("2026-09-10T12:00:00Z")))
        #expect(earlier.end == (try date("2026-09-10T14:00:00Z")))
        #expect(earlier.duration == interval.duration)
    }

    @Test
    func panningStopsAtBothDayBoundaries() {
        let bounds = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 24 * 3_600)
        let interval = DateInterval(start: bounds.start.addingTimeInterval(9 * 3_600), duration: 2 * 3_600)

        let earliest = TimelineViewport.pan(interval, by: -bounds.duration, within: bounds)
        #expect(earliest.start == bounds.start)
        #expect(earliest.duration == interval.duration)
        let latest = TimelineViewport.pan(interval, by: bounds.duration, within: bounds)
        #expect(latest.end == bounds.end)
        #expect(latest.duration == interval.duration)
        #expect(TimelineViewport.pan(bounds, by: 3_600, within: bounds) == bounds)
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
