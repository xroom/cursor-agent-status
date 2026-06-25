import SwiftUI

struct FloatingPanelView: View {
    @Bindable var store: StatusStore
    let conversationId: String?
    var stackCount: Int = 1
    var isStackCollapsed: Bool = false
    var isStackExpanded: Bool = false
    var showsStackBadge: Bool = false
    var onExpandStack: (() -> Void)? = nil
    var onSelectSession: (() -> Void)? = nil

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
        ZStack(alignment: .topTrailing) {
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
                .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .padding(.top, conversationId == nil ? 0 : 4)
            .padding(.trailing, conversationId == nil ? 0 : 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if isStackCollapsed {
                    onExpandStack?()
                } else if isStackExpanded {
                    onSelectSession?()
                }
            }

            if let conversationId {
                closeButton(conversationId: conversationId)
                    .padding(.top, 2)
                    .padding(.trailing, 2)
            }

            if showsStackBadge {
                stackCountBadge
            }
        }
        .frame(maxWidth: FloatingPanelLayout.maxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background { ProCardBackground(cornerRadius: 8) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            tick = date
        }
    }

    private func closeButton(conversationId: String) -> some View {
        Button {
            store.dismissFloatingHUD(for: conversationId)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help("关闭悬浮窗")
    }

    private var stackCountBadge: some View {
        Text("\(stackCount)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
            .padding(.leading, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .onTapGesture {
                onExpandStack?()
            }
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
