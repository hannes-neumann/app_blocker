#!/bin/bash
# Generate a one-item Sparkle appcast for a ZIP in a temporary directory.
set -euo pipefail

ZIP="${1:?usage: make-appcast.sh ZIP VERSION BUILD_NUMBER PUBLIC_KEY PRIVATE_KEY}"
VERSION="${2:?missing version}"
BUILD_NUMBER="${3:?missing build number}"
PUBLIC_KEY="${4:?missing public key}"
PRIVATE_KEY_FILE="${5:-}"
OUT="${6:-$(dirname "$ZIP")/appcast.xml}"
SIGN_UPDATE="${SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"

[ -n "$PUBLIC_KEY" ] || { echo "missing public key" >&2; exit 1; }
if [ ! -x "$SIGN_UPDATE" ]; then
    echo "sign_update not found: $SIGN_UPDATE" >&2
    exit 1
fi
if [ "$PRIVATE_KEY_FILE" = "-" ]; then
    PRIVATE_KEY_FILE="$(mktemp "${TMPDIR:-/tmp}/focusflow-key.XXXXXX")"
    trap 'rm -f "$PRIVATE_KEY_FILE"' EXIT
    cat > "$PRIVATE_KEY_FILE"
fi
SIG="$("$SIGN_UPDATE" "$ZIP" --private-key-file "$PRIVATE_KEY_FILE")"
SIZE="$(stat -f %z "$ZIP")"
URL="${RELEASE_URL:-https://github.com/hannes-neumann/app_blocker/releases/latest/download/$(basename "$ZIP")}"
NOTES="${RELEASE_NOTES_FILE:-}"
if [ -n "$NOTES" ] && [ -f "$NOTES" ]; then
    NOTES_XML="$(cat "$NOTES" | sed 's/]]>/]]]]><![CDATA[>/g')"
else
    NOTES_XML="Release $VERSION"
fi
cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>FocusFlow</title>
    <item>
      <title>FocusFlow $VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_XML]]></description>
      <enclosure url="$URL" length="$SIZE" type="application/octet-stream" sparkle:edSignature="$SIG"/>
    </item>
  </channel>
</rss>
EOF
