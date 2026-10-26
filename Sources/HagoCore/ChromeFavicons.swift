import Foundation
import SQLite3

/// Reads site icons from Chrome's own favicon cache on this Mac, so showing them never
/// touches the network. Missing or unreadable caches simply yield no icon.
public actor ChromeFavicons {
    public static let shared = ChromeFavicons()

    private var cache: [String: Data?] = [:]
    private lazy var databases: [URL] = {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        let profiles = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return profiles
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { ($0 == "Default" ? "" : $0) < ($1 == "Default" ? "" : $1) }
            .map { root.appendingPathComponent($0).appendingPathComponent("Favicons") }
            .filter { FileManager.default.isReadableFile(atPath: $0.path) }
    }()

    public func iconData(for host: String) -> Data? {
        let host = host.lowercased()
        guard !host.isEmpty else { return nil }
        if let cached = cache[host] { return cached }
        let hosts = host.hasPrefix("www.") ? [host] : [host, "www.\(host)"]
        let data = hosts.lazy.flatMap { host in self.databases.lazy.compactMap { Self.read(host: host, from: $0) } }.first
        cache[host] = data
        return data
    }

    private static func read(host: String, from database: URL) -> Data? {
        var handle: OpaquePointer?
        // Chrome keeps the file open; immutable mode reads it without taking or waiting for locks.
        let uri = "file:\(database.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? database.path)?immutable=1"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }

        let sql = """
            SELECT b.image_data FROM icon_mapping m
            JOIN favicon_bitmaps b ON b.icon_id = m.icon_id
            WHERE (m.page_url >= ?1 AND m.page_url < ?2) OR (m.page_url >= ?3 AND m.page_url < ?4)
            ORDER BY b.width >= 32 DESC, abs(b.width - 32), b.last_updated DESC
            LIMIT 1
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        // "/" sorts right before "0", so this range covers every page on the host.
        for (index, value) in ["https://\(host)/", "https://\(host)0", "http://\(host)/", "http://\(host)0"].enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
}
