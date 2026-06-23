#!/usr/bin/env bash
set -euo pipefail

STATUS_DIR="${HOME}/.cursor/agent-status"
EVENTS_FILE="${STATUS_DIR}/events.jsonl"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "${STATUS_DIR}"
python3 "${SCRIPT_DIR}/status-bridge.py" "${EVENTS_FILE}"
exit 0
