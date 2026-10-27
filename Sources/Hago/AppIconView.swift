import AppKit
import HagoCore
import SwiftUI

struct AppIconView: View {
    let bundleIdentifier: String
    let host: String?
    let size: CGFloat
    let placeholderSymbol: String
    let downloadsIcon: Bool
    @State private var favicon: NSImage?

    /// With a host, shows the site's own icon once downloaded, and a monogram until then or when there is none.
    /// `downloadsIcon: false` shows only an icon already saved, for sites the user asked never to record.
    init(bundleIdentifier: String, host: String? = nil, size: CGFloat = 28, placeholderSymbol: String = "app.dashed", downloadsIcon: Bool = true) {
        self.downloadsIcon = downloadsIcon
        self.bundleIdentifier = bundleIdentifier
        self.host = host
        self.size = size
        self.placeholderSymbol = placeholderSymbol
    }

    /// Matches the rounded square of a macOS app icon, which fills about 80% of its frame.
    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
    }

    var body: some View {
        Group {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.6, height: size * 0.6)
                    .frame(width: size * 0.8, height: size * 0.8)
                    .background(.white, in: tile)
                    .overlay(tile.strokeBorder(.black.opacity(0.08)))
                    .frame(width: size, height: size)
            } else if let host, !host.isEmpty {
                SiteMonogram(host: host, size: size * 0.8)
                    .frame(width: size, height: size)
            } else if let app = DetectedWorkApp.application(withID: bundleIdentifier) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.tertiary)
                    .frame(width: size, height: size)
            }
        }
        .task(id: host) {
            favicon = nil
            guard let host, !host.isEmpty else { return }
            favicon = await SiteIcons.shared.icon(for: host, downloading: downloadsIcon).flatMap(NSImage.init(data:))
        }
    }
}

private struct SiteMonogram: View {
    let host: String
    let size: CGFloat

    private static let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .green, .teal, .cyan, .brown]

    private var name: Substring {
        var labels = host.lowercased().split(separator: ".")
        if labels.first == "www" { labels.removeFirst() }
        guard labels.count > 1 else { return labels.first ?? "" }
        let secondLevel: Set<Substring> = ["co", "com", "org", "net", "ac", "gov", "edu"]
        if labels.count > 2, secondLevel.contains(labels[labels.count - 2]) {
            return labels[labels.count - 3]
        }
        return labels[labels.count - 2]
    }

    private var isAddress: Bool {
        host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
    }

    private var color: Color {
        // String.hashValue changes between launches; a site should keep its colour.
        let hash = name.utf8.reduce(UInt32(5381)) { $0 &* 33 &+ UInt32($1) }
        return Self.palette[Int(hash % UInt32(Self.palette.count))]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(color.gradient)
            .overlay {
                if isAddress {
                    Image(systemName: "network")
                        .font(.system(size: size * 0.5, weight: .semibold))
                } else {
                    Text(name.prefix(1).uppercased())
                        .font(.system(size: size * 0.56, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
