import AppKit
import SwiftUI
import HagoCore

enum HagoPalette {
    /// The blue of the app icon.
    static let work = Color(light: 0x2B7BF3, dark: 0x4A93FF)
    static let personal = Color(light: 0x12A37E, dark: 0x3CD3A3)
    static let review = Color(light: 0xE58A0B, dark: 0xFFB43F)
    static let track = Color.primary.opacity(0.07)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

extension Font {
    static func hagoNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

extension ActivityKind {
    var tint: Color {
        switch self {
        case .work: HagoPalette.work
        case .personal: HagoPalette.personal
        case .review: HagoPalette.review
        case .ignored: .gray
        }
    }

    var symbolName: String {
        switch self {
        case .work: "briefcase"
        case .personal: "person"
        case .review: "questionmark.circle"
        case .ignored: "eye.slash"
        }
    }
}

enum HagoDuration {
    static func text(_ duration: TimeInterval) -> String {
        duration < 60 ? "<1m" : TimeFormatting().compactDuration(duration)
    }
}

struct PageTop<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .accessibilityLabel("Clear Search")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct FilterMenu<Content: View>: View {
    let activeCount: Int
    let clear: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
            if activeCount > 0 {
                Divider()
                Button("Clear Filters", action: clear)
            }
        } label: {
            Label(
                activeCount == 0 ? "Filter" : "Filter (\(activeCount))",
                systemImage: activeCount == 0
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .fixedSize()
    }
}

struct PeriodNavigator: View {
    let currentTitle: String
    let isCurrent: Bool
    let canGoForward: Bool
    let step: (Int) -> Void
    let reset: () -> Void

    var body: some View {
        ControlGroup {
            Button {
                step(-1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .help("Previous")
            Button(currentTitle, action: reset)
                .disabled(isCurrent)
            Button {
                step(1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .help("Next")
            .disabled(!canGoForward)
        }
        .fixedSize()
    }
}

struct ActivityKindBadge: View {
    let kind: ActivityKind

    var body: some View {
        Text(kind.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(kind.tint)
            .background(kind.tint.opacity(0.15), in: Capsule())
    }
}

struct ProjectLabel: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct KindFilterChip: View {
    let title: String
    let duration: TimeInterval
    let tint: Color
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                Text(HagoDuration.text(duration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? AnyShapeStyle(tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isSelected ? tint.opacity(0.5) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ClassifyButtons: View {
    let currentKind: ActivityKind
    let classify: (ActivityKind) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if currentKind != .work {
                Button("Work") { classify(.work) }
                    .help("Mark as Work")
            }
            if currentKind != .personal {
                Button("Personal") { classify(.personal) }
                    .help("Mark as Personal")
            }
            Button(role: .destructive) {
                classify(.ignored)
            } label: {
                Image(systemName: "eye.slash")
                    .accessibilityLabel("Ignore")
            }
            .help("Delete these recordings so they never count")
        }
    }
}

struct CorrectionBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let correction = appState.correction {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(correction.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if correction.canUndo, appState.latestCorrectionActionID != nil {
                    Button("Undo") { appState.undoLatestCorrection() }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct HagoCard: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct StatCard: View {
    var title: String
    var value: String
    var detail: String?
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.hagoNumber(28))
                .foregroundStyle(color == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(color))
            if let detail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HagoCard())
    }
}

/// A thin capsule filled to `fraction`, used to compare durations at a glance.
struct ShareBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(HagoPalette.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(height, geometry.size.width * min(max(fraction, 0), 1)))
                        .opacity(fraction > 0 ? 1 : 0)
                }
        }
        .frame(height: height)
    }
}

extension View {
    func hagoCard(padding: CGFloat = 18) -> some View {
        modifier(HagoCard(padding: padding))
    }

    func hagoRowBackground(isSelected: Bool, isHovered: Bool = false) -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.13)
                      : isHovered ? Color.primary.opacity(0.04) : Color.clear)
                .padding(.horizontal, 8)
        )
        .listRowSeparator(.hidden)
    }
}
