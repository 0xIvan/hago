import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController?
    let isConfigured: Bool

    override init() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = Data(base64Encoded: publicKey)?.count == 32
        super.init()
        guard isConfigured else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updates else { throw URLError(.cancelled) }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        GroupBox("Updates") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Text(updater.isConfigured
                     ? "Checks are manual. Sparkle contacts the public Hago update feed on GitHub, verifies signed updates, and asks before downloading or installing. No activity or profile data is sent."
                     : "Updates are not configured in this local build. A Hago update signing key and published feed are required before distribution.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
