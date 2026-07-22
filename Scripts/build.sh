#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[1/4] xcodegen…"
xcodegen generate

echo "[2/4] xcodebuild archive…"
rm -rf build
xcodebuild \
  -project Cadence.xcodeproj \
  -scheme Cadence \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[3/4] locate .app…"
APP="$(find build -name 'Cadence.app' -type d | head -1)"
echo "  -> $APP"

echo "[4/4] install to ~/Applications/Cadence.app…"
rm -rf ~/Applications/Cadence.app
cp -R "$APP" ~/Applications/Cadence.app
codesign --force --deep --sign - ~/Applications/Cadence.app

echo "Done: ~/Applications/Cadence.app"
