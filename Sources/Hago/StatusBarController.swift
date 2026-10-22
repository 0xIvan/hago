import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let menuItem = NSMenuItem()
    private weak var menuContentView: NSView?
    private var cancellables: Set<AnyCancellable> = []

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        configureButton()
        configureMenu()
        bindState()
        updateButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.font = statusTextFont()
        button.image = statusImage()
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        let contentView = NSHostingView(
            rootView: MenuBarContentView(
                openSettings: { [weak self, weak appState] in
                    self?.menu.cancelTracking()
                    DispatchQueue.main.async {
                        appState?.openSettingsWindow()
                    }
                }
            )
            .environmentObject(appState)
        )
        contentView.frame.size = contentView.fittingSize
        menuContentView = contentView

        menuItem.isEnabled = true
        menuItem.view = contentView
        menu.addItem(menuItem)
        statusItem.menu = menu
    }

    private func bindState() {
        appState.$todaySummary
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateButton()
                }
            }
            .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = statusItem.button else {
            return
        }

        button.attributedTitle = statusTitle(appState.menuBarTitle)
        button.setAccessibilityLabel(appState.menuBarAccessibilityLabel)
    }

    private func statusTitle(_ value: String) -> NSAttributedString {
        NSAttributedString(string: value, attributes: [.font: statusTextFont()])
    }

    private func statusTextFont() -> NSFont {
        NSFont.menuBarFont(ofSize: 0)
    }

    private func statusImage() -> NSImage? {
        let image = Self.activityTraceImage()
            ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Hago")

        image?.isTemplate = true

        return image
    }

    private static let activityTraceSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" \
    viewBox="2 2 20 20" fill="none" stroke="currentColor" stroke-width="2.4" \
    stroke-linecap="round">\
    <path d="M5.2 8.4A8.2 8.2 0 0 1 15.7 4.5"/>\
    <path d="M18.6 7.3A8.2 8.2 0 0 1 13.4 20"/>\
    <circle cx="9.8" cy="19.7" r="1.15" fill="currentColor" stroke="none"/>\
    <circle cx="6.6" cy="17.9" r="1" fill="currentColor" stroke="none"/>\
    <circle cx="4.6" cy="14.9" r="0.85" fill="currentColor" stroke="none"/>\
    </svg>
    """

    private static func activityTraceImage() -> NSImage? {
        guard let data = activityTraceSVG.data(using: .utf8),
              let image = NSImage(data: data) else {
            return nil
        }

        let iconSize = NSSize(width: 18, height: 18)
        let paddedImage = NSImage(
            size: NSSize(width: iconSize.width + 2, height: iconSize.height),
            flipped: false
        ) { _ in
            image.draw(
                in: NSRect(origin: .zero, size: iconSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }

        return paddedImage
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let menuContentView else {
            return
        }
        menuContentView.frame.size = menuContentView.fittingSize
    }
}
