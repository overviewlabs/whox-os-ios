#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f '/WHOX OS/Apple Developer/environment.sh' ]]; then
  # shellcheck disable=SC1091
  source '/WHOX OS/Apple Developer/environment.sh'
fi

cd "$ROOT"
swiftc -frontend -parse iOS/WHOXOS/*.swift
swift test

echo 'WHOX OS iOS verification passed.'
