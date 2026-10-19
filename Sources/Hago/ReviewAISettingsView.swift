import HagoCore
import SwiftUI

struct ReviewAISettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var customBinaryPath = ""
    @State private var customModelID = ""

    var body: some View {
        Form {
            Section("Harness") {
                Picker("Local AI CLI", selection: selectedHarnessBinding) {
                    ForEach(ReviewAIHarnessKind.allCases) { harness in
                        Text(harness.displayName).tag(harness)
                    }
                }

                if selectedHarness != .disabled {
                    harnessStatus
                    privacyConfirmation
                }

                Button {
                    appState.refreshReviewAIHarnesses()
                } label: {
                    Label("Refresh Installed CLIs", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isDiscoveringReviewAIHarnesses)
            }

            if selectedHarness != .disabled {
                Section("Profession") {
                    Picker("Profession", selection: Binding(
                        get: { appState.reviewAISettings.profession },
                        set: { appState.setReviewAIProfession($0) }
                    )) {
                        ForEach(ReviewAIProfession.allCases) { profession in
                            Text(profession.displayName).tag(profession)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .environment(\.layoutDirection, .leftToRight)

                Section("Model and Reasoning") {
                    Picker("Model", selection: selectedModelBinding) {
                        Text("CLI Default").tag("")
                        ForEach(appState.availableReviewAIModels) { model in
                            Text(model.isRecommended ? "\(model.displayName) — Recommended" : model.displayName)
                                .tag(model.modelID)
                        }
                        if let selectedModelID = appState.reviewAISettings.selectedModel(for: selectedHarness),
                           !appState.availableReviewAIModels.contains(where: { $0.modelID == selectedModelID }) {
                            Text("Custom: \(selectedModelID)").tag(selectedModelID)
                        }
                    }

                    if let recommendedModel = appState.availableReviewAIModels.first(where: \.isRecommended) {
                        Text("Recommended model: \(recommendedModel.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Reasoning", selection: selectedReasoningBinding) {
                        Text("CLI Default").tag("")
                        ForEach(appState.availableReviewAIReasoningEfforts) { effort in
                            Text(
                                effort == appState.recommendedReviewAIReasoningEffort
                                    ? "\(effort.displayName) — Recommended"
                                    : effort.displayName
                            )
                            .tag(effort.rawValue)
                        }
                    }

                    HStack {
                        TextField("Custom model ID", text: $customModelID)
                            .textFieldStyle(.roundedBorder)
                        Button("Use Model") {
                            appState.setReviewAIModel(customModelID)
                        }
                        .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Text("CLI Default follows the harness configuration. A selected model and reasoning level apply only to Review analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Manual Analysis") {
                    Toggle(
                        "Apply safe suggestions at 95% confidence or higher",
                        isOn: automaticApplyBinding
                    )
                    .disabled(!appState.selectedReviewAIHarnessIsConfirmed)

                    Text("Hago applies at most 10 Work or Personal rules per analysis. Other suggestions remain ready for review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                scheduleSettings

                Section("Advanced") {
                    HStack {
                        TextField("Custom executable path", text: $customBinaryPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Path") {
                            appState.setReviewAICustomBinaryPath(customBinaryPath, for: selectedHarness)
                        }
                    }
                    Text("Leave this empty to use the executable found in your login shell PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Installed CLIs") {
                ForEach(appState.reviewAIHarnessStatuses) { status in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(status.isAvailable ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(status.harness.displayName)
                                .font(.headline)
                            Text(status.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let path = status.executablePath {
                                Text(path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if appState.isDiscoveringReviewAIHarnesses {
                    ProgressView("Checking installed CLIs")
                        .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadCustomBinaryPath()
            loadCustomModelID()
            if appState.reviewAIHarnessStatuses.isEmpty {
                appState.refreshReviewAIHarnesses()
            }
        }
        .onChange(of: selectedHarness) {
            loadCustomBinaryPath()
            loadCustomModelID()
        }
    }

    @ViewBuilder
    private var scheduleSettings: some View {
        Section("Scheduled Review") {
            Toggle("Enable scheduled review", isOn: Binding(
                get: { appState.reviewAISettings.scheduleEnabled },
                set: { appState.setReviewAIScheduleEnabled($0) }
            ))
            .disabled(!appState.selectedReviewAIHarnessIsConfirmed && !appState.reviewAISettings.scheduleEnabled)

            Picker("Run frequency", selection: Binding(
                get: { appState.reviewAISettings.scheduleInterval },
                set: { appState.setReviewAIScheduleInterval($0) }
            )) {
                ForEach(ReviewAIScheduleInterval.allCases, id: \.self) { interval in
                    Text(interval.title).tag(interval)
                }
            }

            Toggle("Apply safe scheduled suggestions automatically", isOn: Binding(
                get: { appState.reviewAISettings.automaticallyApplyScheduledReviews },
                set: { appState.setReviewAIScheduledAutomaticApply($0) }
            ))
            .disabled(!appState.selectedReviewAIHarnessIsConfirmed)

            Text("Off by default: scheduled runs save recommendations for you to review. When enabled, Hago checks saved advice again and applies at most 10 safe Work or Personal rules at 95% confidence per run.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Schedule", value: appState.reviewAISettings.scheduleEnabled ? "Active" : "Paused")
            if let date = appState.reviewAIScheduleState.lastAttemptAt {
                LabeledContent("Last run", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if appState.reviewAISettings.scheduleEnabled, let date = appState.reviewAIScheduleState.nextRunAt {
                LabeledContent("Next run", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let message = appState.reviewAIScheduleState.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(appState.reviewAIScheduleState.outcome == .failed ? .orange : .secondary)
                    .textSelection(.enabled)
            }

            HStack {
                if appState.reviewAIAnalysisState == .analyzing {
                    ProgressView("Analyzing Review")
                        .controlSize(.small)
                    Button("Stop", role: .cancel) { appState.stopReviewAIAnalysis() }
                } else {
                    Button("Run Now") { appState.analyzeReview(scheduled: true) }
                        .disabled(!appState.selectedReviewAIHarnessIsConfirmed || appState.isDiscoveringReviewAIHarnesses)
                }
                if appState.reviewAISettings.scheduleEnabled {
                    Button("Pause Schedule") { appState.setReviewAIScheduleEnabled(false) }
                }
            }

            Text("Runs only while Hago is open and your Mac is awake. After a missed time during sleep, Hago runs once. On launch, an overdue run waits for the next interval. Unchanged groups do not use the AI again. To reconsider them, use Analyze Review on the Review screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var harnessStatus: some View {
        if let status = appState.selectedReviewAIHarnessStatus {
            LabeledContent("Status") {
                Text(status.message)
                    .foregroundStyle(status.isAvailable ? .green : .orange)
            }
        } else {
            LabeledContent("Status", value: "Not checked")
        }
    }

    private var privacyConfirmation: some View {
        Toggle(isOn: confirmationBinding) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow Review activity to be sent to \(selectedHarness.displayName)")
                Text("The CLI can send your profession, app names, window titles, sites, URLs, and related rule values to its configured AI service.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedHarness: ReviewAIHarnessKind {
        appState.reviewAISettings.selectedHarness
    }

    private var selectedHarnessBinding: Binding<ReviewAIHarnessKind> {
        Binding(
            get: { selectedHarness },
            set: { appState.selectReviewAIHarness($0) }
        )
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { appState.selectedReviewAIHarnessIsConfirmed },
            set: { appState.setReviewAIHarnessConfirmed($0) }
        )
    }

    private var automaticApplyBinding: Binding<Bool> {
        Binding(
            get: { appState.reviewAISettings.automaticallyApplyHighConfidence },
            set: { appState.setReviewAIAutomaticallyAppliesHighConfidence($0) }
        )
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: {
                appState.reviewAISettings.selectedModel(for: selectedHarness) ?? ""
            },
            set: { modelID in
                appState.setReviewAIModel(modelID.isEmpty ? nil : modelID)
                customModelID = modelID
            }
        )
    }

    private var selectedReasoningBinding: Binding<String> {
        Binding(
            get: {
                appState.effectiveReviewAIReasoningEffort?.rawValue ?? ""
            },
            set: { rawValue in
                appState.setReviewAIReasoningEffort(ReviewAIReasoningEffort(rawValue: rawValue))
            }
        )
    }

    private func loadCustomBinaryPath() {
        customBinaryPath = appState.reviewAISettings.customBinaryPath(for: selectedHarness) ?? ""
    }

    private func loadCustomModelID() {
        customModelID = appState.reviewAISettings.selectedModel(for: selectedHarness) ?? ""
    }
}
