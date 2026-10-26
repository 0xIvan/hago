import AppKit
import ServiceManagement
import SwiftUI

struct TrackingSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore

    var body: some View {
        Form {
            Section("Tracking") {
                TrackingRows()
            }
            UpdateSettingsSection(updater: appState.updater)
            Section("Setup") {
                LabeledContent("Presets and work apps") {
                    Button("Resume Setup…") {
                        profileStore.needsSetup = true
                        appState.openDashboardWindow()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TrackingRows: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        LabeledContent {
            Button(appState.isTrackingPaused ? "Resume Tracking" : "Pause Tracking") {
                appState.toggleTracking()
            }
        } label: {
            Text(appState.currentStateLabel)
            Text("Sleep, lock and pause stop tracking. Watching a video or sitting in a call counts even without typing.")
        }
        Picker(selection: $appState.awayAfterMinutes) {
            Text("Never").tag(0)
            ForEach([2, 5, 10, 15, 30], id: \.self) { Text("After \($0) minutes").tag($0) }
        } label: {
            Text("Stop counting when I'm away")
            Text("With no keyboard or mouse use for this long, Hago stops at your last input, so the time away is not counted.")
        }
        if let error = appState.trackingErrorMessage {
            Text(error).foregroundStyle(.red)
        }
        Toggle(isOn: Binding(
            get: { appState.loginItemStatus == .enabled || appState.loginItemStatus == .requiresApproval },
            set: { appState.setOpenAtLogin($0) }
        )) {
            Text("Open at login")
            if appState.loginItemStatus == .requiresApproval {
                Text("Allow Hago in System Settings → General → Login Items.")
            } else if appState.loginItemStatus == .notFound {
                Text("Hago is not registered to open at login.")
            }
        }
        .toggleStyle(.switch)
        .onAppear { appState.refreshLoginItemStatus() }
        if appState.loginItemStatus == .requiresApproval {
            LabeledContent("Login items") {
                Button("Open Login Items Settings") { appState.openLoginItemSettings() }
            }
        }
        if let error = appState.loginItemError {
            Text(error).foregroundStyle(.red)
        }
    }
}

struct ChromeAccessRows: View {
    @EnvironmentObject private var appState: AppState
    @State private var requestedChromeAccess = false

    private var hasChrome: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
    }

    var body: some View {
        if hasChrome {
            LabeledContent {
                if appState.chromeAutomationGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        if appState.chromePermissionRequestPending { ProgressView().controlSize(.small) }
                        Button("Allow Chrome Access…") {
                            requestedChromeAccess = true
                            appState.requestChromeAccess()
                        }
                        .disabled(appState.chromePermissionRequestPending)
                    }
                }
            } label: {
                Text("Chrome")
                Text(appState.chromeAutomationGranted
                     ? "Lets Hago read the current tab's site and check for private windows."
                     : "Chrome time is not recorded until access is allowed. Other supported apps continue tracking.")
            }
            if requestedChromeAccess, let error = appState.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
