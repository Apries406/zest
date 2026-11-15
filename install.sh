#!/bin/sh
# Installs zest from the latest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/rostik32/zest/main/install.sh | sh
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/rostik32/zest/main/install.sh | sh -s -- --uninstall
set -eu

repo="rostik32/zest"
app_dir="/Applications"
[ -w "$app_dir" ] || app_dir="$HOME/Applications"
app="$app_dir/Zest.app"
support="$HOME/Library/Application Support/zest"

say() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

quit_app() {
  osascript -e 'tell application id "io.github.rostik32.zest" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Zest >/dev/null 2>&1 || true
}

cli_dir() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) echo "$HOME/.local/bin" ;;
    *) if [ -w /usr/local/bin ]; then echo /usr/local/bin; else echo "$HOME/.local/bin"; fi ;;
  esac
}

if [ "${1:-}" = "--uninstall" ]; then
  say "Quitting zest"
  quit_app
  zshrc="${ZDOTDIR:-$HOME}/.zshrc"
  if [ -f "$zshrc" ] && grep -q '# >>> zest >>>' "$zshrc"; then
    say "Removing zest from $zshrc"
    sed -i '' '/# >>> zest >>>/,/# <<< zest <<</d' "$zshrc"
  fi
  rm -rf "/Applications/Zest.app" "$HOME/Applications/Zest.app" "$support"
  for d in "$HOME/.local/bin" /usr/local/bin; do
    [ -L "$d/zest" ] && rm -f "$d/zest"
  done
  say "zest is uninstalled. Your own specs in ~/.config/zest were kept."
  exit 0
fi

[ "$(uname -s)" = Darwin ] || fail "zest runs on macOS only."
[ "$(uname -m)" = arm64 ] || fail "zest needs a Mac with Apple silicon."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "zest needs macOS 14 Sonoma or later."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
url="https://github.com/$repo/releases/latest/download"

say "Downloading zest"
curl -fsSL "$url/Zest.zip" -o "$tmp/Zest.zip"
curl -fsSL "$url/Zest.zip.sha256" -o "$tmp/Zest.zip.sha256"
expected=$(cut -d' ' -f1 "$tmp/Zest.zip.sha256")
actual=$(shasum -a 256 "$tmp/Zest.zip" | cut -d' ' -f1)
[ "$expected" = "$actual" ] || fail "checksum mismatch; the download is damaged."

say "Installing to $app"
quit_app
mkdir -p "$app_dir"
rm -rf "$app"
ditto -x -k "$tmp/Zest.zip" "$app_dir"

bin=$(cli_dir)
mkdir -p "$bin"
ln -sf "$app/Contents/Helpers/zest" "$bin/zest"
say "Linked the zest command to $bin/zest"

open "$app"
say "zest is running in the menu bar. Follow its setup, then open a new terminal window."
