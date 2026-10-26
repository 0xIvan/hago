import Foundation
import SQLite3
import Testing
@testable import HagoCore

@Suite
struct RecordingIntegrityTests {
    private let base = Date(timeIntervalSince1970: 1_792_476_000)
    private var snapshot: ActivitySnapshot {
        ActivitySnapshot(appName: "Reader", bundleIdentifier: "example.reader", processIdentifier: 12,
                         windowTitle: "Article", url: nil, source: .macOS)
    }

    @Test func uninterruptedReadingCheckpointsOneIdentityWithoutIdleLoss() {
        var recorder = ActivityRecorder()
        #expect(recorder.observe(snapshot, at: base, uptime: 0).isEmpty)
        let id = recorder.current?.id
        for offset in stride(from: 5, through: 600, by: 5) {
            let checkpoints = recorder.observe(snapshot, at: base.addingTimeInterval(Double(offset)), uptime: Double(offset))
            #expect(checkpoints.count == 1)
            #expect(checkpoints.first?.id == id)
            #expect(checkpoints.first?.duration == Double(offset))
        }
        let closed = recorder.observe(nil, at: base.addingTimeInterval(602), uptime: 602)
        #expect(closed.first?.duration == 602)
        #expect(recorder.current == nil)
    }

    @Test func missedPollsAndClockJumpsDoNotInventOrOverlapTime() {
        var recorder = ActivityRecorder()
        _ = recorder.observe(snapshot, at: base, uptime: 0)
        _ = recorder.observe(snapshot, at: base.addingTimeInterval(5), uptime: 5)
        let gap = recorder.observe(snapshot, at: base.addingTimeInterval(605), uptime: 605)
        #expect(gap.first?.duration == 5)
        #expect(recorder.current?.startedAt == base.addingTimeInterval(605))
        let forwardJump = recorder.observe(snapshot, at: base.addingTimeInterval(4_210), uptime: 610)
        #expect(forwardJump.isEmpty)
        _ = recorder.observe(snapshot, at: base.addingTimeInterval(4_215), uptime: 615)
        let backwardsJump = recorder.observe(snapshot, at: base.addingTimeInterval(700), uptime: 620)
        #expect(backwardsJump.first?.duration == 5)
        #expect(recorder.current?.startedAt == base.addingTimeInterval(4_215))
        _ = recorder.observe(nil, at: base.addingTimeInterval(705), uptime: 625)
        _ = recorder.observe(snapshot, at: base.addingTimeInterval(710), uptime: 630)
        #expect(recorder.current?.startedAt == base.addingTimeInterval(4_215))
    }

    @Test func suspensionClosesAndResumeStartsANewInterval() {
        var recorder = ActivityRecorder()
        _ = recorder.observe(snapshot, at: base, uptime: 0)
        let closed = recorder.observe(nil, at: base.addingTimeInterval(4), uptime: 4)
        #expect(closed.first?.duration == 4)
        _ = recorder.observe(snapshot, at: base.addingTimeInterval(900), uptime: 900)
        #expect(recorder.current?.id != closed.first?.id)
        #expect(recorder.current?.startedAt == base.addingTimeInterval(900))
    }

    @Test func restartAfterClockRollbackCannotOverlapAlreadySavedTime() {
        var recorder = ActivityRecorder(notBefore: base.addingTimeInterval(60))
        _ = recorder.observe(snapshot, at: base, uptime: 0)
        #expect(recorder.current?.startedAt == base.addingTimeInterval(60))
        #expect(recorder.observe(snapshot, at: base.addingTimeInterval(5), uptime: 5).isEmpty)
    }

