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
        HStack(spacing: 16) {
            DayRing(
                day: HagoCalendar.shared.dayInterval(containing: appState.todaySummary.date),
                spans: ActivityAggregation.timelineSpans(from: appState.todayTimeline),
                now: Date(),
                lineWidth: 9
            ) { _ in
                VStack(spacing: 0) {
                    Text(formatter.compactDuration(appState.todayTrackedSeconds))
                        .font(.hagoNumber(15))
                    Text("today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 9) {
                metric(.work, seconds: appState.todaySummary.workSeconds)
                metric(.personal, seconds: appState.todaySummary.personalSeconds)
                if appState.todaySummary.reviewSeconds > 0 {
                    metric(.review, seconds: appState.todaySummary.reviewSeconds)
                }
            }
        }
    }

    private func metric(_ kind: ActivityKind, seconds: TimeInterval) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(kind.tint)
                .frame(width: 4, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind == .review ? "Not filed" : kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatter.compactDuration(seconds))
                    .font(.hagoNumber(15))
                    .foregroundStyle(kind.tint)
            }
        }
    }

    private var currentActivity: some View {
        HStack(spacing: 10) {
            activityDetails
            Spacer(minLength: 0)
            pauseButton
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HagoPalette.track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var activityDetails: some View {
        if appState.isTrackingPaused {
            activityLabel(
                icon: Image(systemName: "pause.circle.fill").font(.system(size: 26)).foregroundStyle(.secondary),
                title: "Tracking paused",
                subtitle: "Nothing is recorded until you resume"
            )
        } else if let snapshot = appState.currentSnapshot {
            activityLabel(
                icon: AppIconView(bundleIdentifier: snapshot.bundleIdentifier, host: snapshot.host, size: 30),
                title: snapshot.host.isEmpty ? snapshot.appName : snapshot.host,
                subtitle: snapshot.windowTitle
            )
            .help(snapshot.url ?? snapshot.windowTitle)
        } else {
            activityLabel(
                icon: Image(systemName: "hourglass").font(.system(size: 18)).foregroundStyle(.secondary),
                title: "Waiting for activity",
                subtitle: ""
            )
        }
    }

    private func activityLabel(icon: some View, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var pauseButton: some View {
        let paused = appState.isTrackingPaused
        return Button(action: appState.toggleTracking) {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(paused ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(paused ? Color.accentColor : Color.primary.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(paused ? "Resume tracking" : "Pause tracking")
        .accessibilityLabel(paused ? "Resume tracking" : "Pause tracking")
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
        guard let kind, kind != .ignored else { return .secondary }
        return kind.tint
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
