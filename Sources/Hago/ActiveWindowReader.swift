import AppKit
import Carbon
import ApplicationServices
import CoreGraphics
import Foundation
import HagoCore

struct ActiveWindowReader {
    private let accessibilityTrustCheck: () -> Bool
    private let accessibilityPermissionPrompt: () -> Void
    private let chromeAutomationPermission: (Bool) -> OSStatus

    init(
        accessibilityTrustCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
        accessibilityPermissionPrompt: @escaping () -> Void = {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        },
        chromeAutomationPermission: @escaping (Bool) -> OSStatus = {
            ActiveWindowReader.chromeAutomationPermissionStatus(requestPermission: $0)
        }
    ) {
        self.accessibilityTrustCheck = accessibilityTrustCheck
        self.accessibilityPermissionPrompt = accessibilityPermissionPrompt
        self.chromeAutomationPermission = chromeAutomationPermission
    }

    @MainActor
    func currentSnapshot() async -> ActivitySnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = application.localizedName ?? "Unknown"
        let bundle = application.bundleIdentifier ?? ""
        let pid = application.processIdentifier
        return await Task.detached(priority: .utility) {
            Self.snapshot(appName: appName, bundleIdentifier: bundle, processIdentifier: pid)
        }.value
    }

    func captureCapabilityLabel() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "No foreground application" }
        let bundle = app.bundleIdentifier ?? ""
        if bundle == "com.google.Chrome" {
            return chromeAutomationIsGranted()
                ? "Chrome: Automation granted; public-window context verified per observation"
                : "Chrome: tracking paused; Automation permission is missing. Use Allow Chrome Access in Tracking & Privacy."
        }
        if BrowserCapturePolicy.isBrowser(bundleIdentifier: bundle, appName: app.localizedName ?? "") {
            return "\(app.localizedName ?? "Browser"): time counted for the app only; sites and titles need Chrome"
        }
        return accessibilityIsTrusted() ? "App and window context available" : "App tracking available; Accessibility access needed for window titles"
    }

    private static func snapshot(appName: String, bundleIdentifier: String, processIdentifier: pid_t) -> ActivitySnapshot? {
        // Other browsers can't say whether a window is private, so only the app is recorded: no title, no address.
        if BrowserCapturePolicy.isBrowser(bundleIdentifier: bundleIdentifier, appName: appName) && bundleIdentifier != "com.google.Chrome" {
            return ActivitySnapshot(
                appName: appName, bundleIdentifier: bundleIdentifier, processIdentifier: processIdentifier,
                windowTitle: "", url: nil, source: .macOS, isPrivate: false
            )
        }
        let chromeInfo = chromeTabInfo(bundleIdentifier: bundleIdentifier, appName: appName)
        if bundleIdentifier == "com.google.Chrome", chromeInfo == nil { return nil }
        return ActivitySnapshot(
            appName: appName, bundleIdentifier: bundleIdentifier, processIdentifier: processIdentifier,
            windowTitle: chromeInfo?.title ?? focusedWindowTitle(processIdentifier: processIdentifier),
            url: chromeInfo?.url, source: chromeInfo == nil ? .macOS : .chrome,
            isPrivate: chromeInfo?.isPrivate ?? false
        )
    }

    func chromeAutomationIsGranted() -> Bool {
        chromeAutomationPermission(false) == noErr
    }

    @MainActor
    func requestChromeAutomationPermission() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            Self.chromeAutomationPermissionStatus(requestPermission: true) == noErr
        }.value
    }

    private static func chromeAutomationPermissionStatus(requestPermission: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let bundleID = Data("com.google.Chrome".utf8)
        let status = bundleID.withUnsafeBytes { bytes in
            AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress, bytes.count, &target)
        }
        guard status == noErr else { return OSStatus(status) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), requestPermission)
    }

    func accessibilityIsTrusted() -> Bool {
        accessibilityTrustCheck()
    }

    func requestAccessibilityPermission() {
        // Recheck macOS, not the UI's last poll: access may have changed while Settings was open.
        guard !accessibilityIsTrusted() else {
            return
        }
        accessibilityPermissionPrompt()
    }

    private static func focusedWindowTitle(processIdentifier: pid_t) -> String {
        if let title = accessibilityWindowTitle(processIdentifier: processIdentifier), !title.isEmpty {
            return title
        }

        return graphicsWindowTitle(processIdentifier: processIdentifier)
    }

    private static func accessibilityWindowTitle(processIdentifier: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard windowResult == .success, let focusedWindow else {
            return nil
        }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        guard titleResult == .success else {
            return nil
        }

        return titleValue as? String
    }

    private static func graphicsWindowTitle(processIdentifier: pid_t) -> String {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return ""
        }

        let window = windows.first { info in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int
            else {
                return false
            }

            return ownerPID == processIdentifier && layer == 0
        }

        return window?[kCGWindowName as String] as? String ?? ""
    }

    private static func chromeTabInfo(bundleIdentifier: String, appName: String) -> ChromeTabInfo? {
        guard bundleIdentifier == "com.google.Chrome", chromeAutomationPermissionStatus(requestPermission: false) == noErr else {
            return nil
        }

        let source = """
        with timeout of 2 seconds
        tell application id "com.google.Chrome"
            if (count of windows) is 0 then return ""
            set windowMode to mode of front window as string
            if windowMode is "incognito" then return windowMode
            set activeTab to active tab of front window
            return windowMode & linefeed & (URL of activeTab) & linefeed & (title of activeTab)
        end tell
        end timeout
        """

        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else {
            return nil
        }

        let lines = result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let mode = lines.first else {
            return nil
        }

        if mode.caseInsensitiveCompare("incognito") == .orderedSame {
            return ChromeTabInfo(url: nil, title: "Incognito", isPrivate: true)
        }

        guard mode.caseInsensitiveCompare("normal") == .orderedSame,
              let url = lines.dropFirst().first, URL(string: url)?.scheme != nil else { return nil }
        return ChromeTabInfo(
            url: url,
            title: lines.dropFirst(2).first ?? "",
            isPrivate: false
        )
    }
}

private struct ChromeTabInfo {
    var url: String?
    var title: String
    var isPrivate: Bool
}
