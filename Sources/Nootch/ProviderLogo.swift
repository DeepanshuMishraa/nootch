import AppKit
import SwiftUI

struct ProviderLogo: View {
    let provider: ProviderID
    let size: CGFloat
    var tintColor: Color? = nil

    // NSImage(contentsOf:) hits the disk on every call. Rail items re-render on
    // every hover/animation frame, so load each logo once and reuse it.
    private static let imageCache = NSCache<NSString, NSImage>()

    private static func cachedImage(for provider: ProviderID) -> NSImage? {
        let key = NSString(string: provider.rawValue)
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let resource = provider.logoResource,
              let url = ResourceBundle.url(forResource: resource, withExtension: nil),
              let image = NSImage(contentsOf: url)
        else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    var body: some View {
        Group {
            if let image = Self.cachedImage(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tintColor ?? .white)
            } else {
                Image(systemName: provider.icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tintColor ?? .white)
            }
        }
        .frame(width: size, height: size)
    }
}
