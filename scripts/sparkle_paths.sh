#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SPARKLE_BIN_DIR:-}" && -d "${SPARKLE_BIN_DIR}" ]]; then
  echo "${SPARKLE_BIN_DIR}"
  exit 0
fi

FOUND="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*SourcePackages/artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -n 1 || true)"

if [[ -z "${FOUND}" ]]; then
  echo ""
  exit 1
fi

echo "${FOUND}"
