import AppKit
import ServiceManagement
import SwiftUI

struct TrackingSettingsPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var hasChrome = false
    @State private var requestedChromeAccess = false

    var body: some View {
        GroupBox("Tracking") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Open at Login", isOn: Binding(
                    get: { appState.loginItemStatus == .enabled || appState.loginItemStatus == .requiresApproval },
                    set: { appState.setOpenAtLogin($0) }
                ))
                if appState.loginItemStatus == .requiresApproval {
                    Text("Allow Hago in System Settings → General → Login Items.")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { appState.openLoginItemSettings() }
                } else if appState.loginItemStatus == .notFound {
                    Text("Hago is not registered to open at login.")
                        .foregroundStyle(.secondary)
                }
                if let error = appState.loginItemError {
                    Text(error).foregroundStyle(.red)
                }
                if hasChrome {
                    Divider()
                    if appState.chromeAutomationGranted {
                        Label("Chrome access allowed", systemImage: "checkmark.circle")
                    } else {
                        Text("Chrome time is not recorded until access is allowed. Other supported apps continue tracking.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Allow Chrome Access…") {
                            requestedChromeAccess = true
                            appState.requestChromeAccess()
                        }
                        .disabled(appState.chromePermissionRequestPending)
                        if appState.chromePermissionRequestPending { ProgressView().controlSize(.small) }
                        if requestedChromeAccess, let error = appState.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Divider()
                }
                HStack {
                    Text(appState.currentStateLabel)
                    Spacer()
                    Button(appState.isTrackingPaused ? "Resume Tracking" : "Pause Tracking") {
                        appState.toggleTracking()
                    }
                }
                Text("Reading and watching count without typing. Sleep, lock and pause stop tracking. If you leave your Mac awake and unlocked, remove that time in Activity → Individual → Edit Time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = appState.trackingErrorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .onAppear {
            appState.refreshLoginItemStatus()
            hasChrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
        }
    }
}
