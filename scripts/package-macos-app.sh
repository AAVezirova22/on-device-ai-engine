#!/usr/bin/env bash
set -euo pipefail

APP_NAME="On-Device AI Engine"
BUNDLE_ID="dev.local.ondeviceaiengine.hotkey"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

swift build -c release
VERSION="$(${PWD}/.build/release/edgeai version)"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp ".build/release/edgeai-hotkey" "${MACOS_DIR}/edgeai-hotkey"
chmod +x "${MACOS_DIR}/edgeai-hotkey"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>edgeai-hotkey</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Built for local, privacy-first AI workflows.</string>
</dict>
</plist>
PLIST

echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

test -x "${MACOS_DIR}/edgeai-hotkey"
test -f "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${CONTENTS_DIR}/Info.plist" >/dev/null

echo "Packaged app: ${APP_DIR}"
echo "To run: open \"${APP_DIR}\""
