import Foundation
import SQLite3

/// One consistent copy of the database per Hago day, kept beside it in `Backups/`, newest few only.
public struct DatabaseBackups: Sendable {
    public let databaseURL: URL
    public let keeping: Int

    public init(databaseURL: URL, keeping: Int = 3) {
        self.databaseURL = databaseURL
        self.keeping = keeping
    }

    public var directory: URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    public func existing() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("hago-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Opens its own connection so it can run off the main actor; a no-op when today's copy exists.
    @discardableResult
    public func backUpIfNeeded(now: Date = Date(), calendar: HagoCalendar = .shared) throws -> URL? {
        let day = calendar.dayInterval(containing: now).start
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let destination = directory.appendingPathComponent("hago-\(formatter.string(from: day)).sqlite")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return nil }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(".\(destination.lastPathComponent).partial")
        try? FileManager.default.removeItem(at: partial)
        try copy(to: partial)
        try FileManager.default.moveItem(at: partial, to: destination)

        for old in existing().dropLast(keeping) {
            try? FileManager.default.removeItem(at: old)
        }
        return destination
    }

    private func copy(to destination: URL) throws {
        var source: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let source else {
            sqlite3_close(source)
            throw HagoStoreError.failedToOpenDatabase("Could not read the database to back it up")
        }
        defer { sqlite3_close(source) }
        sqlite3_busy_timeout(source, 3_000)

        var target: OpaquePointer?
        guard sqlite3_open(destination.path, &target) == SQLITE_OK, let target else {
            sqlite3_close(target)
            throw HagoStoreError.failedToOpenDatabase("Could not create the backup file")
        }
        defer { sqlite3_close(target) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        guard let backup = sqlite3_backup_init(target, "main", source, "main") else {
            throw HagoStoreError.failedToStep("Could not start the backup")
        }
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else {
            throw HagoStoreError.failedToStep("The backup did not finish")
        }
    }
}
