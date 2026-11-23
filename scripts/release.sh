#!/bin/bash
# Builds a signed FocusFlow for Apple chips and Intel and packs it as DMG and ZIP in ./build/release.
#
# Needs a code signing certificate in the keychain, by default named "FocusFlow Developer" (see README → Weitergeben).
# Without Apple's paid developer account the app is not notarized, so the first launch needs a manual approval.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${FOCUSFLOW_SIGN_IDENTITY:-FocusFlow Developer}"
# "-" signs ad hoc: fine for a quick test, but macOS forgets granted permissions with every update.
# Self-signed certificates are not trusted by default, so look without -v (valid only).
if [ "$IDENTITY" != "-" ] && ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "Kein Zertifikat „$IDENTITY“ im Schlüsselbund gefunden." >&2
    echo "Anlegen: Schlüsselbundverwaltung → Zertifikatsassistent → Zertifikat erstellen…, Name „$IDENTITY“," >&2
    echo "Identitätstyp „Selbstsigniertes Stammzertifikat“, Zertifikatstyp „Codesignatur“." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
VERSION="${FOCUSFLOW_VERSION:-$VERSION}"
OUT=build/release
APP="$OUT/FocusFlow.app"
NAME="FocusFlow-$VERSION"

FOCUSFLOW_BUILD_DIR="$OUT" FOCUSFLOW_SIGN_IDENTITY="$IDENTITY" FOCUSFLOW_UNIVERSAL=1 scripts/build-app.sh
if [ -n "${FOCUSFLOW_VERSION:-}" ]; then
    ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
    [ "$ACTUAL_VERSION" = "$FOCUSFLOW_VERSION" ] ||
        { echo "build-app.sh produced version $ACTUAL_VERSION, expected $FOCUSFLOW_VERSION" >&2; exit 1; }
fi
codesign --verify --strict --verbose=1 "$APP"

rm -f "$OUT/$NAME.zip" "$OUT/$NAME.dmg"
ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/FocusFlowDMG.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/FocusFlow.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/INSTALL.txt "$STAGE/Zuerst lesen – Read me.txt"
hdiutil create -quiet -volname "FocusFlow $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT/$NAME.dmg"
codesign --force --sign "$IDENTITY" "$OUT/$NAME.dmg"

echo
echo "Architekturen: $(lipo -archs "$APP/Contents/MacOS/FocusFlow")"
echo "Signatur:      $(codesign -d -r- "$APP" 2>&1 | grep designated)"
echo
(cd "$OUT" && shasum -a 256 "$NAME.dmg" "$NAME.zip")
echo
echo "Fertig: $OUT/$NAME.dmg und $OUT/$NAME.zip"
