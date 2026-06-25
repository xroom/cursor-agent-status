import Foundation

extension TaskItem {
    /// 悬浮窗「进行中」单行摘要
    var compactRunningText: String {
        switch kind {
        case .tool:
            return compactToolAction(prefix: "正在")
        case .processing:
            return title.hasPrefix("处理中:") ? title : "正在处理指令"
        case .thinking:
            return "思考中…"
        case .subagent:
            return "正在运行 Subagent"
        case .session:
            return "Agent 会话进行中"
        default:
            return title
        }
    }

    /// 悬浮窗「待确认」单行摘要
    var compactPendingText: String {
        switch kind {
        case .shell:
            return "请确认 Shell 命令"
        case .mcp:
            return "请确认 MCP 操作"
        case .response:
            return "请确认是否继续"
        case .tool:
            return "请确认是否继续"
        default:
            return title.isEmpty ? "请确认是否继续" : title
        }
    }

    /// 悬浮窗「刚完成」：优先显示 Hook 总结
    var compactRecentText: String {
        floatingCompletedTitle()
    }

    /// 任务完成后的展示文案：仅显示 Hook summary
    func floatingCompletedTitle() -> String {
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitizedFloatingTitle(summary, fallback: "")
        }
        return sanitizedFloatingTitle(title, fallback: "")
    }

    var categoryLabel: String {
        switch category {
        case .running: return "进行中"
        case .pending: return "待确认"
        case .recent: return "刚完成"
        }
    }

    func compactSummaryText() -> String {
        switch category {
        case .running: return compactRunningText
        case .pending: return compactPendingText
        case .recent: return compactRecentText
        }
    }

    private func compactToolAction(prefix: String) -> String {
        let tool = subtitle ?? ""
        switch tool {
        case "Write", "StrReplace", "ApplyPatch", "EditNotebook":
            let file = fileName(from: title)
            return file.isEmpty ? "\(prefix)修改文件" : "\(prefix)修改 \(file)"
        case "Read", "Glob", "Grep", "SemanticSearch":
            let file = fileName(from: title)
            if !file.isEmpty { return "\(prefix)读取 \(file)" }
            return "\(prefix)搜索代码"
        case "Shell":
            let cmd = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return cmd.isEmpty ? "\(prefix)执行命令" : "\(prefix)执行 \(truncate(cmd, 36))"
        case "Task":
            return "\(prefix)启动 Subagent"
        case "Delete":
            let file = fileName(from: title)
            return file.isEmpty ? "\(prefix)删除文件" : "\(prefix)删除 \(file)"
        default:
            if !title.isEmpty, title != tool {
                return "\(prefix)\(truncate(title, 40))"
            }
            return tool.isEmpty ? "\(prefix)执行工具" : "\(prefix)执行 \(tool)"
        }
    }

    private func fileName(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }

    private func truncate(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}

struct CompactStatusLine {
    let categoryLabel: String
    let text: String
    let category: TaskCategory
}

struct FloatingPanelContent {
    let activityTitle: String
    let projectName: String
    let runningCount: Int
    let isIdle: Bool
    let isCompleted: Bool
}

struct AgentFloatingContent {
    let panelId: String
    let conversationId: String?
    let agentName: String
    let statusLine: String
    let statusCode: ProStatusCode
    let canStop: Bool
    let stepStartedAt: Date?

    var showsStepTimer: Bool {
        stepStartedAt != nil && (statusCode == .run || statusCode == .pnd)
    }
}

extension TaskItem {
    /// 悬浮窗第二行：优先展示思考摘要、Exploring 等阶段状态
    func floatingStatusLine(headline: String?, thought: String?) -> String {
        switch kind {
        case .subagent where isExploreSubagent:
            let detail = sanitizedFloatingTitle(title, fallback: "", maxLength: 60)
            return detail.isEmpty ? "Exploring" : "Exploring · \(detail)"
        case .tool where subtitle == "Task":
            let detail = sanitizedFloatingTitle(title, fallback: headline ?? "", maxLength: 60)
            return detail.isEmpty ? "Exploring" : "Exploring · \(detail)"
        case .thinking:
            return formattedThought(subtitle ?? thought)
        default:
            break
        }

        if let thought, !thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return formattedThought(thought)
        }

