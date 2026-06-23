import SwiftUI

struct FloatingPanelView: View {
    @Bindable var store: StatusStore
    @Binding var isAlwaysOnTop: Bool
    @Binding var opacity: Double
    @Binding var autoHideWhenIdle: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: store.statusIconName)
                    .foregroundStyle(store.pendingCount > 0 ? .orange : .blue)
                Text("Cursor Agent 工作状态")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                metricCard("进行中", store.activeCount, .blue)
                metricCard("待确认", store.pendingCount, .orange)
                metricCard("刚完成", store.recentCount, .green)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TaskSectionView(
                        title: "进行中",
                        count: store.activeCount,
                        items: store.running,
                        accent: .blue,
                        limit: nil,
                        onSelect: { store.openTranscript(for: $0) }
                    )

                    TaskSectionView(
                        title: "待确认",
                        count: store.pendingCount,
                        items: store.pending,
                        accent: .orange,
                        limit: nil,
                        onSelect: { store.openTranscript(for: $0) }
                    )

                    TaskSectionView(
                        title: "刚完成",
                        count: store.recentCount,
                        items: store.recent,
                        accent: .green,
                        limit: nil,
                        onSelect: { store.openTranscript(for: $0) }
                    )
                }
            }
            .frame(maxHeight: 420)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("始终置顶", isOn: $isAlwaysOnTop)
                Toggle("空闲时自动隐藏", isOn: $autoHideWhenIdle)
                HStack {
                    Text("透明度")
                    Slider(value: $opacity, in: 0.6...1.0)
                }
                Button("重置状态") { store.resetActiveState() }
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 420)
        .opacity(opacity)
    }

    private func metricCard(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}
