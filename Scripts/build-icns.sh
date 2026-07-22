#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MASTER=Resources/Icon-1024.png
ICONSET=Resources/AppIcon.iconset

echo "[1/3] generate master PNG…"
swift Scripts/generate-icon.swift "$MASTER"

echo "[2/3] iconset resize…"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

declare -a SIZES=(16 32 64 128 256 512 1024)
sips -Z 16   "$MASTER" --out "$ICONSET/icon_16x16.png"        >/dev/null
sips -Z 32   "$MASTER" --out "$ICONSET/icon_16x16@2x.png"     >/dev/null
sips -Z 32   "$MASTER" --out "$ICONSET/icon_32x32.png"        >/dev/null
sips -Z 64   "$MASTER" --out "$ICONSET/icon_32x32@2x.png"     >/dev/null
sips -Z 128  "$MASTER" --out "$ICONSET/icon_128x128.png"      >/dev/null
sips -Z 256  "$MASTER" --out "$ICONSET/icon_128x128@2x.png"   >/dev/null
sips -Z 256  "$MASTER" --out "$ICONSET/icon_256x256.png"      >/dev/null
sips -Z 512  "$MASTER" --out "$ICONSET/icon_256x256@2x.png"   >/dev/null
sips -Z 512  "$MASTER" --out "$ICONSET/icon_512x512.png"      >/dev/null
cp "$MASTER"                       "$ICONSET/icon_512x512@2x.png"

echo "[3/3] iconutil → Cadence.icns…"
iconutil -c icns "$ICONSET" -o Resources/Cadence.icns
echo "wrote Resources/Cadence.icns"
