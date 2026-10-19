import Foundation

public enum TimelineViewport {
    public static func defaultInterval(for day: Date, calendar: Calendar) -> DateInterval {
        let hagoDay = HagoCalendar.shared.dayInterval(containing: day, calendar: calendar)
        let midnight = calendar.startOfDay(for: hagoDay.start)
        let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: midnight) ?? hagoDay.start
        let end = calendar.date(byAdding: .day, value: 1, to: midnight) ?? hagoDay.end
        return DateInterval(start: start, end: end)
    }

    public static func zoom(
        _ interval: DateInterval,
        by factor: Double,
        around fraction: Double,
        within bounds: DateInterval
    ) -> DateInterval {
        let fraction = min(1, max(0, fraction))
        let duration = min(bounds.duration, max(15 * 60, interval.duration * factor))
        let anchor = interval.start.addingTimeInterval(interval.duration * fraction)
        let start = min(
            max(anchor.addingTimeInterval(-duration * fraction), bounds.start),
            bounds.end.addingTimeInterval(-duration)
        )
        return DateInterval(start: start, duration: duration)
    }

    public static func axisDates(in interval: DateInterval, calendar: Calendar) -> [Date] {
        let minutes: Int
        switch interval.duration {
        case (12 * 3_600)...: minutes = 120
        case (6 * 3_600)...: minutes = 60
        case (3 * 3_600)...: minutes = 30
        default: minutes = 15
        }

        // Anchor ticks to the local clock, never to the changing viewport start.
        var tick = calendar.startOfDay(for: interval.start)
        var dates: [Date] = []
        while tick <= interval.end {
            if tick >= interval.start {
                dates.append(tick)
            }
            guard let next = calendar.date(byAdding: .minute, value: minutes, to: tick), next > tick else { break }
            tick = next
        }
        return dates
    }

    public static func pan(_ interval: DateInterval, by offset: TimeInterval, within bounds: DateInterval) -> DateInterval {
        let start = min(
            max(interval.start.addingTimeInterval(offset), bounds.start),
            bounds.end.addingTimeInterval(-interval.duration)
        )
        return DateInterval(start: start, duration: interval.duration)
    }
}
