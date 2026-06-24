import SwiftUI

struct FloatingPanelView: View {
    @Bindable var store: StatusStore
    let conversationId: String?

    @State private var tick = Date()

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

                HStack(spacing: 4) {
                    Text(content.statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if content.showsStepTimer, let start = content.stepStartedAt {
                        Text(StepElapsedFormatter.format(since: start, now: tick))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
                    }
                }
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            tick = date
        }
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

enum StepElapsedFormatter {
    static func format(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)秒" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes < 60 {
            return remainder == 0 ? "\(minutes)分" : "\(minutes)分\(remainder)秒"
        }
        let hours = minutes / 60
        let minutePart = minutes % 60
        return minutePart == 0 ? "\(hours)小时" : "\(hours)小时\(minutePart)分"
    }
}
