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
"${GODOT_BIN}" --headless --path . --import >/dev/null 2>&1 || true
"${GODOT_BIN}" --headless --path . -s res://tools/validate_data.gd
