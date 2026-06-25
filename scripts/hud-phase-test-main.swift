import Foundation

@MainActor
func runHUDPhaseTests() -> Int {
    let conv = "hudphase12345678"
    let headline = "验证 HUD 三阶段"
    let summary = "任务已完成：summary 正文"
    let store = StatusStore()
    store.prepareForLiveEvents()

    func event(
        _ name: String,
        conversationId: String = conv,
        title: String? = nil,
        summary: String? = nil,
        toolUseId: String? = nil,
        toolName: String? = nil,
        status: String? = nil
    ) -> AgentEvent {
        AgentEvent(
            ts: Int64(Date().timeIntervalSince1970 * 1000),
            event: name,
            conversationId: conversationId,
            generationId: nil,
            toolUseId: toolUseId,
            toolName: toolName,
            subagentId: nil,
            subagentType: nil,
            title: title,
            workspace: "/tmp",
            transcriptPath: nil,
            status: status,
            failureType: nil,
            command: nil,
            durationMs: nil,
            isBackgroundAgent: nil,
            composerMode: nil,
            summary: summary
        )
    }

    func assertPhase(_ label: String, _ condition: @autoclosure () -> Bool) -> Bool {
        if condition() { return true }
        fputs("FAIL: \(label)\n", stderr)
        return false
    }

    let thoughtText = "正在分析代码结构，准备检查 EventTailer 与 StatusStore 的事件处理逻辑"
    let thoughtSummary = HUDThoughtFormatter.summary(thoughtText)!

    store.handle(event("beforeSubmitPrompt", title: headline))
    var content = store.floatingContent(for: conv)
    guard assertPhase("prompt", content.statusLine == headline && content.statusCode == .run) else { return 1 }

    store.handle(event("afterAgentThought", title: thoughtText))
    content = store.floatingContent(for: conv)
    guard assertPhase("prepare", content.statusLine == thoughtSummary && content.statusCode == .run) else { return 1 }

    store.handle(event("afterAgentThought", title: thoughtText + "，继续深入分析"))
    content = store.floatingContent(for: conv)
    let secondThought = thoughtText + "，继续深入分析"
    guard assertPhase("thinking", content.statusLine == HUDThoughtFormatter.truncated(secondThought)! && content.statusCode == .run) else { return 1 }

    store.handle(event("preToolUse", title: "/tmp/foo.swift", toolUseId: "tool-1", toolName: "Read"))
    content = store.floatingContent(for: conv)
    guard assertPhase("execute", content.statusLine == "正在读取 foo.swift" && content.statusCode == .run) else { return 1 }

    store.handle(event("stop", summary: summary, status: "completed"))
    content = store.floatingContent(for: conv)
    guard assertPhase("done", content.statusLine == summary && content.statusCode == .done) else { return 1 }
    guard assertPhase("hud visible after stop", !store.activeFloatingAgents().isEmpty) else { return 1 }

    store.recentTTL = 0.01
    Thread.sleep(forTimeInterval: 0.02)
    store.handle(event("_pruneTick"))
    content = store.floatingContent(for: conv)
    guard assertPhase("summary persists", content.statusLine == summary && content.statusCode == .done) else { return 1 }

    let newHeadline = "新的任务指令"
    let newThought = "开始处理新的任务指令，先读取相关文件"
    store.handle(event("beforeSubmitPrompt", title: newHeadline))
    content = store.floatingContent(for: conv)
    guard assertPhase("reset on new task", content.statusLine == newHeadline && content.statusCode == .run) else { return 1 }
    guard assertPhase("completed summary cleared", store.hudCompletedSummary(for: conv) == nil) else { return 1 }

    store.handle(event("afterAgentThought", title: newThought))
    content = store.floatingContent(for: conv)
    guard assertPhase("new task prepare", content.statusLine == HUDThoughtFormatter.summary(newThought)!) else { return 1 }

    let singleConv = "singlethought12345"
    store.handle(event("beforeSubmitPrompt", conversationId: singleConv, title: headline))
    content = store.floatingContent(for: singleConv)
    guard assertPhase("single-thought prompt", content.statusLine == headline) else { return 1 }

    store.handle(event("afterAgentThought", conversationId: singleConv, title: thoughtText))
    content = store.floatingContent(for: singleConv)
    guard assertPhase("single-thought prepare", content.statusLine == thoughtSummary) else { return 1 }

    store.advanceHUDThoughtPhase(for: singleConv)
    content = store.floatingContent(for: singleConv)
    guard assertPhase("single-thought thinking", content.statusLine == HUDThoughtFormatter.truncated(thoughtText)!) else { return 1 }

    store.handle(event("preToolUse", conversationId: singleConv, title: "/tmp/foo.swift", toolUseId: "tool-single", toolName: "Read"))
    content = store.floatingContent(for: singleConv)
    guard assertPhase("single-thought execute", content.statusLine == "正在读取 foo.swift") else { return 1 }

    let stopConv = "hudphasestop1234"
    store.handle(event("beforeSubmitPrompt", conversationId: stopConv, title: headline))
    store.handle(event("afterAgentThought", conversationId: stopConv, title: thoughtText))
    store.handle(event("stop", conversationId: stopConv, status: "aborted"))
    content = store.floatingContent(for: stopConv)
    guard assertPhase("stopped", content.statusLine == "已停止" && content.statusCode == .stop) else { return 1 }

    fputs("OK: HUD phase sequence verified\n", stderr)
    return 0
}

@main
struct HUDPhaseTestMain {
    static func main() {
        let code = MainActor.assumeIsolated { runHUDPhaseTests() }
        exit(Int32(code))
    }
}
