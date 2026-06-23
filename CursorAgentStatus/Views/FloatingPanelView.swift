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
}
