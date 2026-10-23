import AppKit
import SwiftUI
import HagoCore

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore
    @Environment(\.colorScheme) private var colorScheme

    var openSettings: () -> Void = {}

    private let formatter = TimeFormatting()
    private let contentWidth: CGFloat = 284

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !profileStore.profile.completed {
                SetupReminderCard {
                    profileStore.needsSetup = true
                    openSettings()
                }
            } else if !appState.accessibilityTrusted {
                MenuActionButton(title: "Grant Accessibility Access…") { appState.requestAccessibilityPermission() }
                    .help("Allow window context recognition. App-level tracking remains available.")
            }
            metrics
            currentActivity

            if let message = appState.trackingErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            MenuActionButton(
                title: appState.isTrackingPaused ? "Resume Tracking" : "Pause Tracking",
                symbol: appState.isTrackingPaused ? "play" : "pause"
            ) {
                appState.toggleTracking()
            }

            if appState.reviewAISettings.scheduleEnabled,
               appState.reviewAIScheduleState.consecutiveFailures >= 3 {
                Label("Scheduled Review needs attention. Check AI suggestions settings.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let errorMessage = appState.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()
            actions
        }
        .padding(16)
        .frame(width: contentWidth)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: menuIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            Text("Hago")
                .font(.headline)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle()
                    .fill(kindColor(appState.currentClassification?.kind))
                    .frame(width: 6, height: 6)
                Text(appState.currentStateLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(kindColor(appState.currentClassification?.kind))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                kindColor(appState.currentClassification?.kind).opacity(0.12),
                in: Capsule()
            )
        }
    }

    private var menuIcon: NSImage {
        let resourceName = colorScheme == .dark ? "AppIcon-dark" : "AppIcon"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSApp.applicationIconImage
        }
        return image
    }

    private var metrics: some View {
        HStack(spacing: 14) {
            metric(
                title: "WORK TODAY",
                value: formatter.compactDuration(appState.todaySummary.workSeconds),
                color: .blue
            )
            Divider()
                .frame(height: 36)
            metric(
                title: "TRACKED TODAY",
                value: formatter.compactDuration(appState.todayTrackedSeconds),
                color: .primary
            )
        }
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var currentActivity: some View {
        if let snapshot = appState.currentSnapshot {
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT ACTIVITY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                    Text(snapshot.appName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                if !snapshot.windowTitle.isEmpty {
                    Text(snapshot.windowTitle)
                        .font(.caption)
                        .lineLimit(2)
                }
                if let url = snapshot.url, !url.isEmpty {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        } else {
            Label("Waiting for current activity", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            MenuActionButton(title: "Open Hago", symbol: "macwindow", action: openSettings)
            Spacer()
            MenuActionButton(title: "Quit", symbol: "power", bordered: false) {
                NSApp.terminate(nil)
            }
        }
    }

    private func kindColor(_ kind: ActivityKind?) -> Color {
        switch kind {
        case .work:
            .blue
        case .personal:
            .green
        case .review:
            .orange
        case .ignored:
            .secondary
        case nil:
            .secondary
        }
    }
}

/// The same AppKit push button Uso and MacMirrorly use in their menus; SwiftUI's bordered style renders shorter and squarer there.
private struct MenuActionButton: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var symbol: String?
    var bordered = true
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.performAction))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.imageHugsTitle = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.isEnabled = isEnabled
        button.isBordered = bordered
        button.contentTintColor = bordered ? nil : .secondaryLabelColor
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(.init(pointSize: NSFont.smallSystemFontSize, weight: .regular))
        button.imagePosition = symbol == nil ? .noImage : .imageLeading
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func performAction() { action() }
    }
}
