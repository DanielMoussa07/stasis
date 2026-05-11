#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$(${ROOT_DIR}/scripts/sparkle_paths.sh)}"

if [[ ! -x "${SPARKLE_BIN_DIR}/generate_keys" ]]; then
  echo "Sparkle generate_keys not found in: ${SPARKLE_BIN_DIR}" >&2
  exit 1
fi

mkdir -p "${ROOT_DIR}/releases/keys"
KEY_FILE="${ROOT_DIR}/releases/keys/sparkle_private_key"

if [[ -f "${KEY_FILE}" ]]; then
  echo "Key already exists at ${KEY_FILE}. Refusing to overwrite." >&2
  exit 1
fi

# 1) Create keypair in login keychain (prints SUPublicEDKey guidance)
"${SPARKLE_BIN_DIR}/generate_keys"

# 2) Export private key from keychain to file for CI/local signing
"${SPARKLE_BIN_DIR}/generate_keys" -x "${KEY_FILE}"

chmod 600 "${KEY_FILE}"

echo
echo "Private key saved to: ${KEY_FILE}"
echo "Public key is printed above by Sparkle."
echo "Set it in Xcode build setting: INFOPLIST_KEY_SUPublicEDKey"
