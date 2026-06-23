import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class StatusStore {
    static let statusDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/agent-status", isDirectory: true)
    static let eventsFile = statusDirectory.appendingPathComponent("events.jsonl")
    static let snapshotFile = statusDirectory.appendingPathComponent("state.json")

    private(set) var running: [TaskItem] = []
    private(set) var pending: [TaskItem] = []
    private(set) var recent: [TaskItem] = []

    var recentTTL: TimeInterval = 60
    var awaitingInputDelay: TimeInterval = 3
    /// 工具/subagent 超过此时间无更新则视为已结束（Cursor 异常退出时不会发 postToolUse）
    var staleToolTTL: TimeInterval = 90
    /// 会话超过此时间无任何事件则视为已结束
    var staleSessionTTL: TimeInterval = 180
    /// Shell/MCP 待批准超过此时间则清除
    var stalePendingTTL: TimeInterval = 60

    private var sessions: [String: TaskItem] = [:]
    private var tools: [String: TaskItem] = [:]
    private var subagents: [String: TaskItem] = [:]
    private var pendingShellMCP: [String: TaskItem] = [:]
    private var lastResponseAt: [String: Date] = [:]
    private var lastActivityAt: [String: Date] = [:]
    private var pruneTimer: Timer?

    var activeCount: Int {
        running.count
    }

    var pendingCount: Int {
        pending.count
    }

    var recentCount: Int {
        recent.count
    }

    var statusIconName: String {
        if pendingCount > 0 { return "hand.raised.fill" }
        if activeCount > 0 { return "arrow.triangle.2.circlepath" }
        return "sparkles"
    }

    init() {
        loadSnapshotIfPresent()
        startPruneTimer()
    }

    func bootstrap(from tailer: EventTailer) {
        for event in tailer.replayAllEvents() {
            apply(event)
        }
        pruneStaleRunning(now: Date())
        refreshPublishedLists()
    }

    func handle(_ event: AgentEvent) {
        apply(event)
        refreshPublishedLists()
    }

    /// 手动清除所有进行中和待确认状态（用于 Cursor 重启后残留）
    func resetActiveState() {
        sessions.removeAll()
        tools.removeAll()
        subagents.removeAll()
        pendingShellMCP.removeAll()
        lastResponseAt.removeAll()
        lastActivityAt.removeAll()
        refreshPublishedLists()
    }

    private func apply(_ event: AgentEvent) {
        let conversationId = event.conversationId ?? "unknown"
        let now = event.date
        lastActivityAt[conversationId] = now

        switch event.event {
        case "sessionStart":
            let item = TaskItem(
                id: "session-\(conversationId)",
                category: .running,
                kind: .session,
                title: sessionTitle(for: event),
                subtitle: event.workspace,
                conversationId: event.conversationId,
                workspace: event.workspace,
                transcriptPath: event.transcriptPath,
                startedAt: now,
                updatedAt: now,
                expiresAt: nil
            )
            sessions[conversationId] = item
            lastResponseAt.removeValue(forKey: conversationId)

        case "sessionEnd":
            if let session = sessions.removeValue(forKey: conversationId) {
                if event.status == "completed" || event.status == nil {
                    addRecent(from: session, title: "会话已结束", at: now)
                }
            }
            clearPending(for: conversationId)
            lastResponseAt.removeValue(forKey: conversationId)
            tools = tools.filter { $0.value.conversationId != conversationId }
            subagents = subagents.filter { $0.value.conversationId != conversationId }

        case "preToolUse":
            guard let toolUseId = event.toolUseId else { break }
            let item = TaskItem(
                id: "tool-\(toolUseId)",
                category: .running,
                kind: .tool,
                title: event.title ?? event.toolName ?? "工具执行",
                subtitle: event.toolName,
                conversationId: event.conversationId,
                workspace: event.workspace,
                transcriptPath: event.transcriptPath,
                startedAt: now,
                updatedAt: now,
                expiresAt: nil
            )
            tools[toolUseId] = item
            lastResponseAt.removeValue(forKey: conversationId)
            removeAwaitingInput(for: conversationId)

        case "postToolUse", "postToolUseFailure":
            if let toolUseId = event.toolUseId {
                tools.removeValue(forKey: toolUseId)
            }
            if event.event == "postToolUseFailure", event.failureType == "permission_denied" {
                let item = TaskItem(
                    id: "denied-\(event.toolUseId ?? UUID().uuidString)",
                    category: .pending,
                    kind: .tool,
                    title: event.title ?? "操作被拒绝",
                    subtitle: "需要重新确认",
                    conversationId: event.conversationId,
                    workspace: event.workspace,
                    transcriptPath: event.transcriptPath,
                    startedAt: now,
                    updatedAt: now,
                    expiresAt: now.addingTimeInterval(recentTTL)
                )
                pendingShellMCP[item.id] = item
            }

        case "subagentStart":
            let key = event.subagentId ?? event.toolUseId ?? UUID().uuidString
            let item = TaskItem(
                id: "subagent-\(key)",
                category: .running,
                kind: .subagent,
                title: event.title ?? "Subagent",
                subtitle: event.subagentType,
                conversationId: event.conversationId,
                workspace: event.workspace,
                transcriptPath: event.transcriptPath,
                startedAt: now,
                updatedAt: now,
                expiresAt: nil
            )
            subagents[key] = item

        case "subagentStop":
            let key = event.subagentId ?? event.toolUseId ?? ""
            if let item = subagents.removeValue(forKey: key) {
                let title = event.summary ?? event.title ?? item.title
                addRecent(from: item, title: "Subagent: \(title)", at: now, status: event.status)
            } else if let title = event.title ?? event.summary {
                addRecent(
                    TaskItem(
                        id: "subagent-done-\(UUID().uuidString)",
                        category: .recent,
                        kind: .subagent,
                        title: title,
                        subtitle: event.subagentType,
                        conversationId: event.conversationId,
                        workspace: event.workspace,
                        transcriptPath: event.transcriptPath,
                        startedAt: now,
                        updatedAt: now,
                        expiresAt: now.addingTimeInterval(recentTTL)
                    )
                )
            }

        case "beforeShellExecution":
            let key = "shell-\(conversationId)-\(event.command ?? event.title ?? UUID().uuidString)"
            let item = TaskItem(
                id: key,
                category: .pending,
                kind: .shell,
                title: event.command ?? event.title ?? "Shell 命令",
                subtitle: "等待执行批准",
                conversationId: event.conversationId,
                workspace: event.workspace,
                transcriptPath: event.transcriptPath,
                startedAt: now,
                updatedAt: now,
                expiresAt: nil
            )
            pendingShellMCP[key] = item

        case "afterShellExecution":
            clearPendingShell(for: conversationId, prefix: "shell-")

        case "beforeMCPExecution":
            let key = "mcp-\(conversationId)-\(event.toolName ?? event.title ?? UUID().uuidString)"
            let item = TaskItem(
                id: key,
                category: .pending,
                kind: .mcp,
                title: event.toolName ?? event.title ?? "MCP 工具",
                subtitle: "等待执行批准",
                conversationId: event.conversationId,
                workspace: event.workspace,
                transcriptPath: event.transcriptPath,
                startedAt: now,
                updatedAt: now,
                expiresAt: nil
            )
            pendingShellMCP[key] = item

        case "afterMCPExecution":
            clearPendingShell(for: conversationId, prefix: "mcp-")

        case "afterAgentResponse":
            lastResponseAt[conversationId] = now
            // 一轮工具调用结束，清除可能未收到 postToolUse 的残留
            clearRunningTools(for: conversationId)
            clearRunningSubagents(for: conversationId)
            addRecent(
                TaskItem(
                    id: "response-\(conversationId)-\(Int(now.timeIntervalSince1970))",
                    category: .recent,
                    kind: .response,
                    title: truncated(event.title ?? "Agent 已回复"),
                    subtitle: "等待你的下一步",
                    conversationId: event.conversationId,
                    workspace: event.workspace,
                    transcriptPath: event.transcriptPath,
                    startedAt: now,
                    updatedAt: now,
                    expiresAt: now.addingTimeInterval(recentTTL)
                )
            )

        case "stop":
            clearRunningTools(for: conversationId)
            clearRunningSubagents(for: conversationId)
            clearPending(for: conversationId)
            removeAwaitingInput(for: conversationId)
            if event.status == "completed" || event.status == "aborted" {
                sessions.removeValue(forKey: conversationId)
            }
            if event.status == "completed" {
                addRecent(
                    TaskItem(
                        id: "stop-\(conversationId)-\(Int(now.timeIntervalSince1970))",
                        category: .recent,
                        kind: .stop,
                        title: "Agent 任务完成",
                        subtitle: event.workspace,
                        conversationId: event.conversationId,
                        workspace: event.workspace,
                        transcriptPath: event.transcriptPath,
                        startedAt: now,
                        updatedAt: now,
                        expiresAt: now.addingTimeInterval(recentTTL)
                    )
                )
            }

        default:
            break
        }
    }

    private func refreshPublishedLists() {
        pruneExpired()
        pruneStaleRunning(now: Date())
        promoteAwaitingInput()

        running = (Array(sessions.values) + Array(tools.values) + Array(subagents.values))
            .sorted { $0.updatedAt > $1.updatedAt }

        pending = Array(pendingShellMCP.values)
            .sorted { $0.updatedAt > $1.updatedAt }

        recent = recent
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func promoteAwaitingInput() {
        let now = Date()
        for (conversationId, respondedAt) in lastResponseAt {
            guard now.timeIntervalSince(respondedAt) >= awaitingInputDelay else { continue }
            let hasActiveTool = tools.values.contains { $0.conversationId == conversationId }
            let hasActiveSubagent = subagents.values.contains { $0.conversationId == conversationId }
            guard !hasActiveTool, !hasActiveSubagent else { continue }

            let key = "await-\(conversationId)"
            if pendingShellMCP[key] != nil { continue }

            let session = sessions[conversationId]
            pendingShellMCP[key] = TaskItem(
                id: key,
                category: .pending,
                kind: .response,
                title: "等待用户输入",
                subtitle: session?.workspaceName,
                conversationId: conversationId,
                workspace: session?.workspace,
                transcriptPath: session?.transcriptPath,
                startedAt: respondedAt,
                updatedAt: now,
                expiresAt: nil
            )
        }
    }

    private func removeAwaitingInput(for conversationId: String) {
        pendingShellMCP.removeValue(forKey: "await-\(conversationId)")
    }

    private func clearPending(for conversationId: String) {
        pendingShellMCP = pendingShellMCP.filter { $0.value.conversationId != conversationId }
    }

    private func clearPendingShell(for conversationId: String, prefix: String) {
        let keys = pendingShellMCP.keys.filter { key in
            key.hasPrefix(prefix) && pendingShellMCP[key]?.conversationId == conversationId
        }
        keys.forEach { pendingShellMCP.removeValue(forKey: $0) }
    }

    private func addRecent(from item: TaskItem, title: String, at date: Date, status: String? = nil) {
        let final = TaskItem(
            id: "recent-\(item.id)-\(Int(date.timeIntervalSince1970))",
            category: .recent,
            kind: item.kind,
            title: status == "error" ? "失败: \(title)" : title,
            subtitle: item.subtitle,
            conversationId: item.conversationId,
            workspace: item.workspace,
            transcriptPath: item.transcriptPath,
            startedAt: item.startedAt,
            updatedAt: date,
            expiresAt: date.addingTimeInterval(recentTTL)
        )
        addRecent(final)
    }

    private func addRecent(_ item: TaskItem) {
        recent.removeAll { $0.id == item.id }
        recent.insert(item, at: 0)
        if recent.count > 50 {
            recent = Array(recent.prefix(50))
        }
    }

    private func sessionTitle(for event: AgentEvent) -> String {
        if event.isBackgroundAgent == true { return "Background Agent" }
        if let mode = event.composerMode { return "会话 (\(mode))" }
        return "Agent 会话"
    }

    private func truncated(_ text: String, limit: Int = 80) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    private func loadSnapshotIfPresent() {
        // 仅以 events.jsonl 重放为准；跳过快照中的 running/pending 避免残留
    }

    private func pruneStaleRunning(now: Date) {
        tools = tools.filter { _, item in
            now.timeIntervalSince(item.updatedAt) < staleToolTTL
        }
        subagents = subagents.filter { _, item in
            now.timeIntervalSince(item.updatedAt) < staleToolTTL * 4
        }
        sessions = sessions.filter { conversationId, item in
            let last = lastActivityAt[conversationId] ?? item.updatedAt
            return now.timeIntervalSince(last) < staleSessionTTL
        }
        pendingShellMCP = pendingShellMCP.filter { key, item in
            if key.hasPrefix("await-") {
                let last = lastActivityAt[item.conversationId ?? ""] ?? item.updatedAt
                return now.timeIntervalSince(last) < staleSessionTTL
            }
            if item.kind == .shell || item.kind == .mcp {
                return now.timeIntervalSince(item.updatedAt) < stalePendingTTL
            }
            return true
        }
        for conversationId in lastResponseAt.keys {
            if sessions[conversationId] == nil &&
                !tools.values.contains(where: { $0.conversationId == conversationId }) {
                lastResponseAt.removeValue(forKey: conversationId)
            }
        }
    }

    private func clearRunningTools(for conversationId: String) {
        tools = tools.filter { $0.value.conversationId != conversationId }
    }

    private func clearRunningSubagents(for conversationId: String) {
        subagents = subagents.filter { $0.value.conversationId != conversationId }
    }

    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPublishedLists()
            }
        }
    }

    private func pruneExpired() {
        let now = Date()
        recent = recent.filter { item in
            guard let expiresAt = item.expiresAt else { return true }
            return expiresAt > now
        }
        pendingShellMCP = pendingShellMCP.filter { _, item in
            guard let expiresAt = item.expiresAt else { return true }
            return expiresAt > now
        }
    }

    func openCursor() {
        NSWorkspace.shared.launchApplication("Cursor")
    }

    func openTranscript(for item: TaskItem) {
        guard let path = item.transcriptPath else {
            openCursor()
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
