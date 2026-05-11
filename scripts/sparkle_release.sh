#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# Load local secrets/config when present
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
fi

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  echo "Usage: scripts/sparkle_release.sh <version> [build]" >&2
  exit 1
fi

BUILD_NUMBER="${2:-$(date +%Y%m%d%H%M)}"
SCHEME="stasis-release"
ARCHIVE_PATH="${ROOT_DIR}/build/Stasis.xcarchive"
EXPORT_PATH="${ROOT_DIR}/build/export"
APP_PATH="${EXPORT_PATH}/Stasis.app"
ZIP_PATH="${ROOT_DIR}/build/Stasis-${VERSION}.zip"
APPCAST_DIR="${ROOT_DIR}/releases/appcast"
NOTES_FILE="${ROOT_DIR}/releases/notes/${VERSION}.html"
APPCAST_OUT="${APPCAST_DIR}/appcast.xml"

SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$(${ROOT_DIR}/scripts/sparkle_paths.sh)}"
: "${SPARKLE_PRIVATE_KEY_PATH:?Set SPARKLE_PRIVATE_KEY_PATH to your private key file path}"
: "${SPARKLE_DOWNLOAD_BASE_URL:?Set SPARKLE_DOWNLOAD_BASE_URL, e.g. https://example.com/stasis/downloads}"

if [[ ! -x "${SPARKLE_BIN_DIR}/generate_appcast" ]]; then
  echo "Sparkle generate_appcast not found in: ${SPARKLE_BIN_DIR}" >&2
  exit 1
fi
if [[ ! -x "${SPARKLE_BIN_DIR}/sign_update" ]]; then
  echo "Sparkle sign_update not found in: ${SPARKLE_BIN_DIR}" >&2
  exit 1
fi

sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = ${VERSION};/" stasis.xcodeproj/project.pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/" stasis.xcodeproj/project.pbxproj

rm -rf "${ROOT_DIR}/build"
mkdir -p "${EXPORT_PATH}"

xcodebuild archive \
  -project stasis.xcodeproj \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist exportOptions.plist

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Exported app not found at ${APP_PATH}" >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

"${SPARKLE_BIN_DIR}/sign_update" "${ZIP_PATH}" -f "${SPARKLE_PRIVATE_KEY_PATH}"

mkdir -p "${APPCAST_DIR}"
if [[ ! -f "${NOTES_FILE}" ]]; then
  cat > "${NOTES_FILE}" <<HTML
<!doctype html>
<html><body><h1>Stasis ${VERSION}</h1><p>Release notes coming soon.</p></body></html>
HTML
fi

"${SPARKLE_BIN_DIR}/generate_appcast" \
  --ed-key-file "${SPARKLE_PRIVATE_KEY_PATH}" \
  --download-url-prefix "${SPARKLE_DOWNLOAD_BASE_URL}" \
  --link "${SPARKLE_DOWNLOAD_BASE_URL}/../notes/${VERSION}.html" \
  --versions "${VERSION}" \
  --maximum-versions 25 \
  "${ROOT_DIR}/build" > "${APPCAST_OUT}"

echo "Created: ${ZIP_PATH}"
echo "Created: ${APPCAST_OUT}"
echo "Notes:   ${NOTES_FILE}"
