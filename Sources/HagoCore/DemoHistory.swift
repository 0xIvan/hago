import Foundation

/// Two weeks of a believable developer's days, for showing Hago without anyone's real history.
public enum DemoHistory {
    private struct Place {
        var app: String
        var bundle: String
        var title: String
        var url: String?
    }

    private static let work = [
        Place(app: "Xcode", bundle: "com.apple.dt.Xcode", title: "Hago — DayRing.swift", url: nil),
        Place(app: "Xcode", bundle: "com.apple.dt.Xcode", title: "Hago — HagoStore.swift", url: nil),
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "Pull requests · hago", url: "https://github.com/pulls"),
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "Sprint board · Linear", url: "https://linear.app/team/board"),
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "Q4 roadmap - Google Docs", url: "https://docs.google.com/document/d/roadmap"),
        Place(app: "Figma", bundle: "com.figma.Desktop", title: "Overview redesign", url: nil),
        Place(app: "Terminal", bundle: "com.apple.Terminal", title: "swift test", url: nil),
        Place(app: "Slack", bundle: "com.tinyspeck.slackmacgap", title: "#product - Acme", url: nil),
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "Swift Forums", url: "https://forums.swift.org/latest"),
    ]

    private static let personal = [
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "YouTube", url: "https://www.youtube.com/"),
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "Instagram", url: "https://www.instagram.com/"),
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "Netflix", url: "https://www.netflix.com/browse"),
        Place(app: "Spotify", bundle: "com.spotify.client", title: "Discover Weekly", url: nil),
        Place(app: "Google Chrome", bundle: "com.google.Chrome", title: "r/swift", url: "https://www.reddit.com/r/swift/"),
        Place(app: "Messages", bundle: "com.apple.MobileSMS", title: "Messages", url: nil),
    ]

    public static func seed(into store: HagoStore, endingAt now: Date, days: Int = 14) throws {
        try store.setEnabledPresetIDs(["software-development", "everyday-personal", "social-media"])
        // Choices the demo user already made in Review; Slack and Reddit are left for Review to show.
        let remembered: [(ActivityKind, RuleField, String)] = [
            (.work, .bundleIdentifier, "com.figma.Desktop"), (.work, .host, "docs.google.com"),
            (.work, .host, "forums.swift.org"), (.personal, .host, "www.youtube.com"),
            (.personal, .bundleIdentifier, "com.apple.MobileSMS"),
        ]
        for (kind, field, value) in remembered {
            try store.saveRule(Rule(
                name: "Remember \(value)", priority: 150, enabled: true, isBuiltIn: false,
                action: RuleAction(kind: kind, categoryID: nil, projectID: nil),
                conditions: [RuleCondition(field: field, operation: .equals, value: value)], origin: .user
            ))
        }
        let classifier = ActivityClassifier()
        let rules = classifier.preparedRules(from: try store.loadRules())
        var random = SeededGenerator(seed: 2026)
        let today = HagoCalendar.shared.dayInterval(containing: now).start

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = Calendar.current.component(.weekday, from: day)
            let blocks: [(start: Double, end: Double, places: [Place])] = weekday == 1 || weekday == 7
                ? [(10.5, 12, personal), (15, 17, personal), (20, 22, personal)]
                : [(8.6, 9, personal), (9, 12.5, work), (12.5, 13.2, personal), (13.2, 17.8, work), (20, 21.5, personal)]
            for block in blocks {
                var cursor = day.addingTimeInterval((block.start - 4) * 3_600)
                let end = day.addingTimeInterval((block.end - 4) * 3_600)
                while cursor < end, cursor < now {
                    let place = block.places[Int(random.next() % UInt64(block.places.count))]
                    let length = Double(120 + random.next() % 900)
                    let stop = min(cursor.addingTimeInterval(length), end, now)
                    let snapshot = ActivitySnapshot(
                        appName: place.app, bundleIdentifier: place.bundle, processIdentifier: 1,
                        windowTitle: place.title, url: place.url, source: place.url == nil ? .macOS : .chrome
                    )
                    let segment = ActivitySegment(startedAt: cursor, endedAt: stop, snapshot: snapshot)
                    let result = classifier.classify(snapshot: snapshot, preparedRules: rules)
                    try store.save(segment: segment, classification: SegmentClassification(
                        segmentID: segment.id, kind: result.kind, categoryID: result.categoryID,
                        projectID: nil, ruleID: result.ruleID, isManual: false
                    ))
                    cursor = stop.addingTimeInterval(Double(random.next() % 60))
                }
            }
        }
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
