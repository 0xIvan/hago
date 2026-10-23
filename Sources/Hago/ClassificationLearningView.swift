import SwiftUI
import HagoCore

struct ClassificationLearningPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var remembering: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = appState.correctionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if appState.latestCorrectionActionID != nil {
                Button("Undo Last Correction or Learned Rule") { appState.undoLatestCorrection() }
            }
            ForEach(appState.learningSuggestions.prefix(5)) { suggestion in
                HStack {
                    VStack(alignment: .leading) {
                        Text(suggestion.rule.name)
                        Text("Consistent corrections across \(suggestion.days) days → \(suggestion.rule.action.kind.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Preview") { remembering = suggestion.rule }
                    Button("Dismiss") { appState.dismissLearningSuggestion(suggestion) }
                }
            }
        }
        .sheet(item: $remembering) { rule in
            RememberRulePreviewView(rule: rule).environmentObject(appState)
        }
    }
}

struct RememberRulePreviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let rule: Rule
    @State private var preview: RuleImpactPreview?
    @State private var previewError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(rule.name).font(.title2.bold())
            Text("Future matches will be \(rule.action.kind.displayName).")
            ForEach(rule.conditions) { condition in
                Text("\(condition.field.displayName) \(condition.operation.displayName) \(condition.value)")
                    .font(.callout).textSelection(.enabled)
            }
            if let preview {
                Text("Applies to \(preview.affectedCount) historical recordings (\(TimeFormatting().compactDuration(preview.affectedSeconds))).")
                Text("Explicit corrections and project assignments stay unchanged. Conflicting rules remain Needs review.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(preview.examples.enumerated()), id: \.offset) { _, example in
                    Text(example).font(.caption).lineLimit(2)
                }
            }
            if let previewError { Text(previewError).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Remember and Apply") {
                    appState.rememberRule(rule)
                    if appState.errorMessage == nil { dismiss() }
                }.disabled(preview == nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 540)
        .onAppear {
            do { preview = try appState.previewRememberedRule(rule) }
            catch { previewError = error.localizedDescription }
        }
    }
}
