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

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore
    @Environment(\.openSettings) private var openSettings
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Understand where your time goes").font(.largeTitle.weight(.semibold))
            Text("Step \(profileStore.profile.step + 1) of 4").foregroundStyle(.secondary)
            Group {
                switch profileStore.profile.step {
                case 0:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Hago records computer activity locally. Reading and watching count without typing. Sleep, lock and pause stop recording; you can repair unattended unlocked time in Activity.")
                            Text(appState.accessibilityTrusted ? "Window context access is available." : "App-level tracking works now. Grant Accessibility access to improve window recognition.")
                            if !appState.accessibilityTrusted { Button("Grant Accessibility Access…") { appState.requestAccessibilityPermission() } }
                            TrackingSettingsPanel()
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                case 1: WorkProfileView()
                case 2:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("AI is optional").font(.title2)
                        Text("Local presets and corrections work without AI. You can connect your preferred provider and model in AI settings. You choose what context is shared and provider usage may cost money.")
                        Button("Open AI Connection Settings…") {
                            appState.prepareSettings(section: .aiReview)
                            openSettings()
                        }
                        Text("Continue to use local classification without connecting a provider.").foregroundStyle(.secondary)
                    }
                default:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("You’re ready").font(.title2)
                        Text("Hago is tracking as capture permits. Unknown activity stays in Needs review. Correct an activity to fix it, and choose Remember when you want a reusable rule.")
                        Text("Your profile is editable in Settings → Work Profile. Review covers your full history.").foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Finish Later") { profileStore.needsSetup = false }
                Spacer()
                if profileStore.profile.step > 0 { Button("Back") { profileStore.profile.step -= 1 } }
                Button(profileStore.profile.step == 3 ? "Open Overview" : "Continue") {
                    do {
                        if profileStore.profile.step == 1 { try appState.applyWorkProfile(&profileStore.profile) }
                        if profileStore.profile.step == 3 { profileStore.finish(); appState.selectedSection = .overview }
                        else { profileStore.profile.step += 1 }
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 700, height: 650)
    }
}
