import SwiftUI

struct AvatarView: View {
    let emoji: String
    var size: CGFloat = 40

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Color.tallyAccent.opacity(0.15))
            .clipShape(Circle())
    }
}
