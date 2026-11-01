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
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/FocusFlowIcon.XXXXXX.iconset")"
trap 'rm -rf "$ICONSET"' EXIT
sips -s format png Resources/FocusFlowIcon.svg --out "$ICONSET/icon_1024x1024.png" >/dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/FocusFlowIcon.icns"
codesign --force --sign - "$APP" >/dev/null

echo "Gebaut: $APP"
echo "Starten mit: open $APP"
