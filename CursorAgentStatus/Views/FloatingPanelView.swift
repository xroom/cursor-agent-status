import SwiftUI

struct FloatingPanelView: View {
    @Bindable var store: StatusStore

    private var statusCode: ProStatusCode {
        ProStatusCode(trafficLight: store.trafficLightState)
    }

    var body: some View {
        HStack(spacing: 8) {
            ProStatusTag(code: statusCode)

            Text(timestampText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()

            Text(store.proSummaryLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if store.canStopAgent {
                stopButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(
            minWidth: FloatingPanelLayout.minWidth,
            maxWidth: FloatingPanelLayout.maxWidth,
            alignment: .leading
        )
        .fixedSize(horizontal: true, vertical: false)
        .background { ProCardBackground(cornerRadius: 8) }
    }

    private var timestampText: String {
        if let item = store.latestTaskItem {
            return item.relativeTime
        }
        return "—"
    }

    private var stopButton: some View {
        Button(action: { store.stopActiveAgent() }) {
            Image(systemName: "stop.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.red.opacity(0.88))
                )
        }
        .buttonStyle(.plain)
        .help("停止 Agent (⌘⇧⌫)")
    }
}
