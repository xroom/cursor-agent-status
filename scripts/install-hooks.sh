#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CURSOR_DIR="${HOME}/.cursor"
HOOKS_DIR="${CURSOR_DIR}/hooks"
HOOKS_JSON="${CURSOR_DIR}/hooks.json"

mkdir -p "${HOOKS_DIR}"
install -m 755 "${ROOT}/hooks/status-bridge.sh" "${HOOKS_DIR}/status-bridge.sh"
install -m 755 "${ROOT}/hooks/status-bridge.py" "${HOOKS_DIR}/status-bridge.py"

if [[ -f "${HOOKS_JSON}" ]]; then
  BACKUP="${HOOKS_JSON}.backup.$(date +%Y%m%d%H%M%S)"
  cp "${HOOKS_JSON}" "${BACKUP}"
  echo "Backed up existing hooks.json to ${BACKUP}"

  python3 - "${HOOKS_JSON}" "${ROOT}/hooks/hooks.json" <<'PY'
import json
import sys
from pathlib import Path

target = Path(sys.argv[1])
incoming = json.loads(Path(sys.argv[2]).read_text())
existing = json.loads(target.read_text()) if target.exists() else {"version": 1, "hooks": {}}

merged = existing.setdefault("hooks", {})
for event, entries in incoming.get("hooks", {}).items():
    commands = {entry.get("command") for entry in merged.get(event, []) if isinstance(entry, dict)}
    new_entries = merged.setdefault(event, [])
    for entry in entries:
        command = entry.get("command")
        if command and command not in commands:
            new_entries.append(entry)
            commands.add(command)

existing["version"] = incoming.get("version", existing.get("version", 1))
target.write_text(json.dumps(existing, indent=2) + "\n")
print(f"Merged status-bridge hooks into {target}")
PY
else
  install -m 644 "${ROOT}/hooks/hooks.json" "${HOOKS_JSON}"
  echo "Installed ${HOOKS_JSON}"
fi

mkdir -p "${HOME}/.cursor/agent-status"
echo "Hooks installed. Restart Cursor or save hooks.json to reload."
