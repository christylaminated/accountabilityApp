import SwiftUI

struct CheckboxButton: View {
    let isChecked: Bool
    let isEditable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard isEditable else { return }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        }) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isChecked ? Color.tallyAccent : .secondary)
                .symbolEffect(.bounce, value: isChecked)
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }
}
