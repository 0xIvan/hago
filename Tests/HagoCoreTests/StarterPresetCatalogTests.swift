import Foundation
import Testing
import HagoCore

struct StarterPresetCatalogTests {
    @Test
    func presetRulesHaveUniqueIDsAndPacksNeverDisagreeAboutAnAppOrSite() {
        let rules = StarterPresets.packs.flatMap(\.rules)
        #expect(Set(StarterPresets.packs.map(\.id)).count == StarterPresets.packs.count)
        #expect(Set(rules.map(\.id)).count == rules.count)
        let classifier = ActivityClassifier()
        for rule in rules {
            let condition = rule.conditions[0]
            let snapshot = condition.field == .host
                ? ActivitySnapshot(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 1,
                                   windowTitle: "", url: "https://\(condition.value)/", source: .chrome)
                : ActivitySnapshot(appName: rule.name, bundleIdentifier: condition.value, processIdentifier: 1,
                                   windowTitle: "", url: nil, source: .macOS)
            let disagreeing = rules.filter { $0.action.kind != rule.action.kind && classifier.matches(rule: $0, snapshot: snapshot) }
            #expect(disagreeing.isEmpty, "\(rule.name) [\(rule.presetID ?? "")] is contradicted by \(disagreeing.map { "\($0.name) [\($0.presetID ?? "")]" })")
        }
    }
}
