import Foundation

enum TaskCategory: String, Codable, Sendable {
    case running
    case pending
    case recent
}

enum TaskKind: String, Codable, Sendable {
    case session
    case processing
    case tool
    case subagent
    case shell
    case mcp
    case response
    case stop
    case thinking
}

struct TaskItem: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let category: TaskCategory
    let kind: TaskKind
    let title: String
    let subtitle: String?
    let conversationId: String?
    let workspace: String?
    let transcriptPath: String?
    let startedAt: Date
    var updatedAt: Date
    var expiresAt: Date?

    var workspaceName: String {
        guard let workspace else { return "未知工作区" }
        return (workspace as NSString).lastPathComponent
    }

    var relativeTime: String {
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 5 { return "刚刚" }
        if interval < 60 { return "\(Int(interval)) 秒前" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        return "\(Int(interval / 3600)) 小时前"
    }
}
