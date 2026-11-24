#!/bin/bash
# Generate and verify a one-item Sparkle appcast without writing the private key.
set -euo pipefail

ZIP="${1:?usage: make-appcast.sh ZIP VERSION BUILD_NUMBER PUBLIC_KEY - [OUT]}"
VERSION="${2:?missing version}"
BUILD_NUMBER="${3:?missing build number}"
PUBLIC_KEY="${4:?missing public key}"
KEY_SOURCE="${5:?missing key source}"
OUT="${6:-$(dirname "$ZIP")/appcast.xml}"
SIGN_UPDATE="${SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
[ "$KEY_SOURCE" = "-" ] || { echo "The private key must be read from stdin (-)." >&2; exit 1; }
[ -n "$PUBLIC_KEY" ] || { echo "missing public key" >&2; exit 1; }
[ -x "$SIGN_UPDATE" ] || { echo "sign_update not found: $SIGN_UPDATE" >&2; exit 1; }

KEY="$(cat)"
[ -n "$KEY" ] || { echo "empty private key" >&2; exit 1; }
# Sparkle's exported new-format key is a base64-encoded 32-byte Ed25519 seed.
# Derive its public half in a pipe so the private key is never written to disk.
DERIVED_PUBLIC="$(
    {
        printf 302e020100300506032b657004220420 | xxd -r -p
        if base64 --decode </dev/null >/dev/null 2>&1; then
            printf '%s' "$KEY" | base64 --decode
        else
            printf '%s' "$KEY" | base64 -D
        fi
    } | openssl pkey -inform DER -pubout -outform DER 2>/dev/null |
        tail -c 32 | base64 | tr -d '\n'
)" || { echo "invalid Ed25519 private seed" >&2; exit 1; }
[ "$DERIVED_PUBLIC" = "$PUBLIC_KEY" ] || { echo "private key does not match public key" >&2; exit 1; }
SIG="$(printf '%s' "$KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP")"
[ -n "$SIG" ] || { echo "sign_update returned no signature" >&2; exit 1; }
printf '%s' "$KEY" | "$SIGN_UPDATE" --ed-key-file - --verify "$ZIP" "$SIG" >/dev/null

SIZE="$(stat -f %z "$ZIP")"
URL="${RELEASE_URL:-https://github.com/hannes-neumann/app_blocker/releases/latest/download/$(basename "$ZIP")}"
NOTES="${RELEASE_NOTES_FILE:-}"
[ -f "$NOTES" ] || { echo "release notes file is required" >&2; exit 1; }
NOTES_XML="$(awk -v version="$VERSION" '
    $0 == "## " version { found=1; next }
    found && /^## / { exit }
    found { print }
    END { if (!found) exit 2 }
' "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g")" || {
    echo "CHANGELOG has no ## $VERSION section" >&2; exit 1;
}
ESCAPE="$(printf '%s' "$URL" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
SIG_ESC="$(printf '%s' "$SIG" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
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
      <description sparkle:format="markdown">$NOTES_XML</description>
      <enclosure url="$ESCAPE" length="$SIZE" type="application/octet-stream" sparkle:edSignature="$SIG_ESC"/>
    </item>
  </channel>
</rss>
EOF
