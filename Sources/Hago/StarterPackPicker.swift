import HagoCore
import SwiftUI

struct StarterPackPicker: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore
    @State private var showsOtherPacks = false

    private var profession: ReviewAIProfession { appState.reviewAISettings.profession }

    var body: some View {
        let recommended = StarterPresets.defaultPresetIDs(for: profession)
        let others = StarterPresets.packs.filter { !recommended.contains($0.id) }
        let othersOn = others.filter { profileStore.profile.presetIDs.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 12) {
            Picker("Profession", selection: Binding(get: { profession }, set: { choose($0) })) {
                ForEach(ReviewAIProfession.allCases) { profession in
                    Text(profession.displayName).tag(profession)
                }
            }
            .pickerStyle(.menu)
            ForEach(StarterPresets.packs.filter { recommended.contains($0.id) }) { packToggle($0) }
            DisclosureGroup(othersOn == 0 ? "More starter rules" : "More starter rules (\(othersOn) on)", isExpanded: $showsOtherPacks) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(others) { packToggle($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choose(_ newProfession: ReviewAIProfession) {
        profileStore.profile.presetIDs = StarterPresets.presetIDs(
            profileStore.profile.presetIDs, switchingFrom: profession, to: newProfession
        )
        appState.setReviewAIProfession(newProfession)
    }

    private func packToggle(_ pack: StarterPreset) -> some View {
        Toggle(isOn: Binding(
            get: { profileStore.profile.presetIDs.contains(pack.id) },
            set: { enabled in
                if enabled { profileStore.profile.presetIDs.insert(pack.id) }
                else { profileStore.profile.presetIDs.remove(pack.id) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                Text(pack.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }
}
