import AppKit
import Combine
import HagoCore

struct WorkProfile: Codable, Equatable {
    var version = 1
    var step = 0
    var completed = false
    var presetIDs: Set<String> = ["general-work"]
    var workDomains = ""
    var workApps: Set<String> = []
    var ruleIDs: [String: UUID] = [:]
}

@MainActor
final class WorkProfileStore: ObservableObject {
    @Published var profile: WorkProfile {
        didSet { persist() }
    }
    @Published var needsSetup = false
    private let defaults: UserDefaults
    private let key = "hago.workProfile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let profile = try? JSONDecoder().decode(WorkProfile.self, from: data) {
            self.profile = profile
        } else {
            profile = WorkProfile()
        }
    }

    func prepare(hasHistory: Bool, presetIDs: Set<String>) {
        if defaults.data(forKey: key) == nil && hasHistory {
            profile.presetIDs = presetIDs
            profile.completed = true
        }
        persist()
        needsSetup = !profile.completed
    }

    func finish() {
        profile.completed = true
        needsSetup = false
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }
}

struct DetectedWorkApp: Identifiable {
    var id: String
    var name: String
    var url: URL

    @MainActor
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    @MainActor
    static func installed() -> [Self] {
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications")
        ]
        var apps: [String: Self] = [:]
        for directory in directories {
            guard let files = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in files where url.pathExtension == "app" {
                if let app = Self(url: url), apps[app.id] == nil { apps[app.id] = app }
            }
        }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    init?(url: URL) {
        guard url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty else { return nil }
        self.id = id
        name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        self.url = url
    }

    @MainActor
    static func application(withID id: String) -> Self? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).flatMap { Self(url: $0) }
    }
}
