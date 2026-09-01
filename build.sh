#!/bin/bash
# Builds GlossyBar.app. Pass --run to (re)launch it when done.
set -euo pipefail
cd "$(dirname "$0")"

APP="GlossyBar.app"
CONFIG=release

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/GlossyBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GlossyBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.glossybar.GlossyBar "$APP" >/dev/null

echo "Built $PWD/$APP"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x GlossyBar 2>/dev/null || true
  open "$APP"
  echo "Launched."
fi
