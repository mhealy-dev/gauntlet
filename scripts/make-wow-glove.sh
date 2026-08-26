#!/bin/sh
# Rebuilds gloves/wow from NeticSoul/retail-cursor-pack (Blizzard's retail
# cursor art, not redistributable — hence built locally instead of committed).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> fetching retail-cursor-pack MPQ"
curl -sL "https://raw.githubusercontent.com/NeticSoul/retail-cursor-pack/HEAD/patch-y.mpq" \
     -o "$WORK/patch-y.mpq"

echo "==> setting up python env"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" -q install mpyq Pillow

echo "==> extracting BLPs"
"$WORK/venv/bin/python" "$ROOT/scripts/mpqx.py" "$WORK/patch-y.mpq" "$WORK/blp"

echo "==> decoding BLP2 -> PNG"
"$WORK/venv/bin/python" "$ROOT/scripts/blp2png.py" "$WORK/blp" "$WORK/png"

echo "==> building glove"
"$WORK/venv/bin/python" "$ROOT/scripts/build_wow_glove.py" "$WORK/png" "$ROOT/gloves/wow"

echo "==> done: apply with \`$ROOT/gauntlet use wow\`"
