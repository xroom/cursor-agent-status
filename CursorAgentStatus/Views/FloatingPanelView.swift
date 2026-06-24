import SwiftUI

struct FloatingPanelView: View {
    @Bindable var store: StatusStore

    @State private var rotateIndex = 0

    private let rotateInterval: TimeInterval = 3

    private var statusCode: ProStatusCode {
        if content.isCompleted { return .done }
        return ProStatusCode(trafficLight: store.trafficLightState)
    }

    private var content: FloatingPanelContent {
        store.floatingContent(at: rotateIndex)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ProStatusTag(code: statusCode)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.activityTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.2), value: content.activityTitle)

                HStack(spacing: 4) {
                    Text(content.projectName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if content.runningCount > 1 {
                        Text("· \(rotateIndex + 1)/\(content.runningCount)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
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
        .onChange(of: store.revision) { _, _ in
            clampRotateIndex()
        }
        .onReceive(Timer.publish(every: rotateInterval, on: .main, in: .common).autoconnect()) { _ in
            guard store.floatingRunningTasksOrdered.count > 1 else { return }
            rotateIndex = (rotateIndex + 1) % store.floatingRunningTasksOrdered.count
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

    private func clampRotateIndex() {
        let count = store.floatingRunningTasksOrdered.count
        guard count > 0 else {
            rotateIndex = 0
            return
        }
        rotateIndex = rotateIndex % count
    }
}
