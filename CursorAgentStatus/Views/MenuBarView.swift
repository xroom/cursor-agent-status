import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var store: StatusStore
    @Binding var isFloatingPanelVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 8) {
                statChip(title: "进行中", count: store.activeCount, color: .blue)
                statChip(title: "待确认", count: store.pendingCount, color: .orange)
                statChip(title: "刚完成", count: store.recentCount, color: .green)
            }

            Divider()

            TaskSectionView(
                title: "进行中",
                count: store.activeCount,
                items: store.running,
                accent: .blue,
                limit: 5,
                onSelect: { store.openTranscript(for: $0) }
            )

            TaskSectionView(
                title: "待确认",
                count: store.pendingCount,
                items: store.pending,
                accent: .orange,
                limit: 5,
                onSelect: { store.openTranscript(for: $0) }
            )

            TaskSectionView(
                title: "刚完成",
                count: store.recentCount,
                items: store.recent,
                accent: .green,
                limit: 5,
                onSelect: { store.openTranscript(for: $0) }
            )

            Text("Smart Mode 内置审批不一定能被 Hook 捕获")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            HStack {
                Button("打开 Cursor") { store.openCursor() }
                Button(isFloatingPanelVisible ? "隐藏悬浮窗" : "显示悬浮窗") {
                    isFloatingPanelVisible.toggle()
                }
                Button("重置状态") { store.resetActiveState() }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Image(systemName: store.statusIconName)
                .font(.title3)
                .foregroundStyle(store.pendingCount > 0 ? .orange : (store.activeCount > 0 ? .blue : .secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor Agent 状态")
                    .font(.headline)
                Text(store.activeCount > 0 ? "AI 正在工作" : "当前空闲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func statChip(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }
}
