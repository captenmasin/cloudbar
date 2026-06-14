import AppKit
import SwiftUI

enum CloudBarAppIcon {
    static var image: NSImage? {
        if let url = CloudBarResources.bundle.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return nil
    }

    @MainActor
    static func applyApplicationIcon() {
        guard let image else {
            return
        }

        NSApp.applicationIconImage = image
    }
}

struct CloudBarLogo: View {
    var size: CGFloat = 72

    var body: some View {
        LaravelCloudLogo(size: size)
    }
}
