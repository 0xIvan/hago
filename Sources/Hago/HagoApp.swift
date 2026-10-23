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
            AppCommands(appState: appDelegate.appState, updater: appDelegate.appState.updater)
        }
    }
}

private struct AppCommands: Commands {
    let appState: AppState
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appState.openHagoWindow(section: .tracking)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(before: .systemServices) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
