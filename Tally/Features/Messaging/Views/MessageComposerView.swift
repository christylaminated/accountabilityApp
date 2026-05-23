import SwiftUI

struct MessageComposerView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Binding var text: String
    let onSend: () -> Void

    private var disabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(disabled ? Color.gray.opacity(0.3) : tallyAccent)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .disabled(disabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tallyCanvas)
    }
}
