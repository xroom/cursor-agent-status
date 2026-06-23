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

    /// 悬浮窗「刚完成」单行摘要
    var compactRecentText: String {
        title
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

extension StatusStore {
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
