import Foundation

public struct ActivityClassifier {
    public init() {}

    public func classify(snapshot: ActivitySnapshot, rules: [Rule]) -> ClassificationResult {
        classify(snapshot: snapshot, preparedRules: preparedRules(from: rules))
    }

    public func preparedRules(from rules: [Rule]) -> PreparedRules {
        PreparedRules(
            rules
                .filter(\.enabled)
                .filter { !isUnsafeRememberedBrowserAppRule($0) }
                .sorted { first, second in
                    if first.priority == second.priority {
                        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                    }

                    return first.priority < second.priority
                }
        )
    }

    public func classify(snapshot: ActivitySnapshot, preparedRules: PreparedRules) -> ClassificationResult {
        classify(snapshot: snapshot, values: SnapshotValues(snapshot), preparedRules: preparedRules)
    }

    func classify(snapshot: ActivitySnapshot, values: SnapshotValues, preparedRules: PreparedRules) -> ClassificationResult {
        if snapshot.isPrivate {
            return ClassificationResult(kind: .ignored, categoryID: nil, projectID: nil, ruleID: nil)
        }

        if isSystemSnapshot(snapshot: snapshot) {
            return ClassificationResult(kind: .ignored, categoryID: nil, projectID: nil, ruleID: nil)
        }

        let matchingRules = preparedRules.matchingRules(for: values)
        if let exclusion = matchingRules.first(where: { $0.action.kind == .ignored }) {
            return result(for: exclusion)
        }
        let humanRules = matchingRules.filter {
            $0.origin == .user || $0.origin == .profile || $0.origin == .legacy || $0.origin == nil
        }
        if !humanRules.isEmpty {
            let narrowest = humanRules.filter { candidate in
                !humanRules.contains { $0.parentRuleID == candidate.id }
            }
            let specificity = narrowest.map(scopeSpecificity).max() ?? 0
            let specificRules = narrowest.filter { scopeSpecificity($0) == specificity }
            let personalRules = specificRules.filter { $0.origin == .user && !$0.isWorkDefault }
            if !personalRules.isEmpty { return resolve(personalRules) }
            let defaults = specificRules.filter(\.isWorkDefault)
            if !defaults.isEmpty { return resolve(defaults) }
            guard let legacy = specificRules.first else { return resolve([]) }
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
                             reason: "\(rule.isWorkDefault ? "Work default" : rule.origin == .preset ? "Preset" : rule.origin == .user ? "Personal rule" : rule.origin == .ai ? "AI rule" : "Legacy rule"): \(rule.name)")
    }

    private func scopeSpecificity(_ rule: Rule) -> Int {
        rule.conditions.reduce(0) { total, condition in
            total + (condition.field == .url ? 40 : condition.field == .windowTitle ? 30 : condition.field == .host ? 20 : 10)
        }
    }

    public func matches(rule: Rule, snapshot: ActivitySnapshot) -> Bool {
        PreparedCondition.matches(rule.conditions.map(PreparedCondition.init), values: SnapshotValues(snapshot))
    }

