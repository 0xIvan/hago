import Foundation
import HagoCore

struct ReviewAISettingsStore {
    private let defaults: UserDefaults
    private let key = "hago.review-ai.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ReviewAISettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ReviewAISettings.self, from: data) else {
            return ReviewAISettings()
        }
        // Remove the obsolete free-text context after converting the saved profession.
        if let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           stored["workContext"] != nil {
            save(settings)
        }
        return settings
    }

    func save(_ settings: ReviewAISettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
