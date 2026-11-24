#!/bin/bash
# One-time interactive setup for the public repository's release secrets.
set -euo pipefail

REPO="${1:-$(git config --get remote.origin.url | sed -E 's#^git@github.com:([^/]+/[^/.]+)(\.git)?$#\1#; s#^https://github.com/([^/]+/[^/.]+)(\.git)?$#\1#')}"
SPARKLE_BIN="${SPARKLE_BIN:-.build/artifacts/sparkle/Sparkle/bin}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/focusflow-release.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
umask 077

ask() { read -r -p "$1 [y/N] " answer; [[ "$answer" == y || "$answer" == Y ]]; }
if [ -z "$REPO" ]; then
    echo "Could not determine GitHub repository; pass owner/name as the first argument." >&2
    exit 1
fi
for tool in gh openssl security; do
    command -v "$tool" >/dev/null || { echo "$tool is required." >&2; exit 1; }
done
for tool in generate_keys; do
    [ -x "$SPARKLE_BIN/$tool" ] || { echo "$SPARKLE_BIN/$tool is required." >&2; exit 1; }
done

echo "This creates release credentials for $REPO."
echo "Back up the certificate and Sparkle private key: losing either means reinstalling or losing update signing."
ask "Continue?" || exit 0
read -r -p "Backup directory outside this repository (created 700): " BACKUP
[ -n "$BACKUP" ] || { echo "A backup directory is required." >&2; exit 1; }
case "$BACKUP" in "~") BACKUP="$HOME" ;; "~/"*) BACKUP="$HOME/${BACKUP#\~/}" ;; esac
mkdir -p "$BACKUP"
chmod 700 "$BACKUP"
REPO_ROOT="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
BACKUP="$(cd "$BACKUP" && pwd -P)"
case "$BACKUP/" in "$REPO_ROOT/"*)
    echo "Backup directory must be outside the repository." >&2; exit 1 ;;
esac
ask "Use $BACKUP for the certificate, password, and Sparkle private key backups?" || exit 0
ask "Inspect and configure GitHub Actions secrets?" || exit 0
EXISTING="$(gh secret list --env release --repo "$REPO" --json name --jq '.[].name')"
replace_group() {
    local names="$1"
    local found=0 name
    for name in $names; do
        if printf '%s\n' "$EXISTING" | grep -qx "$name"; then found=1; fi
    done
    if [ "$found" -eq 1 ]; then
        ask "One or more of $names already exist. Replace the complete group?"
    else
        ask "Store the complete group $names?"
    fi
}
REPLACE_CERT=0
replace_group "SIGNING_CERT_P12_BASE64 SIGNING_CERT_PASSWORD" && REPLACE_CERT=1
REPLACE_SPARKLE=0
replace_group "SPARKLE_PUBLIC_KEY SPARKLE_PRIVATE_KEY" && REPLACE_SPARKLE=1
if [ "$REPLACE_CERT" -eq 1 ]; then
    for file in "$BACKUP/FocusFlow-Developer.p12" "$BACKUP/FocusFlow-Developer.password"; do
        [ ! -e "$file" ] || { echo "Refusing to overwrite backup: $file" >&2; exit 1; }
    done
fi
if [ "$REPLACE_SPARKLE" -eq 1 ]; then
    [ ! -e "$BACKUP/Sparkle-private-key" ] ||
        { echo "Refusing to overwrite backup: $BACKUP/Sparkle-private-key" >&2; exit 1; }
fi

if [ "$REPLACE_CERT" -eq 1 ]; then
cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = FocusFlow Developer
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF
openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/cert.key" -out "$TMP/cert.crt"
P12_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
P12_FLAGS=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    P12_FLAGS=(-legacy)
fi
openssl pkcs12 -export ${P12_FLAGS[@]+"${P12_FLAGS[@]}"} -out "$TMP/cert.p12" \
    -inkey "$TMP/cert.key" -in "$TMP/cert.crt" -passout "pass:$P12_PASSWORD"
TEST_KEYCHAIN="$TMP/test.keychain-db"
security create-keychain -p "$P12_PASSWORD" "$TEST_KEYCHAIN" >/dev/null
trap 'security delete-keychain "$TEST_KEYCHAIN" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
security import "$TMP/cert.p12" -k "$TEST_KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security delete-keychain "$TEST_KEYCHAIN" >/dev/null
cp "$TMP/cert.p12" "$BACKUP/FocusFlow-Developer.p12"
printf '%s' "$P12_PASSWORD" > "$BACKUP/FocusFlow-Developer.password"
chmod 600 "$BACKUP/FocusFlow-Developer.p12" "$BACKUP/FocusFlow-Developer.password"
fi
if [ "$REPLACE_SPARKLE" -eq 1 ]; then
ask "Generate or look up Sparkle keys in the account focusflow-release?" || exit 0
"$SPARKLE_BIN/generate_keys" --account focusflow-release >/dev/null
PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account focusflow-release -p)"
"$SPARKLE_BIN/generate_keys" --account focusflow-release -x "$TMP/sparkle-private"
PRIVATE_KEY="$(cat "$TMP/sparkle-private")"
cp "$TMP/sparkle-private" "$BACKUP/Sparkle-private-key"
chmod 600 "$BACKUP/Sparkle-private-key"
fi
if [ "$REPLACE_CERT" -eq 1 ] || [ "$REPLACE_SPARKLE" -eq 1 ]; then
echo "Backups written to $BACKUP."
fi
ask "Continue to GitHub secret changes?" || exit 0

set_secret() {
    local name="$1" value="$2"
    printf '%s' "$value" | gh secret set "$name" --env release --repo "$REPO"
}
if [ "$REPLACE_CERT" -eq 1 ]; then
    set_secret SIGNING_CERT_P12_BASE64 "$(base64 < "$TMP/cert.p12" | tr -d '\n')"
    set_secret SIGNING_CERT_PASSWORD "$P12_PASSWORD"
fi
if [ "$REPLACE_SPARKLE" -eq 1 ]; then
    set_secret SPARKLE_PUBLIC_KEY "$PUBLIC_KEY"
    set_secret SPARKLE_PRIVATE_KEY "$PRIVATE_KEY"
fi
read -r -p "PostHog EU project key: " POSTHOG_KEY
[ -n "$POSTHOG_KEY" ] || { echo "A PostHog project key is required for the release workflow." >&2; exit 1; }
if printf '%s\n' "$EXISTING" | grep -qx POSTHOG_KEY; then
    ask "POSTHOG_KEY exists. Replace it?" && set_secret POSTHOG_KEY "$POSTHOG_KEY"
else
    ask "Store POSTHOG_KEY?" && set_secret POSTHOG_KEY "$POSTHOG_KEY"
fi
echo "Setup complete. Keep the backup directory offline and private."
