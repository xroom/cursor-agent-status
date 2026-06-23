import Foundation

struct AgentStatusSnapshot: Codable, Sendable {
    let updatedAt: Int64
    let lastEvent: String?
    let running: [TaskItem]
    let pending: [TaskItem]
    let recent: [TaskItem]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case lastEvent = "last_event"
        case running, pending, recent
    }

    static let empty = AgentStatusSnapshot(
        updatedAt: 0,
        lastEvent: nil,
        running: [],
        pending: [],
        recent: []
    )
}
