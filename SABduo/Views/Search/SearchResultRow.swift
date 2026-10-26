import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSent: Bool
    let send: () -> Void
    @State private var confirmingResend = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.wrappingTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(3)
                HStack(spacing: 6) {
                    if result.size > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: result.size, countStyle: .file))
                    }
                    if let published = result.published {
                        Text("·")
                        // "Thu, Oct 23, 2026": the weekday too within the past week, when it's the easier clue.
                        Text(published, format: Date.now.timeIntervalSince(published) < 7 * 86_400
                             ? .dateTime.weekday(.abbreviated).month(.abbreviated).day().year()
                             : .dateTime.month(.abbreviated).day().year())
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // A line of its own: beside the size and date, a half-pane is too narrow for it.
                if !result.category.isEmpty {
                    Text(result.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Stays tappable once sent; the green check is easy to hit by accident, so confirm a resend.
            Button(isSent ? "Send Again" : "Send to SABnzbd", systemImage: isSent ? "checkmark.circle.fill" : "arrow.down.circle") {
                if isSent { confirmingResend = true } else { send() }
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(isSent ? .green : .accentColor)
            .buttonStyle(.borderless)
            .accessibilityValue(isSent ? "Sent" : "")
            .confirmationDialog("Already sent to SABnzbd", isPresented: $confirmingResend, titleVisibility: .visible) {
                Button("Send Again", action: send)
            }
        }
        .padding(.vertical, 2)
    }
}
