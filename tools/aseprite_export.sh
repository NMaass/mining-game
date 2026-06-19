#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: tools/aseprite_export.sh art/source/generated/name.aseprite [art/runtime/name.png]" >&2
  exit 64
fi

input="$1"
output="${2:-}"

case "$input" in
  *.ase|*.aseprite) ;;
  *)
    echo "Input must be an .ase or .aseprite file: $input" >&2
    exit 64
    ;;
esac

if [ ! -f "$input" ]; then
  echo "Input file does not exist: $input" >&2
  exit 66
fi

aseprite_bin="${ASEPRITE_BIN:-/Applications/Aseprite.app/Contents/MacOS/aseprite}"
if [ ! -x "$aseprite_bin" ]; then
  echo "Aseprite executable not found or not executable: $aseprite_bin" >&2
  echo "Set ASEPRITE_BIN=/path/to/aseprite and retry." >&2
  exit 69
fi

if [ -z "$output" ]; then
  base="$(basename "$input")"
  name="${base%.*}"
  output="art/runtime/${name}.png"
fi

mkdir -p "$(dirname "$output")"

"$aseprite_bin" \
  --batch "$input" \
  --save-as "$output"

echo "Exported $input -> $output"
