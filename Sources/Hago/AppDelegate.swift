import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState

    override init() {
        PreferencesDomainMigration.migrate()
        appState = AppState()
        super.init()
    }

    private var statusBarController: StatusBarController?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeAppearance()
        statusBarController = StatusBarController(appState: appState)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopTracking()
        appearanceObservation?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        if appState.flushTracking() { return .terminateNow }
        alert.messageText = "Some tracked time has not been saved"
        alert.informativeText = "Keep Hago open to retry saving, or quit and lose the unsaved time."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Quit Anyway")

        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    private func observeAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateApplicationIcon()
            }
        }
    }

    private func updateApplicationIcon() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let resourceName = isDark ? "AppIcon-dark" : "AppIcon"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return
        }
        NSApp.applicationIconImage = image
        NSApp.dockTile.display()
    }
}
