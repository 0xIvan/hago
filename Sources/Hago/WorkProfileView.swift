import HagoCore
import SwiftUI

struct WorkProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore
    @State private var apps: [DetectedWorkApp] = []
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
                Text("Only installed application identities are checked. Shared tools are selected only when you confirm that all their use should count as work. Leave mixed-use tools unchecked and teach Hago from Activity instead.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(apps) { app in
                    Toggle(app.name, isOn: Binding(
                        get: { profileStore.profile.workApps.contains(app.id) },
                        set: { enabled in
                            if enabled { profileStore.profile.workApps.insert(app.id) }
                            else { profileStore.profile.workApps.remove(app.id) }
                        }
                    ))
                }
                if apps.isEmpty { Text("No starter catalog tools found. You can classify other tools from Activity.").foregroundStyle(.secondary) }
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
        .onAppear { apps = DetectedWorkApp.installed() }
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
