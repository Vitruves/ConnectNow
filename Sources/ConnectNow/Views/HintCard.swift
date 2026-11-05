import SwiftUI
import ConnectNowCore

struct HintCard: View {
    let hint: Hint
    let canPerform: Bool
    let perform: (Hint.Action) -> Void

    private var color: Color { hint.severity == .warning ? .orange : .indigo }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: hint.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(color)
                .accessibilityLabel(hint.severity == .warning ? "Warning" : "Information")
            VStack(alignment: .leading, spacing: 3) {
                Text(hint.title).font(.callout.weight(.semibold))
                Text(hint.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let action = hint.action {
                    Button(action.title) { perform(action) }
                        .controlSize(.small)
                        .disabled(!canPerform)
                        .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}
