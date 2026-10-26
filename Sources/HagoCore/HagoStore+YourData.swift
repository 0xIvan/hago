import Foundation

extension HagoStore {
    /// Every recording as one CSV row, oldest first, in a form spreadsheets open directly.
    @discardableResult
    public func exportActivityCSV(to destination: URL) throws -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines = ["started_at,ended_at,duration_seconds,kind,category,project,app,bundle_id,window_title,url"]
        lines += try exportRows().map { row in
            [
                formatter.string(from: row.startedAt), formatter.string(from: row.endedAt),
                String(Int(row.endedAt.timeIntervalSince(row.startedAt).rounded())), row.kind,
                row.category, row.project, row.app, row.bundleID, row.title, row.url
            ].map(csvField).joined(separator: ",")
        }
        try Data((lines.joined(separator: "\r\n") + "\r\n").utf8).write(to: destination, options: .atomic)
        return lines.count - 1
    }

    private func csvField(_ value: String) -> String {
        // A leading =, +, - or @ would run as a formula in a spreadsheet.
        let guarded = value.first.map { "=+-@".contains($0) } == true ? "'" + value : value
        guard guarded.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return guarded }
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
