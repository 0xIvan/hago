import Foundation

public struct ActivityRecorder {
    public private(set) var current: ActivitySegment?
    private var lastObservation: Date?
    private var lastUptime: TimeInterval?
    private var latestEnd: Date?

    public init() {}

    public init(notBefore date: Date) {
        latestEnd = date
    }

    public mutating func observe(
        _ snapshot: ActivitySnapshot?, at date: Date, uptime: TimeInterval
    ) -> [ActivitySegment] {
        var checkpoints: [ActivitySegment] = []
        if var interval = current, let lastObservation, let lastUptime {
            let elapsed = uptime - lastUptime
            let wallElapsed = date.timeIntervalSince(lastObservation)
            let continuous = elapsed >= 0 && elapsed <= 15
                && abs(wallElapsed - elapsed) < 2
            if continuous {
                interval.endedAt = max(interval.endedAt, date)
            }
            if interval.duration > 0 {
                checkpoints.append(interval)
                latestEnd = max(latestEnd ?? interval.endedAt, interval.endedAt)
            }
            if continuous,
               let snapshot,
               interval.snapshot.normalizedSignature == snapshot.normalizedSignature {
                current = interval
            } else {
                current = snapshot.map {
                    ActivitySegment(startedAt: max(date, interval.endedAt), endedAt: max(date, interval.endedAt), snapshot: $0)
                }
            }
        } else {
            let start = max(date, latestEnd ?? date)
            current = snapshot.map { ActivitySegment(startedAt: start, endedAt: start, snapshot: $0) }
        }
        lastObservation = date
        lastUptime = uptime
        return checkpoints
    }
}
