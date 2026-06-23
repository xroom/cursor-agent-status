#!/usr/bin/env python3
"""Normalize Cursor hook events and append to agent-status event log."""

import json
import os
import sys
import time
from pathlib import Path


def pick_title(data: dict) -> str | None:
    for key in ("prompt", "task", "description", "command", "text", "agent_message", "tool_name"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            text = value.strip()
            return text[:120] + ("…" if len(text) > 120 else "")

    tool_input = data.get("tool_input")
    if isinstance(tool_input, dict):
        for key in ("command", "description", "pattern", "query"):
            value = tool_input.get(key)
            if isinstance(value, str) and value.strip():
                text = value.strip()
                return text[:120] + ("…" if len(text) > 120 else "")
    return None


def append_event(events_file: Path, line: str) -> None:
    events_file.parent.mkdir(parents=True, exist_ok=True)
    with events_file.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def main() -> int:
    events_file = Path(sys.argv[1])
    raw_input = sys.stdin.read()

    try:
        payload = json.loads(raw_input)
    except json.JSONDecodeError:
        print("{}")
        return 0

    event_name = payload.get("hook_event_name") or payload.get("event") or "unknown"
    conversation_id = payload.get("conversation_id") or payload.get("session_id")
    workspace_roots = payload.get("workspace_roots") or []
    workspace = workspace_roots[0] if workspace_roots else payload.get("cwd")

    normalized = {
        "ts": int(time.time() * 1000),
        "event": event_name,
        "conversation_id": conversation_id,
        "generation_id": payload.get("generation_id"),
        "tool_use_id": payload.get("tool_use_id"),
        "tool_name": payload.get("tool_name"),
        "subagent_id": payload.get("subagent_id"),
        "subagent_type": payload.get("subagent_type"),
        "title": pick_title(payload),
        "workspace": workspace,
        "transcript_path": payload.get("transcript_path"),
        "status": payload.get("status") or payload.get("reason") or payload.get("final_status"),
        "failure_type": payload.get("failure_type"),
        "command": payload.get("command"),
        "duration_ms": payload.get("duration_ms") or payload.get("duration"),
        "is_background_agent": payload.get("is_background_agent"),
        "composer_mode": payload.get("composer_mode"),
        "summary": payload.get("summary"),
    }

    line = json.dumps(normalized, ensure_ascii=False, separators=(",", ":"))
    append_event(events_file, line)

    if event_name in ("beforeShellExecution", "beforeMCPExecution"):
        print(json.dumps({"permission": "allow"}))
    else:
        print("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
