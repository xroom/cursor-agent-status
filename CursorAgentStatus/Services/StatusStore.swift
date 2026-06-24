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

    private(set) var revision = 0

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
    /// 每个会话的用户指令摘要，用于悬浮窗展示「正在做什么」
    private var conversationHeadlines: [String: String] = [:]
    /// 每个会话的 Agent 显示名称
    private var agentNames: [String: String] = [:]
    /// 最近一次 Agent 思考摘要（afterAgentThought）
    private var conversationThoughts: [String: String] = [:]
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
        conversationHeadlines.removeAll()
        agentNames.removeAll()
        conversationThoughts.removeAll()
        refreshPublishedLists()
    }

    private func apply(_ event: AgentEvent) {
        let conversationId = event.conversationId ?? "unknown"
        let now = event.date
        lastActivityAt[conversationId] = now

        switch event.event {
        case "beforeSubmitPrompt":
            let promptPreview = event.title ?? "正在处理指令"
            conversationHeadlines[conversationId] = truncated(promptPreview, limit: 80)
            if agentNames[conversationId] == nil {
                registerAgentName(from: event, conversationId: conversationId)
            }
            let item = TaskItem(
                id: "processing-\(conversationId)",
                category: .running,
                kind: .processing,
                title: "处理中: \(truncated(promptPreview, limit: 60))",
                subtitle: "已收到你的消息",
                conversationId: event.conversationId,
                workspace: event.workspace,
                transcriptPath: event.transcriptPath,
                startedAt: now,
                updatedAt: now,
                expiresAt: nil
            )
            sessions[conversationId] = item
            lastResponseAt.removeValue(forKey: conversationId)
            removeAwaitingInput(for: conversationId)

        case "afterAgentThought":
            if let thought = normalizedThoughtText(event.title) {
                conversationThoughts[conversationId] = thought
            }
            let item = TaskItem(
                id: "thinking-\(conversationId)",
                category: .running,
                kind: .thinking,
                title: "思考中…",
                subtitle: conversationThoughts[conversationId],
                conversationId: event.conversationId,
                workspace: event.workspace,
                transcriptPath: event.transcriptPath,
                startedAt: now,
                updatedAt: now,
                expiresAt: nil
            )
            sessions[conversationId] = item

        case "sessionStart":
            registerAgentName(from: event, conversationId: conversationId)
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
            conversationHeadlines.removeValue(forKey: conversationId)
            agentNames.removeValue(forKey: conversationId)
            conversationThoughts.removeValue(forKey: conversationId)
            if let session = sessions.removeValue(forKey: conversationId) {
                if event.status == "completed" || event.status == nil {
                    addRecent(
                        from: session,
                        summary: event.summary ?? event.title,
                        at: now
                    )
                }
            }
            clearPending(for: conversationId)
            lastResponseAt.removeValue(forKey: conversationId)
            tools = tools.filter { $0.value.conversationId != conversationId }
            subagents = subagents.filter { $0.value.conversationId != conversationId }

        case "preToolUse":
            sessions.removeValue(forKey: conversationId) // 清除「处理中/思考中」占位
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
                addRecent(
                    from: item,
                    summary: event.summary ?? event.title,
                    at: now,
                    status: event.status
                )
            } else if let summary = normalizedRecentText(event.summary ?? event.title) {
                addRecent(
                    TaskItem(
                        id: "subagent-done-\(UUID().uuidString)",
                        category: .recent,
                        kind: .subagent,
                        title: summary,
                        subtitle: event.subagentType,
                        conversationId: event.conversationId,
                        workspace: event.workspace,
                        transcriptPath: event.transcriptPath,
                        startedAt: now,
                        updatedAt: now,
                        expiresAt: now.addingTimeInterval(recentTTL),
                        summary: summary
                    )
                )
            }

        case "beforeShellExecution":
            // 不在触发时标记待确认；Hook 返回 allow 时命令会自动执行，不应闪现在待确认
            break

        case "afterShellExecution":
            clearPendingShell(for: conversationId, prefix: "shell-")

        case "beforeMCPExecution":
            // 不在触发时标记待确认；自动执行的 MCP 不应出现在待确认列表
            break

        case "afterMCPExecution":
            clearPendingShell(for: conversationId, prefix: "mcp-")

        case "afterAgentResponse":
            lastResponseAt[conversationId] = now
            // 一轮工具调用结束，清除可能未收到 postToolUse 的残留
            clearRunningTools(for: conversationId)
            clearRunningSubagents(for: conversationId)
            if let summary = normalizedRecentText(event.summary ?? event.title) {
                addRecent(
                    TaskItem(
                        id: "response-\(conversationId)-\(Int(now.timeIntervalSince1970))",
                        category: .recent,
                        kind: .response,
                        title: summary,
                        subtitle: nil,
                        conversationId: event.conversationId,
                        workspace: event.workspace,
                        transcriptPath: event.transcriptPath,
                        startedAt: now,
                        updatedAt: now,
                        expiresAt: now.addingTimeInterval(recentTTL),
                        summary: summary
                    )
                )
            }

        case "stop":
            clearRunningTools(for: conversationId)
            clearRunningSubagents(for: conversationId)
            clearPending(for: conversationId)
            removeAwaitingInput(for: conversationId)
            if event.status == "completed" || event.status == "aborted" {
                sessions.removeValue(forKey: conversationId)
                conversationHeadlines.removeValue(forKey: conversationId)
                agentNames.removeValue(forKey: conversationId)
                conversationThoughts.removeValue(forKey: conversationId)
            }
            if event.status == "completed" {
                addRecent(
                    TaskItem(
                        id: "stop-\(conversationId)-\(Int(now.timeIntervalSince1970))",
                        category: .recent,
                        kind: .stop,
                        title: "",
                        subtitle: event.workspace,
                        conversationId: event.conversationId,
                        workspace: event.workspace,
                        transcriptPath: event.transcriptPath,
                        startedAt: now,
                        updatedAt: now,
                        expiresAt: now.addingTimeInterval(recentTTL),
                        summary: event.summary ?? event.title
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

        let newRunning = (Array(sessions.values) + Array(tools.values) + Array(subagents.values))
            .sorted { $0.updatedAt > $1.updatedAt }
        let newPending = Array(pendingShellMCP.values)
            .sorted { $0.updatedAt > $1.updatedAt }
        let newRecent = recent
            .sorted { $0.updatedAt > $1.updatedAt }

        let changed = newRunning != running || newPending != pending || newRecent != recent
        running = newRunning
        pending = newPending
        recent = newRecent

        if changed {
            revision += 1
        }
        ComposerNameResolver.shared.refreshIfNeeded()
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

    private func normalizedRecentText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return truncated(trimmed, limit: 200)
    }

    private func addRecent(from item: TaskItem, summary: String?, at date: Date, status: String? = nil) {
        guard let text = normalizedRecentText(summary) else { return }
        let title = status == "error" ? "失败: \(text)" : text
        let final = TaskItem(
            id: "recent-\(item.id)-\(Int(date.timeIntervalSince1970))",
            category: .recent,
            kind: item.kind,
            title: title,
            subtitle: item.subtitle,
            conversationId: item.conversationId,
            workspace: item.workspace,
            transcriptPath: item.transcriptPath,
            startedAt: item.startedAt,
            updatedAt: date,
            expiresAt: date.addingTimeInterval(recentTTL),
            summary: text
        )
        addRecent(final)
    }

    private func addRecent(_ item: TaskItem) {
        guard let text = normalizedRecentText(item.summary ?? (item.title.isEmpty ? nil : item.title)) else {
            return
        }
        var entry = item
        if entry.title.isEmpty || entry.title != text {
            entry = TaskItem(
                id: item.id,
                category: item.category,
                kind: item.kind,
                title: text,
                subtitle: item.subtitle,
                conversationId: item.conversationId,
                workspace: item.workspace,
                transcriptPath: item.transcriptPath,
                startedAt: item.startedAt,
                updatedAt: item.updatedAt,
                expiresAt: item.expiresAt,
                summary: text
            )
        }
        recent.removeAll { $0.id == entry.id }
        recent.insert(entry, at: 0)
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

    var canStopAgent: Bool {
        activeCount > 0
    }

    func stopActiveAgent() {
        CursorControl.cancelGeneration()
    }

    func sessionHeadline(for conversationId: String?) -> String? {
        guard let conversationId else { return nil }
        return conversationHeadlines[conversationId]
    }

    func sessionThought(for conversationId: String?) -> String? {
        guard let conversationId else { return nil }
        return conversationThoughts[conversationId]
    }

    private func normalizedThoughtText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return truncated(trimmed, limit: 120)
    }

    func agentDisplayName(for conversationId: String) -> String {
        if let name = ComposerNameResolver.shared.name(for: conversationId), !name.isEmpty {
            return name
        }
        if let name = agentNames[conversationId], !name.isEmpty {
            return name
        }
        if let headline = sessionHeadline(for: conversationId) {
            return truncateHeadline(headline, limit: 36)
        }
        if let workspace = (running + pending).first(where: { $0.conversationId == conversationId })?.workspace {
            return (workspace as NSString).lastPathComponent
        }
        return "Agent"
    }

    private func registerAgentName(from event: AgentEvent, conversationId: String) {
        let name = agentName(from: event)
        if !name.isEmpty {
            agentNames[conversationId] = name
        }
    }

    private func agentName(from event: AgentEvent) -> String {
        if event.isBackgroundAgent == true { return "Background Agent" }
        if let mode = event.composerMode, !mode.isEmpty {
            return displayComposerMode(mode)
        }
        if let workspace = event.workspace, !workspace.isEmpty {
            return (workspace as NSString).lastPathComponent
        }
        return "Agent"
    }

    private func displayComposerMode(_ mode: String) -> String {
        switch mode.lowercased() {
        case "agent": return "Agent"
        case "chat": return "Chat"
        case "edit": return "Edit"
        default: return mode.prefix(1).uppercased() + mode.dropFirst()
        }
    }

    private func truncateHeadline(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    func openTranscript(for item: TaskItem) {
        guard let path = item.transcriptPath else {
            openCursor()
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
