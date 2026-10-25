import Foundation

public enum RuleTarget: String, CaseIterable, Identifiable, Sendable {
    case app
    case website
    case page
    case title

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .app: "App"
        case .website: "Website"
        case .page: "Page"
        case .title: "Window Title"
        }
    }

    public var symbolName: String {
        switch self {
        case .app: "app"
        case .website: "globe"
        case .page: "doc.text"
        case .title: "macwindow"
        }
    }
}

public enum TitleMatch: String, CaseIterable, Identifiable, Sendable {
    case contains
    case exactly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .contains: "contains"
        case .exactly: "is exactly"
        }
    }
}

/// The user-facing shape of a rule: what it covers, in the terms people use.
/// Rules are still stored as conditions; anything that does not fit a scope is a custom rule.
public struct RuleScope: Equatable, Sendable {
    public var target: RuleTarget
    public var value: String
    public var includesSubdomains: Bool
    public var includesSubpages: Bool
    public var title: String
    public var titleMatch: TitleMatch

    public init(
        target: RuleTarget,
        value: String = "",
        includesSubdomains: Bool = true,
        includesSubpages: Bool = false,
        title: String = "",
        titleMatch: TitleMatch = .contains
    ) {
        self.target = target
        self.value = value
        self.includesSubdomains = includesSubdomains
        self.includesSubpages = includesSubpages
        self.title = title
        self.titleMatch = titleMatch
    }

    public init?(conditions: [RuleCondition]) {
        var remaining = conditions
        func take(_ field: RuleField, _ operations: Set<RuleOperation>) -> RuleCondition? {
            guard let index = remaining.firstIndex(where: { $0.field == field && operations.contains($0.operation) }) else {
                return nil
            }
            return remaining.remove(at: index)
        }

        let url = take(.url, [.equals, .startsWith])
        let bundle = take(.bundleIdentifier, [.equals])
        let host = url == nil && bundle == nil ? take(.host, [.equals, .domain]) : nil
        let pageHost = url != nil ? take(.host, [.equals]) : nil
        let title = url == nil ? take(.windowTitle, [.contains, .equals]) : nil
        guard remaining.isEmpty else { return nil }

        if let url {
            guard pageHost == nil || pageHost?.value.lowercased() == Self.host(of: url.value) else { return nil }
            self.init(target: .page, value: url.value, includesSubpages: url.operation == .startsWith)
        } else if let bundle {
            self.init(target: .app, value: bundle.value)
        } else if let host {
            self.init(target: .website, value: host.value, includesSubdomains: host.operation == .domain)
        } else if let title {
            self.init(target: .title, value: title.value, titleMatch: title.operation == .equals ? .exactly : .contains)
            return
        } else {
            return nil
        }

        if let title {
            self.title = title.value
            titleMatch = title.operation == .equals ? .exactly : .contains
        }
    }

    public var supportsTitle: Bool {
        target == .app || target == .website
    }

    public var isComplete: Bool {
        !normalizedValue.isEmpty
    }

    public var conditions: [RuleCondition] {
        let value = normalizedValue
        var conditions: [RuleCondition]
        switch target {
        case .app:
            conditions = [RuleCondition(field: .bundleIdentifier, operation: .equals, value: value)]
        case .website:
            conditions = [RuleCondition(field: .host, operation: includesSubdomains ? .domain : .equals, value: value)]
        case .page:
            conditions = [RuleCondition(field: .url, operation: includesSubpages ? .startsWith : .equals, value: value)]
            if let host = Self.host(of: value), !host.isEmpty {
                conditions.insert(RuleCondition(field: .host, operation: .equals, value: host), at: 0)
            }
        case .title:
            return [RuleCondition(field: .windowTitle, operation: titleMatch == .exactly ? .equals : .contains, value: value)]
        }

        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if supportsTitle, !title.isEmpty {
            conditions.append(RuleCondition(field: .windowTitle, operation: titleMatch == .exactly ? .equals : .contains, value: title))
        }
        return conditions
    }

    /// Websites accept pasted links and keep only the host.
    public var normalizedValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target == .website else { return trimmed }
        if trimmed.contains("://"), let host = Self.host(of: trimmed) {
            return host
        }
        return trimmed.lowercased()
    }

    public func subject(appName: (String) -> String) -> String {
        switch target {
        case .app: appName(normalizedValue)
        case .website: normalizedValue
        case .page: Self.displayURL(normalizedValue)
        case .title: "“\(normalizedValue)”"
        }
    }

    public func summary(appName: (String) -> String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleClause = title.isEmpty ? nil : (titleMatch == .exactly ? "titled “\(title)”" : "with “\(title)” in the title")
        switch target {
        case .app:
            let app = appName(normalizedValue)
            return titleClause.map { "\(app) windows \($0)" } ?? "Everything in \(app)"
        case .website:
            let site = includesSubdomains ? "All of \(normalizedValue) and its subdomains" : "All of \(normalizedValue)"
            return titleClause.map { "\(normalizedValue) pages \($0)" } ?? site
        case .page:
            return includesSubpages ? "\(Self.displayURL(normalizedValue)) and pages under it" : "This page: \(Self.displayURL(normalizedValue))"
        case .title:
            return titleMatch == .exactly ? "Any window titled “\(normalizedValue)”" : "Any window with “\(normalizedValue)” in the title"
        }
    }

    public func defaultName(kind: ActivityKind, appName: (String) -> String) -> String {
        kind == .ignored ? "Never record \(summary(appName: appName))" : "\(summary(appName: appName)) → \(kind.displayName)"
    }

    static func host(of url: String) -> String? {
        URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased()
    }

    static func displayURL(_ url: String) -> String {
        var display = url
        for prefix in ["https://", "http://"] where display.hasPrefix(prefix) {
            display.removeFirst(prefix.count)
        }
        if display.hasPrefix("www.") { display.removeFirst(4) }
        return display
    }
}
