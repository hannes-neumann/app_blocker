#!/bin/bash
# Builds FocusFlow and wraps the binary into a runnable .app bundle in ./build.
#
# Optional settings (scripts/release.sh uses them):
#   FOCUSFLOW_BUILD_DIR      where the app goes, default ./build
#   FOCUSFLOW_SIGN_IDENTITY  certificate name to sign with, default "-" (ad hoc, only runs on this Mac without warnings)
#   FOCUSFLOW_UNIVERSAL=1    build for Apple chips and Intel
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${FOCUSFLOW_BUILD_DIR:-build}"
IDENTITY="${FOCUSFLOW_SIGN_IDENTITY:--}"
APP="$OUT/FocusFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${FOCUSFLOW_UNIVERSAL:-0}" = 1 ]; then
    # `swift build --arch` for several architectures needs a full Xcode, so build each one and merge them.
    for product in FocusFlow focusflow-mcp; do
        parts=()
        for arch in arm64 x86_64; do
            swift build -c release --triple "$arch-apple-macosx14.0" --product "$product"
            parts+=("$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)/$product")
        done
        lipo -create "${parts[@]}" -output "$APP/Contents/MacOS/$product"
    done
else
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
    cp "$BIN_DIR/FocusFlow" "$APP/Contents/MacOS/FocusFlow"
    # MCP server for Claude, see Settings → General → Claude.
    cp "$BIN_DIR/focusflow-mcp" "$APP/Contents/MacOS/focusflow-mcp"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
# What was built, for `focusflow status`. A "+" marks changes that are not committed.
COMMIT="$(git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)"
[ -z "$(git status --porcelain 2>/dev/null)" ] || COMMIT="$COMMIT+"
/usr/libexec/PlistBuddy -c "Add :FocusFlowCommit string $COMMIT" \
    -c "Add :FocusFlowPostHogKey string ${FOCUSFLOW_POSTHOG_KEY:-}" \
    -c "Add :FocusFlowBuildDate string $(date '+%Y-%m-%d %H:%M:%S')" "$APP/Contents/Info.plist"
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/FocusFlowIcon.XXXXXX.iconset")"
trap 'rm -rf "$ICONSET"' EXIT
sips -s format png Resources/FocusFlowIcon.svg --out "$ICONSET/icon_1024x1024.png" >/dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICONSET/icon_1024x1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/FocusFlowIcon.icns"
SIGN=(codesign --force --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
    # A real certificate keeps the signature the same across builds, so macOS keeps the granted permissions.
    SIGN+=(--options runtime --timestamp=none)
fi
"${SIGN[@]}" "$APP/Contents/MacOS/focusflow-mcp" >/dev/null
"${SIGN[@]}" --entitlements Resources/FocusFlow.entitlements "$APP" >/dev/null

echo "Gebaut: $APP"
echo "Starten mit: open $APP"
