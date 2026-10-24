import SwiftUI

struct AppIconView: View {
    let bundleIdentifier: String
    var size: CGFloat = 28

    var body: some View {
        if let app = DetectedWorkApp.application(withID: bundleIdentifier) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.7))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
        }
    }
}
