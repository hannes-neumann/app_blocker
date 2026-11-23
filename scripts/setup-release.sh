#!/bin/bash
# One-time interactive setup for the public repository's release secrets.
set -euo pipefail
REPO="${1:-$(git config --get remote.origin.url | sed -E 's#^git@github.com:([^/]+/[^/.]+)(\.git)?$#\1#; s#^https://github.com/([^/]+/[^/.]+)(\.git)?$#\1#')}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/focusflow-release.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
umask 077
if [ -z "$REPO" ]; then
    echo "Could not determine GitHub repository; pass owner/name as the first argument." >&2
    exit 1
fi

ask() { read -r -p "$1 [y/N] " answer; [[ "$answer" == y || "$answer" == Y ]]; }
if ! command -v gh >/dev/null || ! command -v openssl >/dev/null; then
    echo "gh and openssl are required." >&2; exit 1
fi
echo "This creates a self-signed certificate and Sparkle keys for $REPO."
echo "Back up the certificate and Sparkle private key: losing either means reinstalling or losing update signing."
ask "Continue?" || exit 0
ask "Inspect and configure GitHub Actions secrets?" || exit 0

openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
    -subj "/CN=FocusFlow Developer" -addext "extendedKeyUsage=codeSigning" \
    -keyout "$TMP/cert.key" -out "$TMP/cert.crt"
openssl pkcs12 -export -out "$TMP/cert.p12" -inkey "$TMP/cert.key" -in "$TMP/cert.crt" \
    -passout pass:
SPARKLE_BIN="${SPARKLE_BIN:-.build/artifacts/sparkle/Sparkle/bin}"
ask "Generate Sparkle EdDSA keys using $SPARKLE_BIN/generate_keys?" || exit 0
"$SPARKLE_BIN/generate_keys" -f "$TMP/keys"
PUBLIC_KEY="$(awk -F= '/public-key/ {print $2}' "$TMP/keys")"
PRIVATE_KEY="$(awk -F= '/private-key/ {print $2}' "$TMP/keys")"
read -r -p "PostHog EU project key (blank disables telemetry): " POSTHOG_KEY
for pair in \
    "SIGNING_CERT_P12_BASE64=$(base64 < "$TMP/cert.p12" | tr -d '\n')" \
    "SIGNING_CERT_PASSWORD=" \
    "SPARKLE_PUBLIC_KEY=$PUBLIC_KEY" \
    "SPARKLE_PRIVATE_KEY=$PRIVATE_KEY" \
    "POSTHOG_KEY=$POSTHOG_KEY"; do
    name="${pair%%=*}"; value="${pair#*=}"
    if gh secret list --repo "$REPO" --json name --jq '.[].name' | grep -qx "$name"; then
        ask "Secret $name exists. Replace it?" || continue
    else
        ask "Store secret $name?" || continue
    fi
    printf '%s' "$value" | gh secret set "$name" --repo "$REPO" --body -
done
echo "Setup complete. Store the generated certificate and Sparkle private key securely."
