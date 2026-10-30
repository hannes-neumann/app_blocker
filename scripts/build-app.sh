#!/bin/bash
# Builds FocusFlow and wraps the binary into a runnable .app bundle in ./build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/FocusFlow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FocusFlow" "$APP/Contents/MacOS/FocusFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Gebaut: $APP"
echo "Starten mit: open $APP"