        return floatingActivityTitle(headline: headline)
    }

    private func formattedThought(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "思考中…"
        }
        return sanitizedFloatingTitle(text, fallback: "思考中…", maxLength: 80)
    }

    private var isExploreSubagent: Bool {
        (subtitle ?? "").lowercased() == "explore"
    }

    /// 悬浮窗第一行：正在做什么（自然语言，不暴露 Shell 命令）
    func floatingActivityTitle(headline: String?) -> String {
        switch kind {
        case .processing:
            if title.hasPrefix("处理中:") {
                let rest = title.dropFirst("处理中:".count).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? (headline ?? "处理指令") : String(rest)
            }
            return headline ?? title
        case .thinking:
            if let subtitle, !subtitle.isEmpty { return subtitle }
            return headline ?? "思考中…"
        case .subagent:
            return sanitizedFloatingTitle(title, fallback: headline ?? "子任务进行中")
        case .tool:
            return floatingToolActivity(headline: headline)
        case .session:
            return headline ?? sanitizedFloatingTitle(title, fallback: "Agent 会话")
        default:
            return headline ?? sanitizedFloatingTitle(title, fallback: "处理中…")
        }
    }

    private func floatingToolActivity(headline: String?) -> String {
        let tool = subtitle ?? ""
        switch tool {
        case "Shell":
            return headline ?? "正在处理…"
        case "Task":
            return sanitizedFloatingTitle(title, fallback: headline ?? "子任务进行中")
        case "SemanticSearch":
            return headline ?? "搜索代码库"
        case "Grep":
            return headline ?? "搜索代码"
        case "Glob":
            return headline ?? "查找文件"
        case "Read":
            if let headline, !headline.isEmpty { return headline }
            let file = fileName(from: title)
            return file.isEmpty ? "查看代码" : "查看 \(file)"
        case "Write", "StrReplace", "ApplyPatch", "EditNotebook":
            if let headline, !headline.isEmpty { return headline }
            let file = fileName(from: title)
            return file.isEmpty ? "修改代码" : "修改 \(file)"
        case "Delete":
            if let headline, !headline.isEmpty { return headline }
            let file = fileName(from: title)
            return file.isEmpty ? "删除文件" : "删除 \(file)"
        default:
            if let headline, !headline.isEmpty { return headline }
            if !title.isEmpty, title != tool {
                return sanitizedFloatingTitle(title, fallback: "处理中…")
            }
            return "处理中…"
        }
    }

    private func sanitizedFloatingTitle(_ text: String, fallback: String, maxLength: Int = 60) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if looksLikeShellCommand(trimmed) { return fallback }
        return truncate(trimmed, maxLength)
    }

    private func looksLikeShellCommand(_ text: String) -> Bool {
        let lower = text.lowercased()
        let prefixes = [
            "cd ", "npm ", "git ", "curl ", "bash ", "python ", "pnpm ", "yarn ",
            "xcodebuild", "sudo ", "make ", "docker ", "kubectl ", "./"
        ]
        if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        return text.contains("&&") || text.contains(" | ") || text.hasPrefix("/bin/")
    }
}

extension StatusStore {
    var floatingRunningTasksOrdered: [TaskItem] {
        running.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 每个应展示 HUD 的 Agent（会话）；仅包含本次 App 启动后触发了 Agent 开始事件的会话
    func activeFloatingAgents() -> [AgentFloatingContent] {
        activeHUDSessionIds.map { floatingContent(for: $0) }
    }

    private func isTrackableConversationId(_ id: String) -> Bool {
        id != "unknown" && id.count >= 8
    }

    func floatingContent(for conversationId: String) -> AgentFloatingContent {
        let agentName = agentDisplayName(for: conversationId)
        let runningFor = running.filter { $0.conversationId == conversationId }
        let pendingFor = pending.filter { $0.conversationId == conversationId }
        let headline = sessionHeadline(for: conversationId)
        let thought = sessionThought(for: conversationId)

        if let task = bestRunningTask(for: conversationId, in: runningFor) {
            return AgentFloatingContent(
                panelId: conversationId,
                conversationId: conversationId,
                agentName: agentName,
                statusLine: task.floatingStatusLine(headline: headline, thought: thought),
                statusCode: .run,
                canStop: true,
                stepStartedAt: task.startedAt
            )
        }

        if let task = pendingFor.max(by: { $0.updatedAt < $1.updatedAt }) {
            let line = task.kind == .response && task.title == "等待用户输入"
                ? (headline.map { "等待确认：\($0)" } ?? task.floatingStatusLine(headline: nil, thought: thought))
                : task.floatingStatusLine(headline: headline, thought: thought)
            return AgentFloatingContent(
                panelId: conversationId,
                conversationId: conversationId,
                agentName: agentName,
                statusLine: line,
                statusCode: .pnd,
                canStop: false,
                stepStartedAt: task.startedAt
            )
        }

        if isOngoingConversation(conversationId) {
            return AgentFloatingContent(
                panelId: conversationId,
                conversationId: conversationId,
                agentName: agentName,
                statusLine: ongoingStatusLine(headline: headline, thought: thought),
                statusCode: .run,
                canStop: true,
                stepStartedAt: conversationLastActivity(conversationId)
            )
        }

        if let recentItem = recent
            .filter({ $0.conversationId == conversationId })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            return AgentFloatingContent(
                panelId: conversationId,
                conversationId: conversationId,
                agentName: agentName,
                statusLine: recentItem.floatingCompletedTitle(),
                statusCode: .done,
                canStop: false,
                stepStartedAt: nil
            )
        }

        return AgentFloatingContent(
            panelId: conversationId,
            conversationId: conversationId,
            agentName: agentName,
            statusLine: "暂无活动",
            statusCode: .idle,
            canStop: false,
            stepStartedAt: nil
        )
    }

