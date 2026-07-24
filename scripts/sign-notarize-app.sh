#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-dist/On-Device AI Engine.app}"
ZIP_PATH="${APP_PATH%.app}.zip"

required_env=(
  "DEVELOPER_ID_APPLICATION"
  "APPLE_ID"
  "APPLE_TEAM_ID"
  "APP_SPECIFIC_PASSWORD"
)

for name in "${required_env[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 2
  fi
done

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found: ${APP_PATH}" >&2
  echo "Run scripts/package-macos-app.sh first." >&2
  exit 2
fi

codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  "${APP_PATH}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}" || true

ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

xcrun notarytool submit "${ZIP_PATH}" \
  --apple-id "${APPLE_ID}" \
  --team-id "${APPLE_TEAM_ID}" \
  --password "${APP_SPECIFIC_PASSWORD}" \
  --wait

xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

echo "Signed and notarized: ${APP_PATH}"