    @Test func checkpointSurvivesReopenAndPreservesManualChoice() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let interval = ActivitySegment(startedAt: base, endedAt: base.addingTimeInterval(5), snapshot: snapshot)
        let automatic = classification(interval)
        do {
            let store = try HagoStore(databaseURL: url)
            try store.checkpoint(segment: interval, classification: automatic)
            try store.overrideSegment(id: interval.id, kind: .work, projectID: nil, categoryID: SeedData.workCategoryID)
            var extended = interval
            extended.endedAt = base.addingTimeInterval(10)
            try store.checkpoint(segment: extended, classification: automatic)
            try store.checkpoint(segment: interval, classification: automatic)
        }
        let reopened = try HagoStore(databaseURL: url)
        let rows = try reopened.recentSegments(limit: 10)
        #expect(rows.count == 1)
        #expect(rows.first?.segment.duration == 10)
        #expect(rows.first?.classification.kind == .work)
        #expect(rows.first?.classification.isManual == true)
    }

    @Test func removingMiddleTimePreservesBothSidesAndRejectsStaleEdits() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try HagoStore(databaseURL: url)
        let interval = ActivitySegment(startedAt: base, endedAt: base.addingTimeInterval(60), snapshot: snapshot)
        var original = classification(interval)
        original.isManual = true
        try store.save(segment: interval, classification: original)
        try store.removeTime(segmentID: interval.id, from: base.addingTimeInterval(20), to: base.addingTimeInterval(40))
        let rows = try store.recentSegments(limit: 10)
        #expect(rows.count == 2)
        #expect(rows.reduce(0) { $0 + $1.segment.duration } == 40)
        #expect(rows.allSatisfy { $0.classification.isManual && $0.classification.kind == original.kind })
        #expect(throws: (any Error).self) {
            try store.removeTime(segmentID: interval.id, from: base, to: base.addingTimeInterval(60))
        }
        #expect(try store.recentSegments(limit: 10).count == 2)
        for row in rows {
            try store.removeTime(segmentID: row.id, from: row.segment.startedAt, to: row.segment.endedAt)
        }
        #expect(try store.recentSegments(limit: 10).isEmpty)
    }

    @Test func failedClassificationWriteRollsBackCheckpointAndRetrySucceeds() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try HagoStore(databaseURL: url)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        #expect(sqlite3_exec(connection, "CREATE TRIGGER reject_classification BEFORE INSERT ON classifications BEGIN SELECT RAISE(ABORT, 'temporary failure'); END", nil, nil, nil) == SQLITE_OK)
        let interval = ActivitySegment(startedAt: base, endedAt: base.addingTimeInterval(5), snapshot: snapshot)
        #expect(throws: (any Error).self) {
            try store.checkpoint(segment: interval, classification: classification(interval))
        }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM activity_segments", -1, &statement, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 0)
        sqlite3_finalize(statement)
        #expect(sqlite3_exec(connection, "DROP TRIGGER reject_classification", nil, nil, nil) == SQLITE_OK)
        try store.checkpoint(segment: interval, classification: classification(interval))
        #expect(try store.recentSegments(limit: 10).count == 1)
    }

    @Test func dailyBackupsReopenWithHistoryAndKeepOnlyTheNewest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hago-backups-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hago.sqlite")
        let store = try HagoStore(databaseURL: url)
        let interval = ActivitySegment(startedAt: base, endedAt: base.addingTimeInterval(60), snapshot: snapshot)
        try store.checkpoint(segment: interval, classification: classification(interval))

        let backups = DatabaseBackups(databaseURL: url, keeping: 2)
        let first = try #require(try backups.backUpIfNeeded(now: base))
        #expect(try backups.backUpIfNeeded(now: base.addingTimeInterval(3_600)) == nil)
        #expect(try HagoStore(databaseURL: first).recentSegments(limit: 10).map(\.segment.id) == [interval.id])

        for day in 1...3 {
            try backups.backUpIfNeeded(now: base.addingTimeInterval(Double(day) * 86_400))
        }
        #expect(backups.existing().count == 2)
        #expect(!FileManager.default.fileExists(atPath: first.path))
    }

    @Test func reportEndLabelsUseTrackingDaysAcrossDSTAndYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        for (year, month, day) in [(2026, 10, 19), (2026, 12, 28)] {
            let start = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 4)))
            let end = try #require(calendar.date(byAdding: .day, value: 7, to: start))
            let label = HagoCalendar.shared.lastDayLabel(before: end, calendar: calendar)
            let expected = try #require(calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: start)))
            #expect(label == expected)
        }
    }

    @Test func fourAMCutoffRemainsLocalFourAMOnDaylightSavingChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        for (month, day) in [(3, 29), (10, 25)] {
            let beforeCutoff = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 3, minute: 30)))
            let afterCutoff = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 4, minute: 30)))
            let before = HagoCalendar.shared.dayInterval(containing: beforeCutoff, calendar: calendar)
            let after = HagoCalendar.shared.dayInterval(containing: afterCutoff, calendar: calendar)
            #expect(calendar.component(.hour, from: before.start) == 4)
            #expect(calendar.component(.hour, from: before.end) == 4)
            #expect(before.end == after.start)
            #expect(calendar.component(.day, from: before.start) == day - 1)
            #expect(calendar.component(.day, from: after.start) == day)
        }
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hago-integrity-\(UUID()).sqlite")
    }

    private func classification(_ interval: ActivitySegment) -> SegmentClassification {
        SegmentClassification(segmentID: interval.id, kind: .personal, categoryID: SeedData.personalCategoryID,
                              projectID: nil, ruleID: nil, isManual: false)
    }
}
