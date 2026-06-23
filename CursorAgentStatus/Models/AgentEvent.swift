import Foundation

struct AgentEvent: Codable, Identifiable, Sendable {
    var id: String { "\(ts)-\(event)-\(conversationId ?? "none")-\(toolUseId ?? subagentId ?? UUID().uuidString)" }

    let ts: Int64
    let event: String
    let conversationId: String?
    let generationId: String?
    let toolUseId: String?
    let toolName: String?
    let subagentId: String?
    let subagentType: String?
    let title: String?
    let workspace: String?
    let transcriptPath: String?
    let status: String?
    let failureType: String?
    let command: String?
    let durationMs: Int?
    let isBackgroundAgent: Bool?
    let composerMode: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case ts, event, title, workspace, status, summary, command
        case conversationId = "conversation_id"
        case generationId = "generation_id"
        case toolUseId = "tool_use_id"
        case toolName = "tool_name"
        case subagentId = "subagent_id"
        case subagentType = "subagent_type"
        case transcriptPath = "transcript_path"
        case failureType = "failure_type"
        case durationMs = "duration_ms"
        case isBackgroundAgent = "is_background_agent"
        case composerMode = "composer_mode"
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
    }
}
