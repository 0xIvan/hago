import Foundation
import Testing
@testable import Hago

struct PreferencesDomainMigrationTests {
    @Test
    func copiesMissingLegacyChoicesWithoutOverwritingCurrentChoicesAndRunsOnce() throws {
        let suite = "PreferenceMigrationTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let source = suite + ".source"
        let destination = suite + ".destination"
        defer {
            defaults.removePersistentDomain(forName: source)
            defaults.removePersistentDomain(forName: destination)
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.setPersistentDomain(["choice": "legacy", "profile": Data([1, 2, 3])], forName: source)
        defaults.setPersistentDomain(["choice": "current"], forName: destination)
        PreferencesDomainMigration.migrate(defaults: defaults, sourceDomain: source, destinationDomain: destination)
        let result = try #require(defaults.persistentDomain(forName: destination))
        #expect(result["choice"] as? String == "current")
        #expect(result["profile"] as? Data == Data([1, 2, 3]))
        defaults.setPersistentDomain(["addedLater": true], forName: source)
        PreferencesDomainMigration.migrate(defaults: defaults, sourceDomain: source, destinationDomain: destination)
        #expect(defaults.persistentDomain(forName: destination)?["addedLater"] == nil)
    }
}
