import Foundation

public struct ActivityClassifier {
    public init() {}

    public func classify(snapshot: ActivitySnapshot, rules: [Rule]) -> ClassificationResult {
        classify(snapshot: snapshot, preparedRules: preparedRules(from: rules))
    }

    public func preparedRules(from rules: [Rule]) -> [Rule] {
        rules
            .filter(\.enabled)
            .filter { !isUnsafeRememberedBrowserAppRule($0) }
            .sorted { first, second in
                if first.priority == second.priority {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }

                return first.priority < second.priority
            }
    }

    public func classify(snapshot: ActivitySnapshot, preparedRules: [Rule]) -> ClassificationResult {
        if snapshot.isPrivate {
            return ClassificationResult(kind: .ignored, categoryID: nil, projectID: nil, ruleID: nil)
        }

        if isSystemSnapshot(snapshot: snapshot) {
            return ClassificationResult(kind: .ignored, categoryID: nil, projectID: nil, ruleID: nil)
        }

        let matchingRules = preparedRules.filter { matches(rule: $0, snapshot: snapshot) }
        if let exclusion = matchingRules.first(where: { $0.action.kind == .ignored }) {
            return result(for: exclusion)
        }
        let personalRules = matchingRules.filter { $0.origin == .user }
        if !personalRules.isEmpty {
            let narrowest = personalRules.filter { candidate in
                !personalRules.contains { $0.parentRuleID == candidate.id }
            }
            let specificity = narrowest.map(scopeSpecificity).max() ?? 0
            return resolve(narrowest.filter { scopeSpecificity($0) == specificity })
        }
        if let legacy = matchingRules.first(where: { $0.origin == nil || $0.origin == .legacy }) {
            if snapshot.isDiscordWithoutTitle && legacy.isBuiltIn {
                return ClassificationResult(kind: .review, categoryID: nil, projectID: nil, ruleID: nil,
                                            reason: "Discord channel context is unavailable")
            }
            return result(for: legacy)
        }
        let aiRules = matchingRules.filter { $0.origin == .ai }
        if !aiRules.isEmpty { return resolve(aiRules) }
        return resolve(matchingRules.filter { $0.origin == .preset })
    }

    private func resolve(_ rules: [Rule]) -> ClassificationResult {
        guard let first = rules.first else {
            return ClassificationResult(kind: .review, categoryID: nil, projectID: nil, ruleID: nil,
                                        reason: "No matching rule; needs your input")
        }
        guard rules.allSatisfy({ $0.action == first.action }) else {
            return ClassificationResult(kind: .review, categoryID: nil, projectID: nil, ruleID: nil,
                                        reason: "Conflicting rules: " + rules.map(\.name).joined(separator: ", "))
        }
        return result(for: first)
    }

    private func result(for rule: Rule) -> ClassificationResult {
        ClassificationResult(kind: rule.action.kind, categoryID: rule.action.categoryID,
                             projectID: rule.action.projectID, ruleID: rule.id,
                             reason: "\(rule.origin == .preset ? "Preset" : rule.origin == .user ? "Personal rule" : rule.origin == .ai ? "AI rule" : "Legacy rule"): \(rule.name)")
    }

    private func scopeSpecificity(_ rule: Rule) -> Int {
        rule.conditions.reduce(0) { total, condition in
            total + (condition.field == .url ? 40 : condition.field == .windowTitle ? 30 : condition.field == .host ? 20 : 10)
        }
    }

    public func matches(rule: Rule, snapshot: ActivitySnapshot) -> Bool {
        guard !rule.conditions.isEmpty else {
            return false
        }

        return rule.conditions.allSatisfy { condition in
            matches(condition: condition, snapshot: snapshot)
        }
    }

    private func matches(condition: RuleCondition, snapshot: ActivitySnapshot) -> Bool {
        let source = value(for: condition.field, snapshot: snapshot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let target = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !target.isEmpty else {
            return false
        }

        switch condition.operation {
        case .contains:
            return source.localizedCaseInsensitiveContains(target)
        case .equals:
            return source.caseInsensitiveCompare(target) == .orderedSame
        case .domain:
            let normalizedSource = source.lowercased()
            let normalizedTarget = target.lowercased()
            return normalizedSource == normalizedTarget
                || normalizedSource.hasSuffix(".\(normalizedTarget)")
        case .startsWith:
            return source.lowercased().hasPrefix(target.lowercased())
        case .endsWith:
            return source.lowercased().hasSuffix(target.lowercased())
        case .regex:
            return source.range(of: target, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private func value(for field: RuleField, snapshot: ActivitySnapshot) -> String {
        switch field {
        case .appName:
            snapshot.appName
        case .bundleIdentifier:
            snapshot.bundleIdentifier
        case .windowTitle:
            snapshot.windowTitle
        case .url:
            snapshot.url ?? ""
        case .host:
            snapshot.host
        }
    }

    private func isUnsafeRememberedBrowserAppRule(_ rule: Rule) -> Bool {
        guard !rule.isBuiltIn,
              rule.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("remember "),
              rule.conditions.count == 1,
              let condition = rule.conditions.first,
              condition.operation == .equals,
              condition.field == .appName || condition.field == .bundleIdentifier else {
            return false
        }

        let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.contains("chrome")
            || value.contains("safari")
            || value.contains("arc")
            || value.contains("firefox")
    }

    private func isSystemSnapshot(snapshot: ActivitySnapshot) -> Bool {
        let app = snapshot.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bundle = snapshot.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return app == "loginwindow" || bundle == "com.apple.loginwindow"
            || app == "securityagent" || bundle == "com.apple.securityagent"
    }
}
