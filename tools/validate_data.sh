#!/usr/bin/env bash
# Data-integrity gate. Exit 0 = valid, non-zero = invalid. Wired into CI + workflows.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
if [ -z "${GODOT_BIN}" ] || [ ! -x "${GODOT_BIN}" ]; then
  echo "ERROR: Godot binary not found. Set GODOT_BIN or put 'godot' on PATH." >&2
  exit 2
fi
LOG_FILE="${TMPDIR:-/tmp}/mining_game_validate.log"
"${GODOT_BIN}" --headless --path . --log-file "${LOG_FILE}" --import
"${GODOT_BIN}" --headless --path . --log-file "${LOG_FILE}" -s res://tools/validate_data.gd
