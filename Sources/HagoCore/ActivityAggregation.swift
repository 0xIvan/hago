import Foundation

public struct AggregatedActivity: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var appName: String
    public var kind: ActivityKind
    public var categoryName: String?
    public var projectName: String?
    public var duration: TimeInterval
    public var segmentCount: Int
    public var segmentIDs: [UUID]
    public var appliedRuleIDs: [UUID]
    public var firstStartedAt: Date
    public var lastEndedAt: Date

    public init(
        id: String,
        name: String,
        appName: String,
        kind: ActivityKind,
        categoryName: String?,
        projectName: String?,
        duration: TimeInterval,
        segmentCount: Int,
        segmentIDs: [UUID],
        appliedRuleIDs: [UUID],
        firstStartedAt: Date,
        lastEndedAt: Date
    ) {
        self.id = id
        self.name = name
        self.appName = appName
        self.kind = kind
        self.categoryName = categoryName
        self.projectName = projectName
        self.duration = duration
        self.segmentCount = segmentCount
        self.segmentIDs = segmentIDs
        self.appliedRuleIDs = appliedRuleIDs
        self.firstStartedAt = firstStartedAt
        self.lastEndedAt = lastEndedAt
    }
}

public struct ActivityTimelineSpan: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var kind: ActivityKind
}

public enum ActivityAggregation {
    public static func timeline(from segments: [ClassifiedSegment], in interval: DateInterval) -> [ClassifiedSegment] {
        var entries: [ClassifiedSegment] = []

        for var item in segments.sorted(by: { $0.segment.startedAt < $1.segment.startedAt }) {
            guard item.classification.kind != .ignored else { continue }
            // Keep only the portion inside this day or report interval.
            item.segment.startedAt = max(item.segment.startedAt, interval.start)
            item.segment.endedAt = min(item.segment.endedAt, interval.end)
            guard item.segment.duration > 0 else { continue }

            entries.append(item)
        }

        return entries
    }

    public static func timelineSpans(from entries: [ClassifiedSegment]) -> [ActivityTimelineSpan] {
        var spans: [ActivityTimelineSpan] = []
        for entry in entries.sorted(by: { $0.segment.startedAt < $1.segment.startedAt }) {
            guard entry.classification.kind != .ignored, entry.segment.duration > 0 else { continue }

            if let last = spans.last,
               last.kind == entry.classification.kind,
               last.endedAt == entry.segment.startedAt {
                // Merge only touching intervals; even a small real gap must remain untracked.
                spans[spans.count - 1].endedAt = entry.segment.endedAt
            } else {
                spans.append(ActivityTimelineSpan(
                    id: entry.id,
                    startedAt: entry.segment.startedAt,
                    endedAt: entry.segment.endedAt,
                    kind: entry.classification.kind
                ))
            }
        }
        return spans
    }

    public static func groups(from segments: [ClassifiedSegment]) -> [AggregatedActivity] {
        groups(from: segments, matchingWindows: false)
    }

    public static func reviewGroups(from segments: [ClassifiedSegment]) -> [AggregatedActivity] {
        groups(from: segments.filter { $0.classification.kind == .review }, matchingWindows: true)
            .sorted { $0.lastEndedAt > $1.lastEndedAt }
    }

    private static func groups(from segments: [ClassifiedSegment], matchingWindows: Bool) -> [AggregatedActivity] {
        var groups: [String: AggregatedActivity] = [:]

        for item in segments {
            let name = displayName(for: item.segment)
            let key = [
                matchingWindows ? item.segment.snapshot.normalizedSignature : name.lowercased(),
                item.segment.appName.lowercased(),
                item.classification.kind.rawValue,
                item.categoryName ?? "",
                matchingWindows ? (item.classification.projectID?.uuidString ?? "") : (item.projectName ?? "")
            ].joined(separator: "|")

            if var group = groups[key] {
                group.duration += item.segment.duration
                group.segmentCount += 1
                group.segmentIDs.append(item.id)
                if let ruleID = item.classification.ruleID, !group.appliedRuleIDs.contains(ruleID) {
                    group.appliedRuleIDs.append(ruleID)
                }
                group.firstStartedAt = min(group.firstStartedAt, item.segment.startedAt)
                group.lastEndedAt = max(group.lastEndedAt, item.segment.endedAt)
                groups[key] = group
            } else {
                groups[key] = AggregatedActivity(
                    id: key,
                    name: name,
                    appName: item.segment.appName,
                    kind: item.classification.kind,
                    categoryName: item.categoryName,
                    projectName: item.projectName,
                    duration: item.segment.duration,
                    segmentCount: 1,
                    segmentIDs: [item.id],
                    appliedRuleIDs: item.classification.ruleID.map { [$0] } ?? [],
                    firstStartedAt: item.segment.startedAt,
                    lastEndedAt: item.segment.endedAt
                )
            }
        }

        return Array(groups.values)
    }

    private static func displayName(for segment: ActivitySegment) -> String {
        let host = segment.snapshot.host
        guard segment.source == .chrome, !host.isEmpty else {
            return segment.appName
        }

        return host
    }
}