    func floatingIdleContent() -> AgentFloatingContent {
        AgentFloatingContent(
            panelId: "__idle__",
            conversationId: nil,
            agentName: "Cursor Agent",
            statusLine: "暂无进行中的任务",
            statusCode: .idle,
            canStop: false,
            stepStartedAt: nil
        )
    }

    private func latestActivity(for conversationId: String) -> Date {
        let items = (running + pending).filter { $0.conversationId == conversationId }
        if let latest = items.map(\.updatedAt).max() {
            return latest
        }
        return conversationLastActivity(conversationId) ?? .distantPast
    }

    private func ongoingStatusLine(headline: String?, thought: String?) -> String {
        if let thought, !thought.isEmpty { return thought }
        if let headline, !headline.isEmpty { return headline }
        return "处理中…"
    }

    private func bestRunningTask(for conversationId: String, in items: [TaskItem]) -> TaskItem? {
        let items = items.filter { $0.conversationId == conversationId }
        guard !items.isEmpty else { return nil }

        let priority: [TaskKind] = [.subagent, .thinking, .processing, .tool, .session]
        for kind in priority {
            if let item = items.filter({ $0.kind == kind }).max(by: { $0.updatedAt < $1.updatedAt }) {
                return item
            }
        }
        return items.max(by: { $0.updatedAt < $1.updatedAt })
    }

    func floatingContent(at rotateIndex: Int) -> FloatingPanelContent {
        let tasks = floatingRunningTasksOrdered
        if !tasks.isEmpty {
            let index = rotateIndex % tasks.count
            let task = tasks[index]
            return FloatingPanelContent(
                activityTitle: task.floatingActivityTitle(headline: sessionHeadline(for: task.conversationId)),
                projectName: task.workspaceName,
                runningCount: tasks.count,
                isIdle: false,
                isCompleted: false
            )
        }

        if let pending = pending.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return FloatingPanelContent(
                activityTitle: pending.floatingActivityTitle(headline: sessionHeadline(for: pending.conversationId)),
                projectName: pending.workspaceName,
                runningCount: 0,
                isIdle: false,
                isCompleted: false
            )
        }

        if let recentItem = recent.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return FloatingPanelContent(
                activityTitle: recentItem.floatingCompletedTitle(),
                projectName: recentItem.workspaceName,
                runningCount: 0,
                isIdle: false,
                isCompleted: true
            )
        }

        return FloatingPanelContent(
            activityTitle: "暂无进行中的任务",
            projectName: "—",
            runningCount: 0,
            isIdle: true,
            isCompleted: false
        )
    }

    var latestTaskItem: TaskItem? {
        let all = running + pending + recent
        return all.max(by: { $0.updatedAt < $1.updatedAt })
    }

    /// 三个状态中按更新时间取最新一条
    var latestCombinedStatus: CompactStatusLine? {
        guard let item = latestTaskItem else { return nil }
        return CompactStatusLine(
            categoryLabel: item.categoryLabel,
            text: item.compactSummaryText(),
            category: item.category
        )
    }
}
