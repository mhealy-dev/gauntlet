#!/bin/sh
# Dumps every stock macOS cursor to reference/ as NN.png plus a labelled
# contact sheet — the source material behind CURSORS.md.
#
# Temporarily resets cursors to stock so the dump shows the system set, then
# restores whichever glove was active.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/reference"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CURRENT="$(readlink "$ROOT/gloves/.current" 2>/dev/null || true)"

echo "==> building dumper"
clang -fobjc-arc -fmodules -o "$WORK/dump" "$ROOT/scripts/dump_cursors.m" \
    -framework AppKit -framework ApplicationServices

echo "==> resetting to stock cursors"
"$ROOT/gauntlet" reset >/dev/null 2>&1 || true

echo "==> dumping"
mkdir -p "$OUT"
rm -f "$OUT"/*.png
"$WORK/dump" "$OUT" > "$OUT/cursors.txt"
echo "    $(wc -l < "$OUT/cursors.txt" | tr -d ' ') cursors -> $OUT"

echo "==> building contact sheet"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" -q install Pillow
"$WORK/venv/bin/python" "$ROOT/scripts/make_sheet.py" \
    "$OUT" "$OUT/cursors.txt" "$OUT/sheet.png"

if [ -n "$CURRENT" ]; then
    echo "==> restoring glove: $CURRENT"
    "$ROOT/gauntlet" use "$CURRENT" >/dev/null
fi

echo "==> done: open $OUT/sheet.png"
