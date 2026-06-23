import SwiftUI

struct TaskSectionView: View {
    let title: String
    let count: Int
    let items: [TaskItem]
    let accent: Color
    let limit: Int?
    var onSelect: ((TaskItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            } else {
                ForEach(displayedItems) { item in
                    Button {
                        onSelect?(item)
                    } label: {
                        TaskRowView(item: item, accent: accent)
                    }
                    .buttonStyle(.plain)
                }
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
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    Text(item.workspaceName)
                    Text(item.relativeTime)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
