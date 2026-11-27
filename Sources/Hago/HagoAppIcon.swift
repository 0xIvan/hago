import AppKit
import ImageIO

/// Hago's own icon, decoded once per appearance and size; the bundled PNGs are 1024 pixels.
@MainActor
enum HagoAppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(dark: Bool, pixels: Int) -> NSImage? {
        let resourceName = dark ? "AppIcon-dark" : "AppIcon"
        let key = "\(resourceName)-\(pixels)"
        if let cached = cache[key] { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels
        ]
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache[key] = image
        return image
    }
}
