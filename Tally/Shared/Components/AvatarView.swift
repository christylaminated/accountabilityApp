import SwiftUI

/// Circular avatar tile. Renders an SF Symbol (Lucide-style line icon) on the
/// accent-tinted background. The symbol name comes from the user's profile.
struct AvatarView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    let symbolName: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .medium))
            .frame(width: size, height: size)
            .foregroundStyle(tallyAccent)
            .background(tallyAccent.opacity(0.15))
            .clipShape(Circle())
    }
}
