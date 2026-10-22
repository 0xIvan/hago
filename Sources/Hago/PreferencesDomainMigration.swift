import Foundation

struct PreferencesDomainMigration {
    static let source = "local.hago.app"
    static let destination = "com.ivan.hago"
    static let marker = "hago.preferencesDomainMigration.v1"

    static func migrate(defaults: UserDefaults = .standard, sourceDomain: String = source, destinationDomain: String = destination) {
        var current = defaults.persistentDomain(forName: destinationDomain) ?? [:]
        guard current[marker] as? Bool != true else { return }
        let previous = defaults.persistentDomain(forName: sourceDomain) ?? [:]
        for (key, value) in previous where current[key] == nil { current[key] = value }
        current[marker] = true
        defaults.setPersistentDomain(current, forName: destinationDomain)
    }
}
