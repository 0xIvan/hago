import Foundation
import Testing
import HagoCore
@testable import Hago

@Suite
struct ReviewAISettingsStoreTests {
    @Test
    func loadingLegacySettingsRemovesFreeTextAndPreservesPreferences() throws {
        let suiteName = "hago-settings-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "hago.review-ai.settings.v1"
        defaults.set(Data(
            #"{"workContext":"I am a software developer. Legacy personal notes.","selectedHarness":"codex","confirmedHarnesses":["codex"],"selectedModels":{"codex":"test-model"},"scheduleEnabled":true,"scheduleInterval":7200,"automaticallyApplyScheduledReviews":false}"#.utf8
        ), forKey: key)

        let store = ReviewAISettingsStore(defaults: defaults)
        let settings = store.load()
        #expect(settings.profession == .softwareDeveloper)
        #expect(settings.scheduleEnabled)
        #expect(settings.scheduleInterval == .twoHours)
        #expect(!settings.automaticallyApplyScheduledReviews)
        #expect(settings.confirmedHarnesses == [.codex])
        #expect(settings.selectedModel(for: .codex) == "test-model")

        let saved = try #require(defaults.data(forKey: key))
        let object = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(object["workContext"] == nil)
        #expect(object["profession"] as? String == "softwareDeveloper")
        #expect(store.load() == settings)
    }
}
