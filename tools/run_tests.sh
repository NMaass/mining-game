#!/usr/bin/env bash
# Headless test runner for the Mining Game vertical slice.
# Runs the full gdUnit4 suite under tests/ with no editor. Exit code is the gate.
#
# Usage:
#   tools/run_tests.sh                # run all tests/
#   tools/run_tests.sh tests/unit     # run a subdirectory
#   GODOT_BIN=/path/to/godot tools/run_tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
if [ -z "${GODOT_BIN}" ] || [ ! -x "${GODOT_BIN}" ]; then
  echo "ERROR: Godot binary not found. Set GODOT_BIN or put 'godot' on PATH." >&2
  exit 2
fi

TARGET="${1:-tests}"

# Ensure the project is imported (first run generates .godot/). Idempotent.
LOG_FILE="${TMPDIR:-/tmp}/mining_game_tests.log"
"${GODOT_BIN}" --headless --path . --log-file "${LOG_FILE}" --import

echo "== Running gdUnit4 suite: ${TARGET} =="
"${GODOT_BIN}" --headless --path . --log-file "${LOG_FILE}" \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add "res://${TARGET}" \
  --ignoreHeadlessMode \
  --continue
