#!/usr/bin/env bash
set -euo pipefail

STATUS_DIR="${HOME}/.cursor/agent-status"
EVENTS_FILE="${STATUS_DIR}/events.jsonl"
SNAPSHOT_FILE="${STATUS_DIR}/state.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "${STATUS_DIR}"
python3 "${SCRIPT_DIR}/status-bridge.py" "${EVENTS_FILE}" "${SNAPSHOT_FILE}"
exit 0
