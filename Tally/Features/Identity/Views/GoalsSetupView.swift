import SwiftUI

/// Third step of onboarding: weekly goals.
/// Same UX pattern as HabitsSetupView. Empty fields are skipped on submit.
struct GoalsSetupView: View {
    let onContinue: ([String]) async -> Void

    @State private var titles: [String] = ["", ""]
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
            Text("What are you working toward?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Bigger things — the goals that hang around until you finish them. Add a few; you can set deadlines later.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }

    private var cards: some View {
        VStack(spacing: 10) {
            ForEach(titles.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Image(systemName: "flag")
                        .foregroundStyle(Color.tallyAccent.opacity(0.6))
                        .font(.title3)
                    TextField(placeholder(for: i), text: $titles[i], axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focusedIndex, equals: i)
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
            Label("Add another goal", systemImage: "plus")
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
                Text(nonEmpty.isEmpty ? "Skip for now" : "Done")
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
        let examples = ["Finish reading 'Atomic Habits'", "Call Mom", "Plan weekend hike", "Sign up for the 10k"]
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
        }
    }
}
