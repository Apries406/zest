#!/bin/bash
# One-time setup for maintainers: creates the self-signed certificate that signs
# zest releases. macOS ties the Accessibility permission to this certificate, so
# every release must be signed with the same one. Keep a backup of the folder!
#
# Writes ~/.zest-signing/{zest-signing.p12,p12-password,certificate.pem}.
# Then add two GitHub secrets (see docs/releasing.md):
#   ZEST_SIGNING_P12       base64 of zest-signing.p12
#   ZEST_SIGNING_PASSWORD  contents of p12-password
set -euo pipefail

dir="$HOME/.zest-signing"
if [ -e "$dir/zest-signing.p12" ]; then
  echo "$dir/zest-signing.p12 already exists; not overwriting it." >&2
  exit 1
fi
mkdir -p "$dir"
chmod 700 "$dir"
cd "$dir"

cat > cert.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = zest release signing
O = zest
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:3072 -keyout key.pem -out certificate.pem -days 7300 -nodes -config cert.cnf 2>/dev/null
openssl rand -base64 24 | tr -d '\n' > p12-password
# Legacy encryption: macOS `security import` cannot read OpenSSL 3's default PKCS#12.
openssl pkcs12 -export -out zest-signing.p12 -inkey key.pem -in certificate.pem \
  -passout file:p12-password -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
rm -f key.pem cert.cnf
chmod 600 ./*
echo "Created $dir/zest-signing.p12"
echo "SHA-1: $(openssl x509 -in certificate.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
echo "Back up $dir somewhere safe. Without it, users must reinstall zest by hand."
