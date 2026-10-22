import HagoCore
import SwiftUI

struct DirectAIConnectionView: View {
    @EnvironmentObject private var appState: AppState
    var showsProviderPicker = true
    @State private var apiKey = ""
    @State private var message: String?
    @State private var customModelID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsProviderPicker {
                Picker(
                    "AI connection",
                    selection: Binding(
                        get: { provider },
                        set: {
                            appState.selectReviewAIHarness($0)
                            message = nil
                            apiKey = ""
                        })
                ) {
                    Text("Anthropic API").tag(ReviewAIHarnessKind.anthropic)
                    Text("OpenAI API").tag(ReviewAIHarnessKind.openAI)
                    if !provider.isDirectProvider { Text("Not connected").tag(provider) }
                }
            }
            if provider.isDirectProvider {
                Text(
                    "Optional. Your own API account is billed by the provider. A chat subscription does not necessarily include API usage. No requests are made until you run analysis or explicitly enable a schedule."
                )
                .font(.caption).foregroundStyle(.secondary)
                SecureField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Key in Keychain") {
                        do {
                            try appState.saveDirectAICredential(apiKey)
                            apiKey = ""
                            message = "API key saved in Keychain. Access is checked on your next analysis."
                        } catch { message = error.localizedDescription }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Disconnect and Remove Key") {
                        do {
                            try appState.disconnectDirectAI()
                            apiKey = ""
                            message = "Key removed. AI sharing and scheduling disabled."
                        } catch { message = error.localizedDescription }
                    }
                }
                if let message { Text(message).font(.caption).textSelection(.enabled) }
                if let recommended = ReviewAIDirectCatalog.models(for: provider).first {
                    Text(
                        "Suggested starting model: \(recommended.displayName). Fast, economical classification; quality has not yet been benchmarked on Hago activity."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Link(
                        "Model documentation and pricing",
                        destination: ReviewAIDirectCatalog.documentation(for: provider)
                    )
                    .font(.caption)
                }
                Toggle(
                    "Include redacted window titles and title rule values",
                    isOn: Binding(
                        get: { appState.reviewAISettings.shareRedactedTitles },
                        set: { appState.setReviewAIShareTitles($0) }))
                Text(
                    "By default Hago sends grouped app names, bundle identifiers, site domains, counts, minutes, selected profession, and relevant rule labels/values. URLs lose paths, credentials, queries and fragments. Group IDs are replaced. Titles are withheld unless enabled; enabled titles are shortened and common email addresses, URLs, local paths and key patterns are removed. Titles may still contain sensitive names or text. No page contents, full history, ignored/private activity, or free-text onboarding answers are sent."
                )
                .font(.caption).foregroundStyle(.secondary)
                Toggle(
                    "Allow this data to be sent to \(provider.displayName)",
                    isOn: Binding(
                        get: { appState.selectedReviewAIHarnessIsConfirmed },
                        set: { appState.setReviewAIHarnessConfirmed($0) }))
                DisclosureGroup("Advanced model selection") {
                    Picker(
                        "Model",
                        selection: Binding(
                            get: {
                                appState.reviewAISettings.selectedModel(for: provider) ?? ReviewAIDirectCatalog.models(
                                    for: provider
                                ).first?.modelID ?? ""
                            }, set: { appState.setReviewAIModel($0) })
                    ) {
                        ForEach(ReviewAIDirectCatalog.models(for: provider)) { Text($0.displayName).tag($0.modelID) }
                        if let selected = appState.reviewAISettings.selectedModel(for: provider),
                            !ReviewAIDirectCatalog.models(for: provider).contains(where: { $0.modelID == selected })
                        {
                            Text(selected).tag(selected)
                        }
                    }
                    HStack {
                        TextField("Custom model ID", text: $customModelID)
                        Button("Use Model") { appState.setReviewAIModel(customModelID) }
                            .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text(
                        "Custom models must support this provider's text JSON API. Unsupported models fail visibly; Hago never switches models or providers automatically."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: provider) {
            apiKey = ""
            message = nil
            customModelID = ""
        }
    }

    private var provider: ReviewAIHarnessKind { appState.reviewAISettings.selectedHarness }
}
