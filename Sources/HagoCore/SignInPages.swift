import Foundation

extension ActivitySnapshot {
    /// Sign-in, single sign-on and sign-out pages are a step on the way to something else,
    /// so their time counts with the surrounding activity instead of asking for a decision.
    public var isSignInPage: Bool {
        guard let url, let components = URLComponents(string: url),
              let host = components.host?.lowercased(), !host.isEmpty else {
            return false
        }

        if SignInPages.hosts.contains(host)
            || SignInPages.hostSuffixes.contains(where: { host.hasSuffix($0) })
            || host.split(separator: ".").first.map({ SignInPages.hostLabels.contains(String($0)) }) == true {
            return true
        }

        let path = components.path.lowercased().split(separator: "/").map(String.init)
        if path.contains(where: SignInPages.pathComponents.contains) {
            return true
        }

        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.range(of: SignInPages.titlePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private enum SignInPages {
    static let hosts: Set<String> = [
        "accounts.google.com", "appleid.apple.com", "idmsa.apple.com", "account.apple.com",
        "login.microsoftonline.com", "login.live.com", "login.microsoft.com", "id.atlassian.com"
    ]
    static let hostSuffixes = [".okta.com", ".oktapreview.com", ".auth0.com", ".onelogin.com"]
    static let hostLabels: Set<String> = ["login", "signin", "sso", "auth", "oauth", "accounts", "identity", "idp"]
    static let pathComponents: Set<String> = [
        "login", "signin", "sign-in", "sign_in", "logout", "signout", "sign-out", "sign_out",
        "oauth", "oauth2", "authorize", "sso", "saml", "saml2"
    ]
    /// "Sign in", "Log in to Acme", "Sign in - Google Accounts", but not "Login flow redesign".
    static let titlePattern = #"^(sign|log)[ -]?(in|on)( (to|with) .+| [-–—|·:] .+)?$"#
}
