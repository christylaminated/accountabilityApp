import SwiftUI

/// Inline "all done today" surface for the Habits tab. Renders only when
/// the caller decides the day is complete; visibility is reactive (the
/// caller un-renders it when the user unchecks a habit). No scrim, no
/// modal, no auto-dismiss. The body text matches the habit list's
/// `.body` weight so it feels like part of the list; the streak row is
/// the only "loud" element by design — that's the moment.
struct HabitCelebrationView: View {
    let streakCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("all done today.")
                Text("see you tomorrow.")
            }
            .font(.body.weight(.medium))
            .foregroundStyle(Color.tallyTextPrimary)

            // Flame + count. Number is bolder than the flame so it reads as
            // the focal point (visual hierarchy: streak first, decoration
            // second). Both accent so they share the same emotional weight.
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .medium))
                Text("\(streakCount)")
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.tallyAccent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Faintest possible tint — feels like part of the list rather
            // than a card on top of it. 6% opacity reads as a whisper on
            // every theme.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.tallyAccent.opacity(0.06))
        )
    }
}
