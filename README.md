# Cursor Agent Status

基于 Cursor Hooks 的 macOS 菜单栏 + 悬浮窗应用，实时展示 AI Agent 工作状态。

📖 **完整使用手册**：[docs/使用手册.md](docs/使用手册.md)

## 功能

- **进行中**：活跃会话、工具执行、Subagent
- **待确认**：Shell/MCP 批准等待、Agent 回复后等待输入
- **刚完成**：最近 60 秒内完成的任务（自动淡出）

## 安装

### 1. 安装 Hooks

```bash
chmod +x scripts/install-hooks.sh hooks/status-bridge.sh
./scripts/install-hooks.sh
```

脚本会安装 `~/.cursor/hooks/status-bridge.sh` 和 `status-bridge.py`，并合并 `~/.cursor/hooks.json`。若已有 hooks，会先备份。

重启 Cursor 或保存 `hooks.json` 以加载 hooks。

### 2. 构建 Mac 应用

```bash
chmod +x scripts/generate-xcodeproj.sh
./scripts/generate-xcodeproj.sh
xcodebuild -project CursorAgentStatus.xcodeproj -scheme CursorAgentStatus -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Release/CursorAgentStatus.app
```

或在 Xcode 中打开 `CursorAgentStatus.xcodeproj` 并 Run。

## 数据流

```
Cursor Agent → ~/.cursor/hooks/status-bridge.sh → ~/.cursor/agent-status/events.jsonl
                                                          ↓
                                              CursorAgentStatus.app (FSEvents)
```

## 限制

- 仅覆盖**本地 IDE** Agent，Cloud Agent 不触发用户级 hooks
- Cursor Smart Mode 内置审批 UI 不一定能被 hook 捕获
- `preToolUse` 的 `ask` 权限目前未强制执行

## 项目结构

```
CursorAgentStatus/     SwiftUI 应用源码
hooks/                 Cursor hooks 脚本
scripts/               安装与工程生成脚本
```
