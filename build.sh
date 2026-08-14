#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DeepSeekBar"
APP_VERSION="0.0.3"
BUILD_DIR=".build/release"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_STAGE="${BUILD_DIR}/dmg"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
ICON_SOURCE="Assets/AppIconSource.png"
ICONSET_DIR="${BUILD_DIR}/${APP_NAME}.iconset"
ICNS_PATH="${BUILD_DIR}/${APP_NAME}.icns"

echo "=== Building ${APP_NAME} ==="

mkdir -p "${BUILD_DIR}/module-cache"
swift build -c release --arch arm64 --scratch-path .build -Xcc -fmodules-cache-path="${BUILD_DIR}/module-cache"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"

# Copy SwiftPM resource bundle (bundled logo etc.)
BUNDLE_SOURCE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "${BUNDLE_SOURCE}" ]]; then
  cp -R "${BUNDLE_SOURCE}" "${APP_DIR}/Contents/Resources/"
fi

if [[ -f "${ICON_SOURCE}" ]]; then
  rm -rf "${ICONSET_DIR}"
  mkdir -p "${ICONSET_DIR}"
  sips -z 16 16     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"
  cp "${ICNS_PATH}" "${APP_DIR}/Contents/Resources/${APP_NAME}.icns"
else
  echo "Warning: ${ICON_SOURCE} not found; building without a custom app icon."
fi

cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DeepSeekBar</string>
    <key>CFBundleDisplayName</key>
    <string>DeepSeekBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.deepseekbar.app</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>DeepSeekBarGitHubLatestReleaseURL</key>
    <string>https://api.github.com/repos/mengxu98/deepseekbar/releases/latest</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DeepSeekBar</string>
    <key>CFBundleIconFile</key>
    <string>DeepSeekBar</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --remove-signature "${APP_DIR}" 2>/dev/null || true
codesign --force --deep --sign - "${APP_DIR}"

echo ""
echo "=== Creating DMG ==="
rm -rf "${DMG_STAGE}"
rm -f "${DMG_PATH}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_DIR}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGE}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo ""
echo "=== Packaging complete ==="
echo "App: ${APP_DIR}"
echo "DMG: ${DMG_PATH}"
