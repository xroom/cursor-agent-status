#!/usr/bin/env bash
# Verify simplified HUD three-phase display logic
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

echo "== Building CursorAgentStatus =="
xcodebuild -project CursorAgentStatus.xcodeproj -scheme CursorAgentStatus -configuration Debug build -quiet

echo "== Compiling HUD phase smoke test =="
BIN="$(mktemp -t hud-phase-test)"
swiftc -o "${BIN}" \
  CursorAgentStatus/Models/AgentEvent.swift \
  CursorAgentStatus/Models/TaskItem.swift \
  CursorAgentStatus/Services/StatusStore.swift \
  CursorAgentStatus/Services/ComposerNameResolver.swift \
  CursorAgentStatus/Services/CursorControl.swift \
  CursorAgentStatus/Models/TaskItem+CompactDisplay.swift \
  CursorAgentStatus/Views/ProInfoTheme.swift \
  CursorAgentStatus/Views/TrafficLightView.swift \
  scripts/hud-phase-test-main.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Foundation

echo "== Running HUD phase smoke test =="
"${BIN}"
rm -f "${BIN}"

echo ""
echo "HUD phase verification passed."
