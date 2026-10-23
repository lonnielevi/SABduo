import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSent: Bool
    let send: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.body.weight(.medium))
                    .lineLimit(3)
                HStack(spacing: 6) {
                    if result.size > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: result.size, countStyle: .file))
                    }
                    if let published = result.published {
                        Text("·")
                        Text(published, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    }
                    if let grabs = result.grabs {
                        Text("·")
                        Label("\(grabs)", systemImage: "arrow.down.to.line")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if !result.category.isEmpty {
                    Text(result.category)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(isSent ? "Sent" : "Send to SABnzbd", systemImage: isSent ? "checkmark.circle.fill" : "arrow.down.circle", action: send)
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(isSent ? .green : .accentColor)
                .buttonStyle(.borderless)
                .disabled(isSent)
        }
        .padding(.vertical, 2)
    }
}
