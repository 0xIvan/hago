import Foundation
import SQLite3
import Testing
@testable import HagoCore

struct DatabaseLocationTests {
    @Test
    func usesLegacyDatabaseWithLiveWALWhenHagoDatabaseIsAbsent() throws {
        let support = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacyDirectory = support.appendingPathComponent("Worklog", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacy = legacyDirectory.appendingPathComponent("worklog.sqlite")
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z"))

        do {
            let store = try HagoStore(databaseURL: legacy)
            let start = HagoCalendar.shared.dayInterval(containing: date).start.addingTimeInterval(3_600)
            let segment = ActivitySegment(
                startedAt: start,
                endedAt: start.addingTimeInterval(120),
                snapshot: ActivitySnapshot(
                    appName: "Legacy history",
                    bundleIdentifier: "test.legacy",
                    processIdentifier: 1,
                    windowTitle: "History",
                    url: nil,
                    source: .macOS
                )
            )
            try store.save(segment: segment, classification: SegmentClassification(
                segmentID: segment.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            ))
        }

        var writer: OpaquePointer?
        #expect(sqlite3_open(legacy.path, &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        #expect(sqlite3_exec(writer, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(writer, "CREATE TABLE fixture_wal (value INTEGER)", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(writer, "INSERT INTO fixture_wal VALUES (1)", nil, nil, nil) == SQLITE_OK)
        #expect(FileManager.default.fileExists(atPath: legacy.path + "-wal"))

        let selected = try HagoStore.defaultDatabaseURL(in: support)
        #expect(selected == legacy)
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Hago").path))
        let reopened = try HagoStore(databaseURL: selected)
        #expect(try reopened.daySummary(for: date).workSeconds == 120)
        #expect(FileManager.default.fileExists(atPath: legacy.path + "-wal"))
    }

    @Test
    func existingHagoDatabaseTakesPrecedenceWithoutOverwritingEitherFile() throws {
        let support = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacyDirectory = support.appendingPathComponent("Worklog", isDirectory: true)
        let hagoDirectory = support.appendingPathComponent("Hago", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hagoDirectory, withIntermediateDirectories: true)
        let legacy = legacyDirectory.appendingPathComponent("worklog.sqlite")
        let hago = hagoDirectory.appendingPathComponent("hago.sqlite")
        try Data("legacy".utf8).write(to: legacy)
        try Data("hago".utf8).write(to: hago)

        #expect(try HagoStore.defaultDatabaseURL(in: support) == hago)
        #expect(try Data(contentsOf: legacy) == Data("legacy".utf8))
        #expect(try Data(contentsOf: hago) == Data("hago".utf8))
    }

    private func temporarySupportDirectory() throws -> URL {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }
}
