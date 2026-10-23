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

struct TrackingSettingsPanel: View {
    var body: some View {
        GroupBox("Tracking") {
            VStack(alignment: .leading, spacing: 10) {
                TrackingRows()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

private struct TrackingRows: View {
    @EnvironmentObject private var appState: AppState
    @State private var hasChrome = false
    @State private var requestedChromeAccess = false

    var body: some View {
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
        .onAppear {
            appState.refreshLoginItemStatus()
            hasChrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
        }
        if appState.loginItemStatus == .requiresApproval {
            LabeledContent("Login items") {
                Button("Open Login Items Settings") { appState.openLoginItemSettings() }
            }
        }
        if let error = appState.loginItemError {
            Text(error).foregroundStyle(.red)
        }
        if hasChrome {
            LabeledContent {
                if appState.chromeAutomationGranted {
                    Label("Allowed", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
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
                if !appState.chromeAutomationGranted {
                    Text("Chrome time is not recorded until access is allowed. Other supported apps continue tracking.")
                }
            }
            if requestedChromeAccess, let error = appState.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        LabeledContent {
            Button(appState.isTrackingPaused ? "Resume Tracking" : "Pause Tracking") {
                appState.toggleTracking()
            }
        } label: {
            Text(appState.currentStateLabel)
            Text("Reading and watching count without typing. Sleep, lock and pause stop tracking. If you leave your Mac awake and unlocked, remove that time in Activity → Individual → Edit Time.")
        }
        if let error = appState.trackingErrorMessage {
            Text(error).foregroundStyle(.red)
        }
    }
}
