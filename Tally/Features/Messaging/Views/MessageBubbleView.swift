import SwiftUI

struct MessageBubbleView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    let text: String
    let timestamp: Date
    let isMe: Bool
    let senderSymbol: String
    /// The sender's uploaded photo, when we have it (friends only). Nil falls
    /// back to the SF symbol inside AvatarView.
    var senderImageData: Data? = nil
    let senderName: String
    let showSender: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if !isMe {
                AvatarView(
                    symbolName: senderSymbol,
                    imageData: senderImageData,
                    size: 28
                )
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                if showSender {
                    Text(senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? tallyAccent : Color.tallyCard)
                    // `tallyOnAccent` (not literal .white) so the text
                    // contrasts with the bubble in both light AND dark mode
                    // — Classic's accent flips to near-white in dark mode,
                    // which made white-on-white invisible.
                    .foregroundStyle(isMe ? Color.tallyOnAccent : Color.tallyTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        .padding(.leading, isMe ? 40 : 0)
        .padding(.trailing, isMe ? 0 : 40)
    }
}
