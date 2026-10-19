import AppKit
import SwiftUI
import HagoCore

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var openSettings: () -> Void = {}

    private let formatter = TimeFormatting()
    private let contentWidth: CGFloat = 284

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metrics
            currentActivity

            if appState.reviewAISettings.scheduleEnabled,
               appState.reviewAIScheduleState.consecutiveFailures >= 3 {
                Label("Scheduled Review needs attention. Check AI Harness settings.", systemImage: "exclamationmark.triangle.fill")
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
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
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
