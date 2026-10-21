#!/bin/zsh
# Creates a long-lived self-signed code-signing identity for XClose releases.
#
# Why: without an Apple Developer ID, each build would otherwise be ad-hoc
# signed with a new identity, and macOS would drop the user's Accessibility
# permission after every update. Signing every release with the same
# certificate keeps the app's designated requirement stable across versions.
# (It does not remove Gatekeeper's "unidentified developer" warning; only a
# Developer ID and notarization do.)
#
# Usage: scripts/create-signing-identity.sh [output-dir]   (default ~/.xclose-release)
# Writes signing.p12 and signing.p12.password. Back both up; losing them means
# the next release gets a new identity and users must re-grant Accessibility.
set -euo pipefail

OUT="${1:-$HOME/.xclose-release}"
NAME="XClose Self-Signed Release"
mkdir -p "$OUT"
chmod 700 "$OUT"
[[ -e "$OUT/signing.p12" ]] && { echo "$OUT/signing.p12 already exists; refusing to overwrite."; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:3072 -nodes -days 7300 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
PASSWORD=$(openssl rand -base64 24)
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$OUT/signing.p12" -passout "pass:$PASSWORD"
print -r -- "$PASSWORD" > "$OUT/signing.p12.password"
chmod 600 "$OUT/signing.p12" "$OUT/signing.p12.password"

echo "Created $OUT/signing.p12 (valid 20 years)."
echo "For GitHub Actions, add repository secrets:"
echo "  SIGNING_P12_BASE64   = \$(base64 -i $OUT/signing.p12)"
echo "  SIGNING_P12_PASSWORD = \$(cat $OUT/signing.p12.password)"
