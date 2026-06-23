#!/usr/bin/env bash
# Integration verification for Cursor Agent Status
set -euo pipefail

STATUS_DIR="${HOME}/.cursor/agent-status"
EVENTS_FILE="${STATUS_DIR}/events.jsonl"
HOOKS_JSON="${HOME}/.cursor/hooks.json"
BRIDGE="${HOME}/.cursor/hooks/status-bridge.sh"

echo "== Checking hooks installation =="
[[ -x "${BRIDGE}" ]] || { echo "FAIL: status-bridge.sh missing"; exit 1; }
[[ -f "${HOME}/.cursor/hooks/status-bridge.py" ]] || { echo "FAIL: status-bridge.py missing"; exit 1; }
[[ -f "${HOOKS_JSON}" ]] || { echo "FAIL: hooks.json missing"; exit 1; }
grep -q "status-bridge.sh" "${HOOKS_JSON}" || { echo "FAIL: hooks.json missing status-bridge entries"; exit 1; }
echo "OK: hooks installed"

echo "== Simulating event pipeline =="
CONV="verify-$(date +%s)"
send_event() {
  echo "$1" | "${BRIDGE}" >/dev/null
}

send_event "{\"hook_event_name\":\"sessionStart\",\"conversation_id\":\"${CONV}\",\"session_id\":\"${CONV}\",\"workspace_roots\":[\"/tmp\"],\"composer_mode\":\"agent\"}"
send_event "{\"hook_event_name\":\"preToolUse\",\"conversation_id\":\"${CONV}\",\"tool_use_id\":\"t1\",\"tool_name\":\"Shell\",\"tool_input\":{\"command\":\"echo hi\"},\"workspace_roots\":[\"/tmp\"]}"
send_event "{\"hook_event_name\":\"postToolUse\",\"conversation_id\":\"${CONV}\",\"tool_use_id\":\"t1\",\"tool_name\":\"Shell\",\"workspace_roots\":[\"/tmp\"]}"
send_event "{\"hook_event_name\":\"subagentStart\",\"conversation_id\":\"${CONV}\",\"subagent_id\":\"s1\",\"subagent_type\":\"explore\",\"task\":\"Explore codebase\",\"workspace_roots\":[\"/tmp\"]}"
send_event "{\"hook_event_name\":\"subagentStop\",\"conversation_id\":\"${CONV}\",\"subagent_id\":\"s1\",\"subagent_type\":\"explore\",\"status\":\"completed\",\"task\":\"Explore codebase\",\"summary\":\"Found auth module\",\"workspace_roots\":[\"/tmp\"]}"
send_event "{\"hook_event_name\":\"afterAgentResponse\",\"conversation_id\":\"${CONV}\",\"text\":\"All done.\",\"workspace_roots\":[\"/tmp\"]}"
send_event "{\"hook_event_name\":\"sessionEnd\",\"conversation_id\":\"${CONV}\",\"session_id\":\"${CONV}\",\"reason\":\"completed\",\"workspace_roots\":[\"/tmp\"]}"

COUNT=$(grep -c "\"conversation_id\":\"${CONV}\"" "${EVENTS_FILE}" || true)
[[ "${COUNT}" -ge 7 ]] || { echo "FAIL: expected >=7 events for ${CONV}, got ${COUNT}"; exit 1; }
echo "OK: wrote ${COUNT} events for conversation ${CONV}"

echo "== Checking Xcode build =="
cd "$(dirname "$0")/.."
xcodebuild -project CursorAgentStatus.xcodeproj -scheme CursorAgentStatus -configuration Debug build -quiet
echo "OK: app builds successfully"

echo ""
echo "All integration checks passed."
echo "Next: launch CursorAgentStatus.app and trigger a real Agent session in Cursor."
