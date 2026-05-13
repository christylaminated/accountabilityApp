import SwiftUI

/// Second step of onboarding: what habits do you want to track?
/// User types into a list of cards; can add more or remove. Empty fields are
/// dropped on submit. "Continue" is always enabled — submitting zero habits is
/// the same as skipping (user can add later from the Habits tab).
struct HabitsSetupView: View {
    /// Invoked when the user taps Continue. Receives the entered titles in order.
    let onContinue: ([String]) async -> Void

    @State private var titles: [String] = ["", "", ""]
    @FocusState private var focusedIndex: Int?
    @State private var isSubmitting = false

    private var nonEmpty: [String] {
        titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                cards
                addButton
                Spacer().frame(height: 8)
                submitButton
                skipLink
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .background(Color.tallyCanvas)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("What do you want to track?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Add a few daily habits to start. You can edit, archive, or add more anytime.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    private var cards: some View {
        VStack(spacing: 10) {
            ForEach(titles.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .foregroundStyle(Color.tallyAccent.opacity(0.6))
                        .font(.title3)
                    TextField(placeholder(for: i), text: $titles[i])
                        .focused($focusedIndex, equals: i)
                        .submitLabel(.next)
                        .onSubmit {
                            if i + 1 < titles.count {
                                focusedIndex = i + 1
                            } else {
                                appendField()
                            }
                        }
                    if titles.count > 1 {
                        Button {
                            removeField(at: i)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var addButton: some View {
        Button {
            appendField()
        } label: {
            Label("Add another habit", systemImage: "plus")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.tallyAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(nonEmpty.isEmpty ? "Skip for now" : "Continue")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(nonEmpty.isEmpty ? Color.tallyCard : Color.tallyAccent)
            .foregroundStyle(nonEmpty.isEmpty ? Color.primary : .white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isSubmitting)
    }

    @ViewBuilder
    private var skipLink: some View {
        if !nonEmpty.isEmpty {
            Button {
                titles = []
                submit()
            } label: {
                Text("Skip for now")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: -

    private func placeholder(for i: Int) -> String {
        let examples = ["Read 30 min", "Drink 2L water", "Morning walk", "Journal", "Meditate 10 min"]
        return examples[i % examples.count]
    }

    private func appendField() {
        titles.append("")
        focusedIndex = titles.count - 1
    }

    private func removeField(at index: Int) {
        guard titles.indices.contains(index) else { return }
        titles.remove(at: index)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        focusedIndex = nil
        let toSave = nonEmpty
        Task {
            await onContinue(toSave)
            // Parent transitions onboarding state; this view goes away.
        }
    }
}
