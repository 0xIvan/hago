import SwiftUI

struct RulesManagementView: View {
    @State private var selection = Pane.rules

    private enum Pane: String, CaseIterable, Identifiable {
        case rules = "Specific Rules"
        case defaults = "Work Defaults"

        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Specific rules override work defaults.").font(.headline)
                Text("Site, title, and project rules take precedence over whole-app defaults. Ignore rules always win. Your manual corrections stay unchanged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Configure", selection: $selection) {
                    ForEach(Pane.allCases) { pane in Text(pane.rawValue).tag(pane) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            if selection == .rules {
                RulesSettingsView().padding(20)
            } else {
                WorkProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
