import SwiftUI

struct TaskSectionView: View {
    let title: String
    let count: Int
    let items: [TaskItem]
    var code: ProStatusCode = .run
    let limit: Int?
    var onSelect: ((TaskItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ProStatusTag(code: code)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%02d", count))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(code.tint)
            }

            if items.isEmpty {
                Text("—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onSelect?(item)
                        } label: {
                            TaskRowView(item: item, code: code)
                        }
                        .buttonStyle(.plain)

                        if index < displayedItems.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }

    private var displayedItems: [TaskItem] {
        guard let limit else { return items }
        return Array(items.prefix(limit))
    }
}

struct TaskRowView: View {
    let item: TaskItem
    var code: ProStatusCode = .run

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.relativeTime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    Text(item.workspaceName)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
