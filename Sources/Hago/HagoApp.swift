import AppKit
import SwiftUI

@main
struct HagoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Hago", id: "dashboard") {
            DashboardView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.appState.workProfileStore)
        }
        .defaultSize(width: 1_020, height: 720)
        .commands {
            UpdateCommands(updater: appDelegate.appState.updater)
        }
        Settings {
            HagoSettingsView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.appState.workProfileStore)
        }
    }
}

private struct UpdateCommands: Commands {
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(before: .systemServices) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
