import Foundation

public struct ReportComparisonWindow: Equatable, Sendable {
    public let currentPeriod: DateInterval
    public let previousPeriod: DateInterval
    public let currentData: DateInterval
    public let previousData: DateInterval

    public var comparesElapsedPortion: Bool {
        currentData.end < currentPeriod.end
    }

    public init(for kind: ReportPeriodKind, containing date: Date, now: Date, calendar: Calendar = .current) {
        func period(containing date: Date) -> DateInterval {
            switch kind {
            case .week: HagoCalendar.shared.weekInterval(containing: date, calendar: calendar)
            case .month: HagoCalendar.shared.monthInterval(containing: date, calendar: calendar)
            }
        }
        currentPeriod = period(containing: date)
        previousPeriod = period(containing: currentPeriod.start.addingTimeInterval(-1))
        let currentEnd = min(currentPeriod.end, max(currentPeriod.start, now))
        currentData = DateInterval(start: currentPeriod.start, end: currentEnd)
        if now >= currentPeriod.end {
            previousData = previousPeriod
        } else if now <= currentPeriod.start {
            previousData = DateInterval(start: previousPeriod.start, duration: 0)
        } else {
            let currentDay = HagoCalendar.shared.dayInterval(containing: now, calendar: calendar).start
            let days = calendar.dateComponents([.day], from: currentPeriod.start, to: currentDay).day ?? 0
            let previousDay = calendar.date(byAdding: .day, value: days, to: previousPeriod.start) ?? previousPeriod.end
            if previousDay >= previousPeriod.end {
                previousData = previousPeriod
            } else {
                var civilDay = calendar.startOfDay(for: previousDay)
                let clock = calendar.dateComponents([.hour, .minute, .second], from: now)
                if (clock.hour ?? 0) < HagoCalendar.shared.dayCutoffHour {
                    civilDay = calendar.date(byAdding: .day, value: 1, to: civilDay) ?? civilDay
                }
                let aligned =
                    calendar.date(
                        bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: clock.second ?? 0,
                        of: civilDay, matchingPolicy: .nextTimePreservingSmallerComponents,
                        repeatedTimePolicy: .first, direction: .forward
                    ) ?? previousPeriod.end
                let fraction = now.timeIntervalSince1970 - floor(now.timeIntervalSince1970)
                let previousEnd = min(
                    previousPeriod.end, max(previousPeriod.start, aligned.addingTimeInterval(fraction)))
                previousData = DateInterval(start: previousPeriod.start, end: previousEnd)
            }
        }
    }
}

public struct ReportComparison: Sendable {
    public let current: ReportSummary
    public let previous: ReportSummary
    public let window: ReportComparisonWindow

    public init(current: ReportSummary, previous: ReportSummary, window: ReportComparisonWindow) {
        self.current = current
        self.previous = previous
        self.window = window
    }
}
