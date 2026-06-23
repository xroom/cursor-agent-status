import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var store: StatusStore
    @Binding var isFloatingPanelVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ProMetricsRow(
                running: store.activeCount,
                pending: store.pendingCount,
                recent: store.recentCount
            )

            summaryLine

            Divider()

            TaskSectionView(
                title: "RUN · 进行中",
                count: store.activeCount,
                items: store.running,
                code: .run,
                limit: 5,
                onSelect: { store.openTranscript(for: $0) }
            )

            TaskSectionView(
                title: "PND · 待确认",
                count: store.pendingCount,
                items: store.pending,
                code: .pnd,
                limit: 5,
                onSelect: { store.openTranscript(for: $0) }
            )

            TaskSectionView(
                title: "DONE · 刚完成",
                count: store.recentCount,
                items: store.recent,
                code: .done,
                limit: 5,
                onSelect: { store.openTranscript(for: $0) }
            )

            Text("Hook 无法捕获 Smart Mode 内置审批")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Divider()

            HStack(spacing: 12) {
                Button("Cursor") { store.openCursor() }
                Button(isFloatingPanelVisible ? "隐藏窗" : "悬浮窗") {
                    isFloatingPanelVisible.toggle()
                }
                Button("重置") { store.resetActiveState() }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
            .font(.system(size: 12))
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AGENT STATUS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(headerSubtitle)
                    .font(.system(size: 14, weight: .semibold))
            }
            Spacer()
            ProStatusTag(code: ProStatusCode(trafficLight: store.trafficLightState))
        }
    }

    private var headerSubtitle: String {
        if store.pendingCount > 0 { return "Pending \(store.pendingCount)" }
        if store.activeCount > 0 { return "Running \(store.activeCount)" }
        if store.recentCount > 0 { return "Recently done \(store.recentCount)" }
        return "Idle"
    }

    private var summaryLine: some View {
        Text(store.proSummaryLine)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
    }
}
