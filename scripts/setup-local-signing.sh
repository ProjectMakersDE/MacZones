#!/usr/bin/env bash
#
# One-time setup of a stable self-signed code-signing identity that is shared by
# local builds AND GitHub CI, so the macOS Accessibility permission persists
# across local rebuilds and updates alike.
#
# It creates a dedicated, persistent keychain (~/Library/Keychains/
# maczones-signing.keychain-db), imports a freshly generated self-signed
# certificate, and (unless SET_SECRETS=0) stores the same certificate as the
# repo secrets SIGNING_CERTIFICATE_P12_BASE64 / SIGNING_CERTIFICATE_PASSWORD so
# CI signs with the identical identity.
#
# Re-running rotates the certificate (you then grant the permission once more).
#
# Usage: scripts/setup-local-signing.sh [owner/repo]
#        SET_SECRETS=0 scripts/setup-local-signing.sh   # skip updating CI secrets
#
set -euo pipefail

IDENTITY="MacZones Self-Signed"
REPO="${1:-ProjectMakersDE/MacZones}"
SET_SECRETS="${SET_SECRETS:-1}"

KC="$HOME/Library/Keychains/maczones-signing.keychain-db"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
CONF_DIR="$HOME/.config/maczones"
PW_FILE="$CONF_DIR/signing-keychain.pw"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Generating self-signed code-signing certificate ($IDENTITY)"
cat > "$TMP/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = MacZones Self-Signed
O = ProjectMakers
C = DE
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/openssl.cnf" 2>/dev/null

P12PWD="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -name "$IDENTITY" -passout pass:"$P12PWD" 2>/dev/null || \
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -name "$IDENTITY" -passout pass:"$P12PWD" 2>/dev/null

echo "==> Creating dedicated signing keychain"
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
KCPWD="$(openssl rand -hex 16)"
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPWD" "$KC"
security set-keychain-settings "$KC"                 # no auto-lock timeout
security unlock-keychain -p "$KCPWD" "$KC"
security import "$TMP/cert.p12" -k "$KC" -P "$P12PWD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPWD" "$KC" >/dev/null

# Add the signing keychain to the user search list ALONGSIDE the login keychain.
# Explicit paths only (never parse/sed the existing list — that once corrupted it).
security list-keychains -d user -s "$KC" "$LOGIN_KC"

printf '%s' "$KCPWD" > "$PW_FILE"; chmod 600 "$PW_FILE"
echo "   keychain: $KC"
echo "   password stored at: $PW_FILE"

if [ "$SET_SECRETS" = "1" ] && command -v gh >/dev/null 2>&1; then
    echo "==> Updating GitHub secrets in $REPO (so CI uses the same identity)"
    base64 < "$TMP/cert.p12" | gh secret set SIGNING_CERTIFICATE_P12_BASE64 --repo "$REPO"
    gh secret set SIGNING_CERTIFICATE_PASSWORD --repo "$REPO" --body "$P12PWD"
fi

echo "==> Done. cert SHA-1: $(openssl x509 -in "$TMP/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2)"
echo "    Now run: scripts/install-local.sh <version>"
