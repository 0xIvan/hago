import HagoCore
import SwiftUI

struct WorkProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore
    @State private var message: String?

    var body: some View {
        Form {
            Section("Your work") {
                Text("Choose the work you do. Presets provide starting defaults; your corrections take priority.")
                    .foregroundStyle(.secondary)
                Toggle("General Work", isOn: presetBinding("general-work"))
                Toggle("Software Development", isOn: presetBinding("software-development"))
            }
            Section("Tools you use for work") {
                WorkAppSelectionView(selectedIDs: $profileStore.profile.workApps)
            }
            Section("Work sites and workspaces") {
                TextField("Work-only domains, one per line (e.g. company.slack.com)", text: $profileStore.profile.workDomains, axis: .vertical)
                    .lineLimit(3...6)
                Text("Use only domains whose entire activity is work. For a mixed-use site, leave it out and remember narrower contexts from Activity. Answers stay on this Mac and are not automatically shared with AI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Save Work Profile") { save() }
                .buttonStyle(.borderedProminent)
            if let message { Text(message).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }

    private func presetBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { profileStore.profile.presetIDs.contains(id) }, set: { enabled in
            if enabled { profileStore.profile.presetIDs.insert(id) }
            else { profileStore.profile.presetIDs.remove(id) }
        })
    }

    private func save() {
        do {
            try appState.applyWorkProfile(&profileStore.profile)
            message = "Saved. New activity uses these choices; existing history is unchanged."
        } catch { message = error.localizedDescription }
    }
}
