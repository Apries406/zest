#!/bin/bash
# Imports ~/.zest-signing/zest-signing.p12 into a separate keychain
# (~/.zest-signing/zest.keychain-db) that `scripts/build-app.sh` uses automatically.
# Your login keychain and keychain search list are not changed.
set -euo pipefail

dir="$HOME/.zest-signing"
keychain="$dir/zest.keychain-db"
[ -f "$dir/zest-signing.p12" ] || { echo "Run scripts/create-signing-identity.sh first (or copy the backup to $dir)." >&2; exit 1; }

if [ ! -f "$keychain" ]; then
  openssl rand -base64 24 | tr -d '\n' > "$dir/keychain-password"
  chmod 600 "$dir/keychain-password"
  saved=$(security list-keychains -d user | tr -d '"')
  security create-keychain -p "$(cat "$dir/keychain-password")" "$keychain"
  # create-keychain adds the keychain to the search list; put the old list back.
  # shellcheck disable=SC2086
  security list-keychains -d user -s $saved
fi
password=$(cat "$dir/keychain-password")
security unlock-keychain -p "$password" "$keychain"
security set-keychain-settings "$keychain"  # never lock automatically
security import "$dir/zest-signing.p12" -k "$keychain" -P "$(cat "$dir/p12-password")" -T /usr/bin/codesign >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
openssl x509 -in "$dir/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d : > "$dir/identity"
echo "Ready. build-app.sh will sign with $(cat "$dir/identity")."
