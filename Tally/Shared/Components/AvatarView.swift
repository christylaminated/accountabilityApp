import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Circular avatar tile. Renders the user's uploaded photo (`imageData`)
/// when present; otherwise falls back to the SF Symbol on the accent-tinted
/// background. Existing callers can pass just `symbolName` — `imageData`
/// defaults to nil so they keep the symbol look until they're updated to
/// pass through the friend/user's photo data.
struct AvatarView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    let symbolName: String
    var imageData: Data? = nil
    var size: CGFloat = 40

    var body: some View {
        if let imageData, let uiImage = decode(imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.45, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(tallyAccent)
                .background(tallyAccent.opacity(0.15))
                .clipShape(Circle())
        }
    }

    private func decode(_ data: Data) -> UIImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #else
        return nil
        #endif
    }
}
