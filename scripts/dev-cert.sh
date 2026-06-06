#!/usr/bin/env bash
# Create a stable self-signed code-signing identity so dockja's Accessibility
# grant survives rebuilds. Run once. See bundle.sh for how it's used.
set -euo pipefail

NAME="${1:-dockja-dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Code-signing identity '$NAME' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $NAME
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:

# -A lets codesign use the key without a per-use prompt.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "" -A

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "OK: '$NAME' is ready. Rebuild with ./scripts/bundle.sh"
else
    echo
    echo "NOTE: '$NAME' did not register as a valid signing identity (likely untrusted)."
    echo "Create it via the GUI instead (reliable, ~5 clicks):"
    echo "  Keychain Access -> Certificate Assistant -> Create a Certificate"
    echo "    Name:            $NAME"
    echo "    Identity Type:   Self Signed Root"
    echo "    Certificate Type: Code Signing"
fi
