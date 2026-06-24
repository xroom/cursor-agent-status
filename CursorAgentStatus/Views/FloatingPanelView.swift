import SwiftUI

struct FloatingPanelView: View {
    @Bindable var store: StatusStore
    let conversationId: String?

    private var content: AgentFloatingContent {
        if let conversationId {
            return store.floatingContent(for: conversationId)
        }
        return store.floatingIdleContent()
    }

    private var statusCode: ProStatusCode {
        content.statusCode
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ProStatusTag(code: statusCode)
                .layoutPriority(2)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.agentName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(content.statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if content.canStop {
                stopButton
                    .layoutPriority(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(
            minWidth: FloatingPanelLayout.minWidth,
            maxWidth: FloatingPanelLayout.maxWidth,
            alignment: .leading
        )
        .background { ProCardBackground(cornerRadius: 8) }
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
