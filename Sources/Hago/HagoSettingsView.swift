import SwiftUI

struct HagoSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: HagoSection? = .profile

    var body: some View {
        NavigationSplitView {
            List(HagoSection.settingsSections, selection: $selection) { section in
                Label(section.title, systemImage: section.symbolName).tag(section)
            }.navigationSplitViewColumnWidth(180)
        } detail: {
            Group {
                switch selection {
                case .profile: WorkProfileView()
                case .rules: RulesSettingsView()
                case .projects: ProjectsSettingsView()
                case .categories: CategoriesSettingsView()
                case .privacy: PrivacySettingsView()
                case .aiReview: ReviewAISettingsView()
                default: TrackingSettingsView()
                }
            }.padding(selection == .profile || selection == .tracking ? 0 : 20)
        }
        .frame(minWidth: 850, minHeight: 650)
        .background(WindowLifecycleView(id: "settings"))
        .onAppear {
            appState.prepareToOpenAppWindow()
            if HagoSection.settingsSections.contains(appState.selectedSettingsSection) { selection = appState.selectedSettingsSection }
        }
        .onChange(of: selection) { _, section in
            if let section { appState.selectedSettingsSection = section }
        }
        .onChange(of: appState.selectedSettingsSection) { _, section in
            if HagoSection.settingsSections.contains(section) { selection = section }
        }
    }
}
