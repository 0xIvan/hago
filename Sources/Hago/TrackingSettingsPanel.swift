import ServiceManagement
import SwiftUI

struct TrackingSettingsPanel: View {
    @EnvironmentObject private var appState: AppState

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
        .onAppear { appState.refreshLoginItemStatus() }
    }
}
