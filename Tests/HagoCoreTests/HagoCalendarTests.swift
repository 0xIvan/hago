import Foundation
import Testing
import HagoCore

@Suite
struct HagoCalendarTests {
    @Test
    func dayBeforeFourAMBelongsToPreviousHagoDay() throws {
        let calendar = utcCalendar()
        let sampleDate = try date("2026-06-02T03:30:00Z")
        let expectedStart = try date("2026-06-01T04:00:00Z")
        let expectedEnd = try date("2026-06-02T04:00:00Z")
        let interval = HagoCalendar().dayInterval(containing: sampleDate, calendar: calendar)

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    @Test
    func aMidnightDayStartPutsLateNightsOnTheNewDay() throws {
        let interval = HagoCalendar(dayCutoffHour: 0).dayInterval(containing: try date("2026-06-02T03:30:00Z"), calendar: utcCalendar())

        #expect(interval.start == (try date("2026-06-02T00:00:00Z")))
        #expect(interval.end == (try date("2026-06-03T00:00:00Z")))
    }

    @Test
    func dayAfterFourAMBelongsToCurrentHagoDay() throws {
        let calendar = utcCalendar()
        let sampleDate = try date("2026-06-02T14:00:00Z")
        let expectedStart = try date("2026-06-02T04:00:00Z")
        let expectedEnd = try date("2026-06-03T04:00:00Z")
        let interval = HagoCalendar().dayInterval(containing: sampleDate, calendar: calendar)

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    @Test
    func monthBeforeFourAMBelongsToPreviousHagoMonth() throws {
        let calendar = utcCalendar()
        let sampleDate = try date("2026-06-01T03:30:00Z")
        let expectedStart = try date("2026-05-01T04:00:00Z")
        let expectedEnd = try date("2026-06-01T04:00:00Z")
        let interval = HagoCalendar().monthInterval(containing: sampleDate, calendar: calendar)

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()

        return try #require(formatter.date(from: value))
    }
}
