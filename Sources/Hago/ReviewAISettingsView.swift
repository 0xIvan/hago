import HagoCore
import SwiftUI

/// Three plain steps: pick an AI, allow what it sees, choose how much it does on its own.
/// Models, reasoning and CLI paths stay under Advanced.
struct ReviewAISettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var apiKey = ""
    @State private var keyMessage: String?
    @State private var hasSavedKey = false
    @State private var customBinaryPath = ""
    @State private var customModelID = ""

    var body: some View {
        Form {
            Section {
                summary
            }

            Section {
                ChoiceRow(
                    title: "Off",
                    detail: "Everything waits in Review for you to file.",
                    isSelected: selectedHarness == .disabled
                ) { appState.selectReviewAIHarness(.disabled) }
                ForEach(appHarnesses, id: \.self) { harness in
                    let status = appState.reviewAIHarnessStatuses.first { $0.harness == harness }
                    ChoiceRow(
                        title: harness.friendlyName,
                        detail: status?.isAvailable == true ? harness.friendlyDetail : "Not installed on this Mac.",
                        isSelected: selectedHarness == harness
                    ) { appState.selectReviewAIHarness(harness) }
                    .disabled(status?.isAvailable != true && selectedHarness != harness)
                }
                ForEach([ReviewAIHarnessKind.anthropic, .openAI], id: \.self) { harness in
                    ChoiceRow(
                        title: harness.friendlyName,
                        detail: harness.friendlyDetail,
                        isSelected: selectedHarness == harness
                    ) { appState.selectReviewAIHarness(harness) }
                }
                if selectedHarness.isDirectProvider {
                    apiKeyRows
                }
            } header: {
                Text("Which AI should help?")
            } footer: {
                if appState.isDiscoveringReviewAIHarnesses {
                    Text("Looking for AI apps on this Mac…")
                }
            }

            if selectedHarness != .disabled {
                Section("What it sees") {
                    Text(sharingSummary)
                        .foregroundStyle(.secondary)
                    if selectedHarness.isDirectProvider {
                        Toggle("Also send window titles, with emails, links and paths removed", isOn: Binding(
                            get: { appState.reviewAISettings.shareRedactedTitles },
                            set: { appState.setReviewAIShareTitles($0) }
                        ))
                    }
                    Toggle(isOn: Binding(
                        get: { appState.selectedReviewAIHarnessIsConfirmed },
                        set: { appState.setReviewAIHarnessConfirmed($0) }
                    )) {
                        Text("Allow Hago to send this to \(selectedHarness.friendlyName)")
                    }
                    .toggleStyle(.switch)
                }

                Section("What it does") {
                    ChoiceRow(
                        title: "Suggest",
                        detail: "AI marks its pick on each item in Review. You accept or change it.",
                        isSelected: !automaticallyFiles
                    ) { setAutomaticallyFiles(false) }
                    ChoiceRow(
                        title: "File the sure ones for me",
                        detail: "When AI is very confident, it files the item and remembers the rule. Up to 10 at a time, and Review lets you undo them.",
                        isSelected: automaticallyFiles
                    ) { setAutomaticallyFiles(true) }

                    Toggle(isOn: Binding(
                        get: { appState.reviewAISettings.scheduleEnabled },
                        set: { appState.setReviewAIScheduleEnabled($0) }
                    )) {
                        Text("Check new activity on its own")
                        Text("Otherwise AI only looks when you press Check with AI in Review.")
                    }
                    .toggleStyle(.switch)
                    if appState.reviewAISettings.scheduleEnabled {
                        Picker("How often", selection: Binding(
                            get: { appState.reviewAISettings.scheduleInterval },
                            set: { appState.setReviewAIScheduleInterval($0) }
                        )) {
                            ForEach(ReviewAIScheduleInterval.allCases, id: \.self) { interval in
                                Text(interval.title).tag(interval)
                            }
                        }
                    }
                    Picker(selection: Binding(
                        get: { appState.reviewAISettings.profession },
                        set: { appState.setReviewAIProfession($0) }
                    )) {
                        ForEach(ReviewAIProfession.allCases) { profession in
                            Text(profession.displayName).tag(profession)
                        }
                    } label: {
                        Text("Your work")
                        Text("Helps AI tell your work apart from personal use.")
                    }
                }
                .disabled(!appState.selectedReviewAIHarnessIsConfirmed)

                Section {
                    DisclosureGroup("Advanced") {
                        advanced
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadFields()
            if appState.reviewAIHarnessStatuses.isEmpty {
                appState.refreshReviewAIHarnesses()
            }
        }
        .onChange(of: selectedHarness) {
            apiKey = ""
            keyMessage = nil
            loadFields()
        }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(appState.reviewAIIsReady ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryTitle)
                    .font(.headline)
                Text(summaryDetail)
                    .foregroundStyle(.secondary)
                if let message = appState.reviewAIScheduleState.message, appState.reviewAIScheduleState.outcome == .failed {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            if appState.reviewAIAnalysisState == .analyzing {
                ProgressView().controlSize(.small)
                Button("Stop") { appState.stopReviewAIAnalysis() }
            } else if appState.reviewAIIsReady {
                Button("Check Now") { appState.analyzeReview(scheduled: appState.reviewAISettings.scheduleEnabled) }
                    .disabled(appState.isDiscoveringReviewAIHarnesses)
            }
        }
        .padding(.vertical, 4)
    }

    private var summaryTitle: String {
        if selectedHarness == .disabled { return "AI suggestions are off" }
        if appState.reviewAIIsReady { return "AI helps with Review using \(selectedHarness.friendlyName)" }
        return "Finish setting up \(selectedHarness.friendlyName)"
    }

    private var summaryDetail: String {
        if selectedHarness == .disabled {
            return "Pick an AI below and it will sort what's waiting in Review into Work and Personal for you."
        }
        if !appState.reviewAIIsReady {
            if selectedHarness.isDirectProvider, !hasSavedKey { return "Add your API key, then allow sharing." }
            if !appState.selectedReviewAIHarnessIsConfirmed { return "Allow sharing below to turn it on." }
            return "\(selectedHarness.friendlyName) isn't available right now. Check that it's installed and signed in."
        }
        var parts = [automaticallyFiles ? "Files the sure ones and suggests the rest." : "Suggests a pick for each item."]
        if let last = appState.reviewAIScheduleState.lastAttemptAt {
            parts.append("Last checked \(last.formatted(.relative(presentation: .named))).")
        }
        if appState.reviewAISettings.scheduleEnabled, let next = appState.reviewAIScheduleState.nextRunAt {
            parts.append("Next check \(next.formatted(date: .omitted, time: .shortened)).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Choices

    private var selectedHarness: ReviewAIHarnessKind {
        appState.reviewAISettings.selectedHarness
    }

    /// Apps already installed come first; uninstalled ones stay visible so people know they exist.
    private var appHarnesses: [ReviewAIHarnessKind] {
        [ReviewAIHarnessKind.claudeCode, .codex, .pi].sorted { first, second in
            let available = { (harness: ReviewAIHarnessKind) in
                appState.reviewAIHarnessStatuses.first { $0.harness == harness }?.isAvailable == true
            }
            return available(first) && !available(second)
        }
    }

    /// One setting for both ways AI runs, so it never files on its own in one and not the other.
    private var automaticallyFiles: Bool {
        appState.reviewAISettings.automaticallyApplyHighConfidence || appState.reviewAISettings.automaticallyApplyScheduledReviews
    }

    private func setAutomaticallyFiles(_ enabled: Bool) {
        appState.setReviewAIAutomaticallyAppliesHighConfidence(enabled)
        appState.setReviewAIScheduledAutomaticApply(enabled)
    }

    private var sharingSummary: String {
        if selectedHarness.isDirectProvider {
            return "For items waiting in Review, Hago sends app names, website names, minutes and your kind of work. Full addresses, page contents, private windows and anything you told Hago never to record stay on this Mac. Your provider bills your API account."
        }
        return "For items waiting in Review, \(selectedHarness.friendlyName) receives app names, window titles, websites and minutes, plus your kind of work. It sends them to its own AI service under your sign-in. Private windows and anything you told Hago never to record are never included."
    }

    @ViewBuilder
    private var apiKeyRows: some View {
        if hasSavedKey {
            LabeledContent {
                Button("Remove Key") {
                    do {
                        try appState.disconnectDirectAI()
                        hasSavedKey = false
                        keyMessage = nil
                    } catch { keyMessage = error.localizedDescription }
                }
            } label: {
                Label("API key saved in Keychain", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else {
            HStack {
                SecureField("Paste your \(selectedHarness.displayName) API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    do {
                        try appState.saveDirectAICredential(apiKey)
                        apiKey = ""
                        hasSavedKey = true
                        keyMessage = nil
                    } catch { keyMessage = error.localizedDescription }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Link("Get an API key", destination: ReviewAIDirectCatalog.documentation(for: selectedHarness))
                .font(.caption)
        }
        if let keyMessage {
            Text(keyMessage).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
        }
    }

    // MARK: Advanced

    @ViewBuilder
    private var advanced: some View {
        Picker("Model", selection: Binding(
            get: { appState.reviewAISettings.selectedModel(for: selectedHarness) ?? "" },
            set: { modelID in
                appState.setReviewAIModel(modelID.isEmpty ? nil : modelID)
                customModelID = modelID
            }
        )) {
            Text(selectedHarness.isDirectProvider ? "Recommended" : "App default").tag("")
            ForEach(appState.availableReviewAIModels) { model in
                Text(model.isRecommended ? "\(model.displayName) (recommended)" : model.displayName).tag(model.modelID)
            }
            if let selected = appState.reviewAISettings.selectedModel(for: selectedHarness),
               !appState.availableReviewAIModels.contains(where: { $0.modelID == selected }) {
                Text("Custom: \(selected)").tag(selected)
            }
        }
        HStack {
            TextField("Other model ID", text: $customModelID)
                .textFieldStyle(.roundedBorder)
            Button("Use") { appState.setReviewAIModel(customModelID) }
                .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if !selectedHarness.isDirectProvider {
            Picker("Reasoning", selection: Binding(
                get: { appState.effectiveReviewAIReasoningEffort?.rawValue ?? "" },
                set: { appState.setReviewAIReasoningEffort(ReviewAIReasoningEffort(rawValue: $0)) }
            )) {
                Text("App default").tag("")
                ForEach(appState.availableReviewAIReasoningEfforts) { effort in
                    Text(effort == appState.recommendedReviewAIReasoningEffort ? "\(effort.displayName) (recommended)" : effort.displayName)
                        .tag(effort.rawValue)
                }
            }
            HStack {
                TextField("Path to \(selectedHarness.displayName), if Hago can't find it", text: $customBinaryPath)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { appState.setReviewAICustomBinaryPath(customBinaryPath, for: selectedHarness) }
            }
            if let status = appState.selectedReviewAIHarnessStatus {
                LabeledContent("Status") {
                    Text(status.message)
                        .foregroundStyle(status.isAvailable ? .green : .orange)
                        .textSelection(.enabled)
                }
            }
            Button {
                appState.refreshReviewAIHarnesses()
            } label: {
                Label("Look for AI apps again", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isDiscoveringReviewAIHarnesses)
        }
        Text("Automatic checks run only while Hago is open and your Mac is awake. Items AI already looked at aren't sent again unless they change.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func loadFields() {
        customBinaryPath = appState.reviewAISettings.customBinaryPath(for: selectedHarness) ?? ""
        customModelID = appState.reviewAISettings.selectedModel(for: selectedHarness) ?? ""
        hasSavedKey = selectedHarness.isDirectProvider && appState.hasDirectAICredential
    }
}

/// A radio choice with a sentence of explanation, which a plain radio picker can't show.
private struct ChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private extension ReviewAIHarnessKind {
    var friendlyName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .pi: "Pi"
        case .anthropic: "Claude API"
        case .openAI: "OpenAI API"
        case .disabled: "Off"
        }
    }

    var friendlyDetail: String {
        switch self {
        case .claudeCode: "Uses the Claude Code app on this Mac and your Claude sign-in. Nothing else to set up."
        case .codex: "Uses the Codex app on this Mac and your ChatGPT sign-in. Nothing else to set up."
        case .pi: "Uses the Pi command-line app on this Mac with its own settings."
        case .anthropic: "Pay per use with your own Anthropic API key."
        case .openAI: "Pay per use with your own OpenAI API key."
        case .disabled: ""
        }
    }
}
