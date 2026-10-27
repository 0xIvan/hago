import Foundation
import ImageIO

/// Site icons, downloaded once from each site itself and kept in `Application Support/Hago/SiteIcons`.
/// Requests carry no cookies, referrer or Hago data; only sites already in your history are asked.
public actor SiteIcons {
    public static let shared = SiteIcons()
    public static let enabledKey = "hago.fetchSiteIcons"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static let retryMissingAfter: TimeInterval = 7 * 86_400
    private static let maximumBytes = 512 * 1_024

    private let directory: URL
    private let session: URLSession
    private var memory: [String: Data?] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hago/SiteIcons", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.httpAdditionalHeaders = ["User-Agent": "Hago (macOS; site icon)"]
        session = URLSession(configuration: configuration)
    }

    public func icon(for host: String) async -> Data? {
        guard let host = Self.fetchableHost(host) else { return nil }
        if let cached = memory[host] { return cached }
        if let task = inFlight[host] { return await task.value }

        let file = directory.appendingPathComponent("\(host).icon")
        let missing = directory.appendingPathComponent("\(host).none")
        if let data = try? Data(contentsOf: file) {
            memory[host] = data
            return data
        }
        let missingSince = (try? missing.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard Self.isEnabled, missingSince.map({ Date().timeIntervalSince($0) > Self.retryMissingAfter }) ?? true else {
            memory[host] = .some(nil)
            return nil
        }

        let task = Task { await download(host) }
        inFlight[host] = task
        let data = await task.value
        inFlight[host] = nil
        memory[host] = data
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.removeItem(at: missing)
        } else {
            try? Data().write(to: missing)
        }
        return data
    }

    /// The cache lists sites you visited, so it goes with your history.
    public func removeAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    private func download(_ host: String) async -> Data? {
        guard let home = URL(string: "https://\(host)/") else { return nil }
        var candidates: [URL] = []
        if let (data, response) = try? await session.data(from: home),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let html = String(data: data.prefix(1_024 * 1_024), encoding: .utf8) ?? String(data: data.prefix(1_024 * 1_024), encoding: .isoLatin1) {
            candidates += Self.declaredIcons(in: html, relativeTo: response.url ?? home)
        }
        candidates += ["apple-touch-icon.png", "favicon.ico"].compactMap { URL(string: $0, relativeTo: home)?.absoluteURL }

        for url in candidates where url.scheme == "https" {
            guard !Task.isCancelled else { return nil }
            if let (data, response) = try? await session.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               data.count <= Self.maximumBytes,
               Self.isImage(data) {
                return data
            }
        }
        return nil
    }

    /// Icons the page declares with `<link rel="…icon…">`, largest first. SVG is skipped because
    /// not every macOS version Hago supports can draw it.
    static func declaredIcons(in html: String, relativeTo base: URL) -> [URL] {
        let tags = html.matches(of: /<link\b[^>]*>/.ignoresCase()).map { String($0.output) }
        let icons: [(url: URL, size: Int)] = tags.compactMap { tag in
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attribute("href", in: tag),
                  !href.lowercased().hasSuffix(".svg"),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL else { return nil }
            let declared = attribute("sizes", in: tag)?
                .split(whereSeparator: { $0 == " " || $0 == "x" || $0 == "X" })
                .compactMap { Int($0) }.max()
            return (url, declared ?? (rel.contains("apple-touch-icon") ? 180 : 32))
        }
        return icons.sorted { $0.size > $1.size }.map(\.url)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = try? Regex<(Substring, Substring?, Substring?, Substring?)>(
            #"\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        ).ignoresCase()
        guard let pattern, let match = tag.firstMatch(of: pattern) else { return nil }
        return (match.output.1 ?? match.output.2 ?? match.output.3).map { String($0).replacingOccurrences(of: "&amp;", with: "&") }
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// Public names only: no addresses, local names or anything that could reach into a private network.
    static func fetchableHost(_ host: String) -> String? {
        var host = host.lowercased().trimmingCharacters(in: .whitespaces)
        if host.hasSuffix(".") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }),
              host.allSatisfy(\.isASCII),
              !(labels.last?.allSatisfy(\.isNumber) ?? true),
              !["local", "localhost", "internal", "lan", "home", "test", "invalid"].contains(String(labels.last ?? ""))
        else { return nil }
        return host
    }
}
