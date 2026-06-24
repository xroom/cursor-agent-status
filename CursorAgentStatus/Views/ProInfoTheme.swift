import SwiftUI

enum ProStatusCode: String {
    case idle = "IDLE"
    case run = "RUN"
    case pnd = "PND"
    case done = "DONE"

    init(trafficLight state: TrafficLightState) {
        switch state {
        case .idle: self = .idle
        case .running: self = .run
        case .pending: self = .pnd
        case .recent: self = .done
        }
    }

    init(category: TaskCategory) {
        switch category {
        case .running: self = .run
        case .pending: self = .pnd
        case .recent: self = .done
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .secondary
        case .run: return Color(red: 0.20, green: 0.45, blue: 0.95)
        case .pnd: return Color(red: 0.90, green: 0.45, blue: 0.12)
        case .done: return Color(red: 0.18, green: 0.62, blue: 0.36)
        }
    }
}

struct ProStatusTag: View {
    let code: ProStatusCode

    var body: some View {
        Text(code.rawValue)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(code.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(code.tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(code.tint.opacity(0.25), lineWidth: 0.5)
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct ProCardBackground: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

struct ProMetricsRow: View {
    let running: Int
    let pending: Int
    let recent: Int

    var body: some View {
        HStack(spacing: 0) {
            metricCell(code: .run, value: running)
            divider
            metricCell(code: .pnd, value: pending)
            divider
            metricCell(code: .done, value: recent)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private func metricCell(code: ProStatusCode, value: Int) -> some View {
        VStack(spacing: 3) {
            Text(code.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(code.tint)
        }
        .frame(maxWidth: .infinity)
    }
}

enum FloatingPanelLayout {
    static let maxWidth: CGFloat = 400
}

extension StatusStore {
    var menuBarLabel: String {
        if pendingCount > 0 { return "Agent !\(min(pendingCount, 99))" }
        if activeCount > 0 { return "Agent · \(min(activeCount, 99))" }
        return "Agent"
    }

    var proSummaryLine: String {
        if let status = latestCombinedStatus {
            return status.text
        }
        return "No active tasks"
    }
}
