import SwiftUI
import HagoCore

struct LearningSuggestionsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var remembering: Rule?

    var body: some View {
        if !appState.learningSuggestions.isEmpty {
            Section("Make it automatic") {
                ForEach(appState.learningSuggestions.prefix(5)) { suggestion in
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.summary(for: suggestion.rule))
                            Text("You picked \(suggestion.rule.action.kind.displayName) on \(suggestion.days) days. Make it a rule?")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Dismiss") { appState.dismissLearningSuggestion(suggestion) }
                        Button("Preview Rule…") { remembering = suggestion.rule }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                    .padding(.vertical, 4)
                    .selectionDisabled()
                }
            }
            .sheet(item: $remembering) { rule in
                RememberRulePreviewView(rule: rule).environmentObject(appState)
            }
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Always \(rule.action.kind.displayName)")
                    .font(.title2.bold())
                Text("Activity matching this rule will be classified automatically from now on.")
                    .foregroundStyle(.secondary)
            }

            Label {
                Text(appState.summary(for: rule))
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: (RuleScope(conditions: rule.conditions)?.target ?? .title).symbolName)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if let preview {
                Label(
                    "Also reclassifies \(preview.affectedCount) past recordings (\(TimeFormatting().compactDuration(preview.affectedSeconds))).",
                    systemImage: "clock.arrow.circlepath"
                )
                if !preview.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(preview.examples.enumerated()), id: \.offset) { _, example in
                            Text(example).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Text("Your manual corrections and project assignments stay unchanged. Conflicting rules stay in Review.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let previewError { Text(previewError).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Rule") {
                    appState.rememberRule(rule)
                    if appState.errorMessage == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 540)
        .onAppear {
            do { preview = try appState.previewRememberedRule(rule) }
            catch { previewError = error.localizedDescription }
        }
    }
}