    private func isUnsafeRememberedBrowserAppRule(_ rule: Rule) -> Bool {
        guard !rule.isBuiltIn,
              rule.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("remember "),
              rule.conditions.count == 1,
              let condition = rule.conditions.first,
              condition.operation == .equals,
              condition.field == .appName || condition.field == .bundleIdentifier,
              !(condition.field == .bundleIdentifier && BrowserCapturePolicy.isWebApp(bundleIdentifier: condition.value)) else {
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

/// Rules sorted by precedence, bucketed by an exact host, bundle, app or URL value so
/// classification only evaluates rules that can match instead of every rule.
public struct PreparedRules: Sendable {
    public let rules: [Rule]
    private let conditions: [[PreparedCondition]]
    private let exactIndex: [RuleField: [String: [Int]]]
    private let domainIndex: [String: [Int]]
    private let unindexed: [Int]

    public init(_ sortedRules: [Rule]) {
        rules = sortedRules
        conditions = sortedRules.map { $0.conditions.map(PreparedCondition.init) }
        var exactIndex: [RuleField: [String: [Int]]] = [:]
        var domainIndex: [String: [Int]] = [:]
        var unindexed: [Int] = []

        for (index, conditions) in conditions.enumerated() {
            if let condition = conditions.first(where: \.isExactKey) {
                exactIndex[condition.field, default: [:]][condition.lowercasedTarget, default: []].append(index)
            } else if let condition = conditions.first(where: \.isDomainKey) {
                domainIndex[condition.lowercasedTarget, default: []].append(index)
            } else {
                unindexed.append(index)
            }
        }

        self.exactIndex = exactIndex
        self.domainIndex = domainIndex
        self.unindexed = unindexed
    }

    func matchingRules(for values: SnapshotValues) -> [Rule] {
        candidateIndices(for: values)
            .filter { PreparedCondition.matches(conditions[$0], values: values) }
            .map { rules[$0] }
    }

    func candidateIndices(for values: SnapshotValues) -> [Int] {
        let indexedFields: [RuleField] = [.host, .bundleIdentifier, .appName, .url]

        // Case-insensitive comparison of non-ASCII text can differ from lowercased keys.
        guard indexedFields.allSatisfy({ values[$0].isASCII }) else {
            return Array(rules.indices)
        }

        var indices = unindexed
        for field in indexedFields {
            if let hits = exactIndex[field]?[values[field].lowercased] {
                indices.append(contentsOf: hits)
            }
        }

        var suffix = Substring(values[.host].lowercased)
        while !suffix.isEmpty {
            if let hits = domainIndex[String(suffix)] {
                indices.append(contentsOf: hits)
            }
            guard let dot = suffix.firstIndex(of: ".") else { break }
            suffix = suffix[suffix.index(after: dot)...]
        }

        return indices.sorted()
    }
}

struct PreparedCondition: Sendable {
    let field: RuleField
    let operation: RuleOperation
    let target: String
    let lowercasedTarget: String
    let isASCII: Bool

    init(_ condition: RuleCondition) {
        field = condition.field
        operation = condition.operation
        target = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        lowercasedTarget = target.lowercased()
        isASCII = target.utf8.allSatisfy { $0 < 0x80 }
    }

    var isExactKey: Bool {
        operation == .equals && field != .windowTitle && isASCII && !target.isEmpty
    }

    var isDomainKey: Bool {
        operation == .domain && field == .host && isASCII && !target.isEmpty
            && !target.hasPrefix(".") && !target.hasSuffix(".")
    }

    static func matches(_ conditions: [PreparedCondition], values: SnapshotValues) -> Bool {
        guard !conditions.isEmpty, conditions.allSatisfy({ $0.matches(values[$0.field]) }) else { return false }
        // Older builds recorded Chrome's front tab under a web app's name, so an app-wide rule for the web app
        // must not claim those sites.
        return !(values.isWebAppWithSite && conditions.allSatisfy { $0.field == .appName || $0.field == .bundleIdentifier })
    }

    func matches(_ source: FieldValue) -> Bool {
        guard !target.isEmpty else {
            return false
        }

        let asciiOnly = isASCII && source.isASCII
        switch operation {
        case .contains:
            // ASCII lowercasing is a cheap superset check; the localized comparison stays authoritative.
            if asciiOnly, !asciiContains(source.lowercased, lowercasedTarget) {
                return false
            }
            return source.text.localizedCaseInsensitiveContains(target)
        case .equals:
            if asciiOnly {
                return source.lowercased == lowercasedTarget
            }
            return source.text.caseInsensitiveCompare(target) == .orderedSame
        case .domain:
            return source.lowercased == lowercasedTarget
                || source.lowercased.hasSuffix(".\(lowercasedTarget)")
        case .startsWith:
            return source.lowercased.hasPrefix(lowercasedTarget)
        case .endsWith:
            return source.lowercased.hasSuffix(lowercasedTarget)
        case .regex:
            return source.text.range(of: target, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

private func asciiContains(_ haystack: String, _ needle: String) -> Bool {
    var haystack = haystack
    var needle = needle
    return haystack.withUTF8 { source in
        needle.withUTF8 { target in
            guard target.count <= source.count, let first = target.first else { return target.isEmpty }
            var index = 0
            let last = source.count - target.count
            while index <= last {
                if source[index] == first {
                    var offset = 1
                    while offset < target.count, source[index + offset] == target[offset] {
                        offset += 1
                    }
                    if offset == target.count { return true }
                }
                index += 1
            }
            return false
        }
    }
}

struct FieldValue {
    let text: String
    let lowercased: String
    let isASCII: Bool

    init(_ value: String) {
        text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lowercased = text.lowercased()
        isASCII = text.utf8.allSatisfy { $0 < 0x80 }
    }
}

struct SnapshotValues {
    private let host: FieldValue
    private let bundleIdentifier: FieldValue
    private let appName: FieldValue
    private let url: FieldValue
    private let windowTitle: FieldValue
    let isWebAppWithSite: Bool

    init(_ snapshot: ActivitySnapshot) {
        host = FieldValue(snapshot.host)
        bundleIdentifier = FieldValue(snapshot.bundleIdentifier)
        appName = FieldValue(snapshot.appName)
        url = FieldValue(snapshot.url ?? "")
        windowTitle = FieldValue(snapshot.windowTitle)
        isWebAppWithSite = !host.text.isEmpty && BrowserCapturePolicy.isWebApp(bundleIdentifier: bundleIdentifier.text)
    }

    subscript(field: RuleField) -> FieldValue {
        switch field {
        case .appName: appName
        case .bundleIdentifier: bundleIdentifier
        case .windowTitle: windowTitle
        case .url: url
        case .host: host
        }
    }
}
