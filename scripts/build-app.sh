#!/bin/bash
# Builds FocusFlow and wraps the binary into a runnable .app bundle in ./build.
#
# Optional settings (scripts/release.sh uses them):
#   FOCUSFLOW_BUILD_DIR      where the app goes, default ./build
#   FOCUSFLOW_SIGN_IDENTITY  certificate name to sign with, default "-" (ad hoc, only runs on this Mac without warnings)
#   FOCUSFLOW_RUNTIME=1    add the hardened runtime option to an ad hoc signature
#   FOCUSFLOW_UNIVERSAL=1    build for Apple chips and Intel
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${FOCUSFLOW_BUILD_DIR:-build}"
IDENTITY="${FOCUSFLOW_SIGN_IDENTITY:--}"
APP="$OUT/FocusFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
SPARKLE_FRAMEWORKS=()
BIN_DIR=""

if [ "${FOCUSFLOW_UNIVERSAL:-0}" = 1 ]; then
    # `swift build --arch` for several architectures needs a full Xcode, so build each one and merge them.
    BIN_DIRS=()
    for arch in arm64 x86_64; do
        SCRATCH="$OUT/.swift-build-$arch"
        rm -rf "$SCRATCH"
        swift build -c release --scratch-path "$SCRATCH" --triple "$arch-apple-macosx14.0"
        BIN_DIRS+=("$(swift build -c release --scratch-path "$SCRATCH" --triple "$arch-apple-macosx14.0" --show-bin-path)")
    done
    for product in FocusFlow focusflow-mcp; do
        parts=()
        for bin_dir in "${BIN_DIRS[@]}"; do
            parts+=("$bin_dir/$product")
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
# The package copies the universal macOS slice into each product's bin directory.
if [ "${FOCUSFLOW_UNIVERSAL:-0}" = 1 ]; then
    SPARKLE="$OUT/.swift-build-arm64/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
else
    SPARKLE="$BIN_DIR/Sparkle.framework"
fi
[ -d "$SPARKLE" ] || { echo "Sparkle.framework not found at $SPARKLE" >&2; exit 1; }
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
RPATHS="$(otool -l "$APP/Contents/MacOS/FocusFlow" | awk '/LC_RPATH/{getline; getline; print $2}' | sort -u)"
while IFS= read -r rpath; do
    [ -n "$rpath" ] && [ "$rpath" != "/usr/lib/swift" ] && install_name_tool -delete_rpath "$rpath" "$APP/Contents/MacOS/FocusFlow" || true
done <<< "$RPATHS"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/FocusFlow"
if [ "${FOCUSFLOW_UNIVERSAL:-0}" = 1 ]; then
    lipo -archs "$APP/Contents/MacOS/FocusFlow" | grep -Eq 'arm64.*x86_64|x86_64.*arm64'
    lipo -archs "$FRAMEWORK/Versions/B/Sparkle" | grep -Eq 'arm64.*x86_64|x86_64.*arm64'
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
VERSION="${FOCUSFLOW_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
BUILD_NUMBER="${FOCUSFLOW_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
if [ -n "${FOCUSFLOW_SPARKLE_PUBLIC_KEY:-}" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $FOCUSFLOW_SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
fi
# What was built, for `focusflow status`. A "+" marks changes that are not committed.
COMMIT="$(git rev-parse --short=10 HEAD 2>/dev/null || echo unknown)"
[ -z "$(git status --porcelain 2>/dev/null)" ] || COMMIT="$COMMIT+"
/usr/libexec/PlistBuddy -c "Add :FocusFlowCommit string $COMMIT" \
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
if [ "$IDENTITY" != "-" ] || [ "${FOCUSFLOW_RUNTIME:-0}" = 1 ]; then
    # A real certificate keeps the signature the same across builds, so macOS keeps the granted permissions.
    SIGN+=(--options runtime --timestamp=none)
fi
# Sparkle embeds signed helpers; sign innermost code before the framework itself.
SPARKLE_VERSION="$FRAMEWORK/Versions/B"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE_VERSION/XPCServices/Downloader.xpc" >/dev/null
"${SIGN[@]}" "$SPARKLE_VERSION/XPCServices/Installer.xpc" >/dev/null
"${SIGN[@]}" "$SPARKLE_VERSION/Autoupdate" >/dev/null
"${SIGN[@]}" "$SPARKLE_VERSION/Updater.app" >/dev/null
"${SIGN[@]}" "$FRAMEWORK" >/dev/null
"${SIGN[@]}" "$APP/Contents/MacOS/focusflow-mcp" >/dev/null
"${SIGN[@]}" --entitlements Resources/FocusFlow.entitlements "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
for nested in "$SPARKLE_VERSION/XPCServices/Downloader.xpc" "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
              "$SPARKLE_VERSION/Autoupdate" "$SPARKLE_VERSION/Updater.app" "$FRAMEWORK"; do
    codesign -dvv "$nested" 2>&1 | grep -E '^(Authority|Signature)=' | head -1
done

echo "Gebaut: $APP"
echo "Starten mit: open $APP"
