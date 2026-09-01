import AppKit
import SwiftUI

struct ProviderLogo: View {
    let provider: ProviderID
    let size: CGFloat
    var tintColor: Color? = nil

    var body: some View {
        Group {
            if let resource = provider.logoResource,
               let url = Bundle.module.url(forResource: resource, withExtension: nil),
               let image = NSImage(contentsOf: url)
            {
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
