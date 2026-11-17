#!/bin/bash
# Runs the zsh integration test (Tests/zsh/integration.zsh) against `zest serve`.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
swift build --product zest >/dev/null
bin=$(swift build --show-bin-path)
# Unix socket paths are limited to 104 bytes, so use a short folder.
dir=$(mktemp -d /tmp/zest-test.XXXXXX)
socket="$dir/s"
ZEST_RESOURCES="$root" "$bin/zest" serve --socket "$socket" --specs "$root/Tests/zsh/specs" > "$dir/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$dir"' EXIT
for _ in $(seq 50); do [ -S "$socket" ] && break; sleep 0.1; done
zsh -f "$root/Tests/zsh/integration.zsh" "$bin/zest" "$socket" "$root"
zsh -fi "$root/Tests/zsh/menu-safety.zsh" "$root" "$dir/injected"
