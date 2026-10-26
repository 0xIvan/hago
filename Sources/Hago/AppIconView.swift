import AppKit
import HagoCore
import SwiftUI

struct AppIconView: View {
    let bundleIdentifier: String
    let host: String?
    let size: CGFloat
    let placeholderSymbol: String
    @State private var favicon: NSImage?

    /// With a host, shows the site's icon from Chrome's local cache and falls back to the app icon.
    init(bundleIdentifier: String, host: String? = nil, size: CGFloat = 28, placeholderSymbol: String = "app.dashed") {
        self.bundleIdentifier = bundleIdentifier
        self.host = host
        self.size = size
        self.placeholderSymbol = placeholderSymbol
    }

    var body: some View {
        Group {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.6, height: size * 0.6)
                    .frame(width: size * 0.86, height: size * 0.86)
                    .background(.white, in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                            .strokeBorder(.black.opacity(0.08))
                    )
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
            favicon = await ChromeFavicons.shared.iconData(for: host).flatMap(NSImage.init(data:))
        }
    }
}
