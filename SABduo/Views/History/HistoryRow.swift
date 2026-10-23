import SwiftUI

struct HistoryRow: View {
    let item: HistorySlot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
            }
            HStack {
                Text(item.isCompleted || item.isFailed ? item.status : item.actionLine.nonEmpty ?? item.status)
                    .foregroundStyle(tint)
                if !item.size.isEmpty {
                    Text("·")
                    Text(item.size)
                }
                Spacer()
                if let completed = item.completed {
                    Text(completed, format: .relative(presentation: .named))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if item.isFailed, !item.failMessage.isEmpty {
                Text(item.failMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        if item.isCompleted { return "checkmark.circle.fill" }
        if item.isFailed { return "xmark.octagon.fill" }
        return "gearshape.2.fill"
    }

    private var tint: Color {
        if item.isCompleted { return .green }
        if item.isFailed { return .red }
        return .blue
    }
}
