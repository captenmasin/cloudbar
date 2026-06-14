import AppKit
import SwiftUI

struct LaravelCloudLogo: View {
    var size: CGFloat = 16

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        }
    }

    private static var image: NSImage? {
        if let url = CloudBarResources.bundle.url(forResource: "logo", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }

        return NSImage.cloudBarLogo
    }
}
