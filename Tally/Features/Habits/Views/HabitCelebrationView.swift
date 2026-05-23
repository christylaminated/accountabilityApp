import SwiftUI

struct HabitCelebrationView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .light))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                Text("All done today!")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(tallyAccent.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}
