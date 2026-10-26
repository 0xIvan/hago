import Foundation
import HagoCore
import SQLite3

// Times the store work the app does, on a synthetic history of a heavy user.
// swift run -c release HagoBench [--segments 500000] [--db /path/to/bench.sqlite]

let arguments = CommandLine.arguments
func option(_ name: String) -> String? {
    arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
}

let segmentCount = Int(option("--segments") ?? "") ?? 500_000
let databaseURL = URL(fileURLWithPath: option("--db")
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("hago-bench-\(segmentCount).sqlite").path)
let now = Date()

if !FileManager.default.fileExists(atPath: databaseURL.path) {
    let start = Date()
    try generate(at: databaseURL, count: segmentCount)
    print("generated \(segmentCount) segments in \(Int(Date().timeIntervalSince(start)))s at \(databaseURL.path)")
}

let store = try HagoStore(databaseURL: databaseURL)
var results: [(String, Double)] = []

@MainActor func measure(_ name: String, runs: Int = 5, _ body: () throws -> Void) rethrows {
    try body()
    var samples: [Double] = []
    for _ in 0..<runs {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    let median = samples.sorted()[samples.count / 2]
    results.append((name, median))
    print(name.padding(toLength: 30, withPad: " ", startingAt: 0) + String(format: "%9.2f ms", median))
}

let rules = try store.loadRules()
try measure("tick.daySummary") { _ = try store.daySummary(for: now) }
try measure("tick.dayTimeline") { _ = try store.dayTimeline(for: now) }
try measure("refresh.loadRules") { _ = try store.loadRules() }
try measure("refresh.learningSuggestions") { _ = try store.learningSuggestions() }
try measure("refresh.ruleReviewRecords") { _ = try store.ruleReviewRecords(for: rules) }
try measure("refresh.reviewSegments") { _ = try store.reviewSegments() }
try measure("refresh.activitySegments") { _ = try store.activitySegments(for: now) }
try measure("refresh.recentSegments") { _ = try store.recentSegments(limit: 20) }
let review = try store.reviewSegments()
try measure("review.groups") { _ = ActivityAggregation.groups(from: review) }
try measure("reports.week", runs: 3) { _ = try store.reportComparison(for: .week, containing: now, now: now) }
try measure("reports.month", runs: 3) { _ = try store.reportComparison(for: .month, containing: now, now: now) }
var backupDay = 0
try measure("daily.backup", runs: 3) {
    backupDay += 1
    try DatabaseBackups(databaseURL: databaseURL).backUpIfNeeded(now: now.addingTimeInterval(Double(backupDay) * 86_400 * 400))
}
print("TOTAL".padding(toLength: 30, withPad: " ", startingAt: 0) + String(format: "%9.2f ms", results.map(\.1).reduce(0, +)))

func generate(at url: URL, count: Int) throws {
    let store = try HagoStore(databaseURL: url)
    for index in 0..<120 {
        let kind: ActivityKind = index.isMultiple(of: 3) ? .personal : .work
        try store.saveRule(Rule(
            name: "Bench \(index)", priority: 100 + index, enabled: true, isBuiltIn: false,
            action: RuleAction(kind: kind, categoryID: nil, projectID: nil),
            conditions: [RuleCondition(field: .host, operation: .domain, value: "site\(index).example")]
        ))
    }
    let ruleIDs = try store.loadRules().map(\.id.uuidString)

    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
    defer { sqlite3_close(handle) }
    sqlite3_exec(handle, "BEGIN", nil, nil, nil)

    var segment: OpaquePointer?
    var classification: OpaquePointer?
    sqlite3_prepare_v2(handle, """
        INSERT INTO activity_segments (id, started_at, ended_at, app_name, bundle_id, process_id, window_title, url, source,
            host, app_name_normalized, bundle_id_normalized, window_title_normalized, url_normalized)
        VALUES (?1, ?2, ?3, ?4, ?5, 1, ?6, ?7, ?8, ?9, lower(?4), lower(?5), lower(?6), lower(coalesce(?7, '')))
        """, -1, &segment, nil)
    sqlite3_prepare_v2(handle, """
        INSERT INTO classifications (segment_id, kind, category_id, project_id, rule_id, is_manual)
        VALUES (?1, ?2, NULL, NULL, ?3, ?4)
        """, -1, &classification, nil)

    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let apps = (0..<30).map { ("App \($0)", "com.bench.app\($0)") }
    let span = 365.0 * 86_400
    let step = span / Double(count)
    var generator = SystemRandomNumberGenerator()

    for index in 0..<count {
        let id = UUID().uuidString
        let start = now.timeIntervalSince1970 - span + Double(index) * step
        let end = start + step * Double.random(in: 0.5...0.95, using: &generator)
        let isBrowser = index % 3 != 0
        let site = Int.random(in: 0..<200, using: &generator)
        let app = isBrowser ? ("Google Chrome", "com.google.chrome") : apps[index % apps.count]
        let host = isBrowser ? "site\(site).example" : ""
        let url = isBrowser ? "https://\(host)/page/\(index % 50)" : nil
        let title = isBrowser ? "Page \(index % 50) - Site \(site)" : "Document \(index % 400)"

        sqlite3_bind_text(segment, 1, id, -1, transient)
        sqlite3_bind_double(segment, 2, start)
        sqlite3_bind_double(segment, 3, end)
        sqlite3_bind_text(segment, 4, app.0, -1, transient)
        sqlite3_bind_text(segment, 5, app.1, -1, transient)
        sqlite3_bind_text(segment, 6, title, -1, transient)
        if let url { sqlite3_bind_text(segment, 7, url, -1, transient) } else { sqlite3_bind_null(segment, 7) }
        sqlite3_bind_text(segment, 8, isBrowser ? "chrome" : "macOS", -1, transient)
        sqlite3_bind_text(segment, 9, host, -1, transient)
        sqlite3_step(segment)
        sqlite3_reset(segment)

        let roll = index % 100
        let kind = roll < 10 ? "review" : roll < 60 ? "work" : "personal"
        sqlite3_bind_text(classification, 1, id, -1, transient)
        sqlite3_bind_text(classification, 2, kind, -1, transient)
        if kind != "review", roll >= 12 {
            sqlite3_bind_text(classification, 3, ruleIDs[site % ruleIDs.count], -1, transient)
        } else {
            sqlite3_bind_null(classification, 3)
        }
        sqlite3_bind_int(classification, 4, kind != "review" && roll < 12 ? 1 : 0)
        sqlite3_step(classification)
        sqlite3_reset(classification)
    }

    sqlite3_finalize(segment)
    sqlite3_finalize(classification)
    sqlite3_exec(handle, "COMMIT", nil, nil, nil)
}
