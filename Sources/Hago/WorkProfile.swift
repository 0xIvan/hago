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
        let bundleIDs = ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.figma.Desktop", "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.Terminal", "com.mitchellh.ghostty", "com.apple.mail", "com.googlecode.iterm2", "notion.id", "com.microsoft.teams2", "us.zoom.xos"]
        return bundleIDs.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return Self(id: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
