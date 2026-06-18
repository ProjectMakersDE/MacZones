#!/usr/bin/env bash
#
# Creates a stable, self-signed code-signing certificate for MacZones and stores
# it (plus its password) as GitHub Actions secrets, so every CI build is signed
# with the SAME identity. That keeps the macOS Accessibility permission across
# updates (TCC keys the grant on the signing identity, not on the binary hash).
#
# Requirements: openssl, gh (authenticated with access to the repo).
# Re-running rotates the certificate — after that, the permission must be granted
# once more (then it persists again).
#
# Usage: scripts/create-signing-cert.sh [owner/repo]
#
set -euo pipefail

REPO="${1:-ProjectMakersDE/MacZones}"
IDENTITY="MacZones Self-Signed"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CERT_PWD="$(openssl rand -hex 16)"

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

echo "==> Generating self-signed code-signing certificate ($IDENTITY)"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/openssl.cnf" 2>/dev/null

# -legacy keeps the PKCS#12 readable by macOS `security import`.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -name "$IDENTITY" -passout pass:"$CERT_PWD" 2>/dev/null || \
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -name "$IDENTITY" -passout pass:"$CERT_PWD" 2>/dev/null

echo "   SHA-1: $(openssl x509 -in "$TMP/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2)"

echo "==> Storing GitHub secrets in $REPO"
base64 < "$TMP/cert.p12" | gh secret set SIGNING_CERTIFICATE_P12_BASE64 --repo "$REPO"
gh secret set SIGNING_CERTIFICATE_PASSWORD --repo "$REPO" --body "$CERT_PWD"

echo "==> Done. Secrets set:"
gh secret list --repo "$REPO"
