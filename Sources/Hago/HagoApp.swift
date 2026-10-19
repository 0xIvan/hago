import AppKit
import SwiftUI

@main
struct HagoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Hago", id: "dashboard") {
            DashboardView()
                .environmentObject(appDelegate.appState)
        }
        .defaultSize(width: 1_020, height: 720)
    }
}
