#!/bin/bash
# Downloads the icon sets zest uses and writes them to assets/icons.
#   Material Icon Theme (MIT)  — file, folder and tool icons
#   Codicons (CC BY 4.0)       — subcommand, option and argument icons
# Usage: scripts/update-icons.sh
set -euo pipefail

MATERIAL_VERSION=5.40.0
CODICONS_VERSION=0.0.36

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cd "$work"
npm pack --silent "material-icon-theme@$MATERIAL_VERSION" "@vscode/codicons@$CODICONS_VERSION" >/dev/null
mkdir material codicons
tar -xzf material-icon-theme-*.tgz -C material
tar -xzf vscode-codicons-*.tgz -C codicons

out="$root/assets/icons"
mkdir -p "$out/material"
find "$out/material" -name '*.svg' -delete
node "$root/scripts/material-index.mjs" "$work/material/package" "$out"
cp "$work/material/package/LICENSE" "$out/material/LICENSE.txt"

cp "$work/codicons/package/dist/codicon.ttf" "$out/codicon.ttf"
# Only the few glyphs the popup uses: name → code point.
node -e '
  const fs = require("fs");
  const pick = new Set(["symbol-method", "symbol-property", "symbol-variable", "symbol-enum-member", "symbol-field",
    "symbol-key", "history", "terminal", "arrow-right", "loading", "sparkle"]);
  const out = {};
  for (const line of fs.readFileSync(process.argv[1], "utf8").split("\n").slice(1)) {
    const [name, , code] = line.split(",");
    if (pick.has(name)) out[name] = code.trim();
  }
  fs.writeFileSync(process.argv[2], JSON.stringify(out, null, 2) + "\n");
' "$work/codicons/package/dist/codicon.csv" "$out/codicons.json"
cp "$work/codicons/package/LICENSE" "$out/CODICONS-LICENSE.txt" 2>/dev/null || true
echo "Icons updated in $out"
