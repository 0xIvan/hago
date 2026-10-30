import Foundation

public struct RememberedRuleFactory {
    public init() {}

    public func rule(from segment: ClassifiedSegment, kind: ActivityKind, categoryID: UUID?) -> Rule? {
        rules(from: segment, kind: kind, categoryID: categoryID).first
    }

    public func rules(from segment: ClassifiedSegment, kind: ActivityKind, categoryID: UUID?) -> [Rule] {
        let snapshot = segment.segment.snapshot
        guard !snapshot.isPrivate, !snapshot.isDiscordWithoutTitle, kind == .work || kind == .personal else { return [] }
        let action = RuleAction(kind: kind, categoryID: categoryID, projectID: nil)
        func make(_ name: String, _ conditions: [RuleCondition]) -> Rule {
            Rule(name: "Remember \(name)", priority: 150, enabled: true, isBuiltIn: false,
                 action: action, conditions: conditions, origin: .user)
        }
        if !snapshot.host.isEmpty {
            let host = RuleCondition(field: .host, operation: .equals, value: snapshot.host)
            var options: [Rule] = []
            if let url = snapshot.url, var components = URLComponents(string: url) {
                components.query = nil
                components.fragment = nil
                if let sanitized = components.url?.absoluteString,
                   sanitized == url, components.path != "", components.path != "/" {
                    options.append(make("this page", [host, RuleCondition(field: .url, operation: .equals, value: sanitized)]))
                }
            }
            options.append(make("all of \(snapshot.host)", [host]))
            return options
        }
        let bundle = snapshot.bundleIdentifier
        guard !bundle.isEmpty,
              BrowserCapturePolicy.isWebApp(bundleIdentifier: bundle)
                || !BrowserCapturePolicy.isBrowser(bundleIdentifier: bundle, appName: snapshot.appName) else { return [] }
        let app = RuleCondition(field: .bundleIdentifier, operation: .equals, value: bundle)
        var options: [Rule] = []
        if !snapshot.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options.append(make("this title in \(snapshot.appName)", [app, RuleCondition(field: .windowTitle, operation: .equals, value: snapshot.windowTitle)]))
        }
        options.append(make("all of \(snapshot.appName)", [app]))
        return options
    }
}

public enum BrowserCapturePolicy {
    public static func isBrowser(bundleIdentifier: String, appName: String) -> Bool {
        let bundle = bundleIdentifier.lowercased()
        let names = ["google chrome", "safari", "firefox", "arc", "brave browser", "vivaldi", "opera", "microsoft edge", "orion", "zen browser"]
        let bundles = ["com.google.chrome", "com.apple.safari", "org.mozilla.firefox", "company.thebrowser.browser", "com.brave.browser", "com.vivaldi.vivaldi", "com.operasoftware.opera", "com.microsoft.edgemac", "com.kagi.kagimacos", "app.zen-browser.zen"]
        return names.contains(appName.lowercased()) || bundles.contains { bundle.hasPrefix($0) }
    }

    /// A Chrome web app (Add to Dock / Install) runs as its own app for one site, so an app-wide rule is safe.
    public static func isWebApp(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix("com.google.chrome.app.")
    }
}
