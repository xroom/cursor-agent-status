import SwiftUI

enum TrafficLightState {
    case idle
    case running
    case pending
    case recent

    init(category: TaskCategory) {
        switch category {
        case .running: self = .running
        case .pending: self = .pending
        case .recent: self = .recent
        }
    }
}

struct TrafficLightView: View {
    let active: TrafficLightState
    var runningCount: Int = 0
    var pendingCount: Int = 0
    var recentCount: Int = 0
    var showLabels: Bool = false
    var showsBackground: Bool = true
    var dotSize: CGFloat = 10

    var body: some View {
        HStack(spacing: showLabels ? 14 : (showsBackground ? 7 : 4)) {
            lightColumn(
                color: TrafficLightColors.red,
                label: "待确认",
                isOn: active == .pending,
                count: pendingCount
            )
            lightColumn(
                color: TrafficLightColors.yellow,
                label: "进行中",
                isOn: active == .running,
                count: runningCount
            )
            lightColumn(
                color: TrafficLightColors.green,
                label: "完成",
                isOn: active == .recent,
                count: recentCount
            )
        }
        .padding(.horizontal, showLabels ? 10 : (showsBackground ? 8 : 0))
        .padding(.vertical, showLabels ? 8 : (showsBackground ? 5 : 0))
        .background {
            if showsBackground {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
        }
    }

    private func lightColumn(color: Color, label: String, isOn: Bool, count: Int) -> some View {
        VStack(spacing: 4) {
            trafficLightDot(color: color, isOn: isOn, hasActivity: count > 0)

            if showLabels {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isOn ? color : .secondary)

                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trafficLightDot(color: Color, isOn: Bool, hasActivity: Bool) -> some View {
        Circle()
            .fill(dotFill(color: color, isOn: isOn, hasActivity: hasActivity))
            .frame(width: dotSize, height: dotSize)
            .overlay {
                Circle()
                    .strokeBorder(color.opacity(isOn ? 0.9 : 0.25), lineWidth: 0.5)
            }
            .shadow(color: isOn ? color.opacity(0.75) : .clear, radius: isOn ? 5 : 0)
    }

    private func dotFill(color: Color, isOn: Bool, hasActivity: Bool) -> Color {
        if isOn { return color }
        if hasActivity { return color.opacity(showsBackground ? 0.45 : 0.65) }
        return color.opacity(showsBackground ? 0.18 : 0.32)
    }
}

enum TrafficLightColors {
    static let red = Color(red: 1.0, green: 0.37, blue: 0.34)
    static let yellow = Color(red: 1.0, green: 0.74, blue: 0.18)
    static let green = Color(red: 0.38, green: 0.84, blue: 0.44)

    static func accent(for category: TaskCategory) -> Color {
        switch category {
        case .running: return yellow
        case .pending: return red
        case .recent: return green
        }
    }
}

extension StatusStore {
    var trafficLightState: TrafficLightState {
        if let status = latestCombinedStatus {
            return TrafficLightState(category: status.category)
        }
        if pendingCount > 0 { return .pending }
        if activeCount > 0 { return .running }
        if recentCount > 0 { return .recent }
        return .idle
    }
}
