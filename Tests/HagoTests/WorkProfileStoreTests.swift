import Foundation
import Testing
@testable import Hago

@MainActor
struct WorkProfileStoreTests {
    @Test
    func testReturningHistoryDoesNotForceSetupOrEnablePresets() {
        let suite = "WorkProfileTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkProfileStore(defaults: defaults)
        store.prepare(hasHistory: true, presetIDs: [])
        #expect(!store.needsSetup)
        #expect(store.profile.completed)
        #expect(store.profile.presetIDs.isEmpty)
    }

    @Test
    func testInterruptedSetupAndRuleIdentitiesSurviveRestart() {
        let suite = "WorkProfileTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkProfileStore(defaults: defaults)
        store.prepare(hasHistory: false, presetIDs: [])
        store.profile.step = 2
        let ruleID = UUID()
        store.profile.ruleIDs["app:test"] = ruleID
        let reloaded = WorkProfileStore(defaults: defaults)
        reloaded.prepare(hasHistory: true, presetIDs: [])
        #expect(reloaded.needsSetup)
        #expect(reloaded.profile.step == 2)
        #expect(reloaded.profile.ruleIDs["app:test"] == ruleID)
        reloaded.finish()
        let completed = WorkProfileStore(defaults: defaults)
        completed.prepare(hasHistory: true, presetIDs: [])
        #expect(!completed.needsSetup)
    }
}
