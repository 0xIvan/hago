import Foundation

public struct HagoCalendar: Sendable {
    public static let dayStartHourKey = "hago.dayStartHour"
    public static let dayStartHours = 0...8

    /// Read on each use so a new day start applies everywhere at once.
    public static var shared: HagoCalendar {
        HagoCalendar(dayCutoffHour: UserDefaults.standard.object(forKey: dayStartHourKey) as? Int ?? 4)
    }

    public let dayCutoffHour: Int

    public init(dayCutoffHour: Int = 4) {
        self.dayCutoffHour = min(max(dayCutoffHour, Self.dayStartHours.lowerBound), Self.dayStartHours.upperBound)
    }

    public func lastDayLabel(before end: Date, calendar: Calendar = .current) -> Date {
        let lastDay = dayInterval(containing: end.addingTimeInterval(-1), calendar: calendar).start
        return calendar.startOfDay(for: lastDay)
    }

    public func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let localCalendar = calendar

        let localStartOfDate = localCalendar.startOfDay(for: date)
        let cutoff = localCalendar.date(
            bySettingHour: dayCutoffHour, minute: 0, second: 0, of: localStartOfDate
        ) ?? localStartOfDate

        let start: Date
        if date < cutoff {
            start = localCalendar.date(byAdding: .day, value: -1, to: cutoff) ?? cutoff
        } else {
            start = cutoff
        }

        let end = localCalendar.date(byAdding: .day, value: 1, to: start) ?? start

        return DateInterval(start: start, end: end)
    }

    public func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let localCalendar = calendar

        let currentDayStart = dayInterval(containing: date, calendar: localCalendar).start
        let calendarWeekStart = localCalendar.dateInterval(of: .weekOfYear, for: currentDayStart)?.start
            ?? localCalendar.startOfDay(for: currentDayStart)

        return localCalendar.date(
            bySettingHour: dayCutoffHour, minute: 0, second: 0, of: calendarWeekStart
        ) ?? calendarWeekStart
    }

    public func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = weekStart(containing: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start

        return DateInterval(start: start, end: end)
    }

    public func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let localCalendar = calendar
        let currentDayStart = dayInterval(containing: date, calendar: localCalendar).start
        let calendarMonthStart = localCalendar.dateInterval(of: .month, for: currentDayStart)?.start
            ?? localCalendar.startOfDay(for: currentDayStart)
        let start = localCalendar.date(
            bySettingHour: dayCutoffHour, minute: 0, second: 0, of: calendarMonthStart
        ) ?? calendarMonthStart
        let nextMonthStart = localCalendar.date(byAdding: .month, value: 1, to: calendarMonthStart)
            ?? calendarMonthStart
        let end = localCalendar.date(
            bySettingHour: dayCutoffHour, minute: 0, second: 0, of: nextMonthStart
        ) ?? nextMonthStart

        return DateInterval(start: start, end: end)
    }
}
