#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DeepSeekBar"
APP_VERSION="0.0.5"
BUILD_DIR=".build/release"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_STAGE="${BUILD_DIR}/dmg"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
ICON_SOURCE="Assets/${APP_NAME}.icon"
ICON_BUILD_DIR="${BUILD_DIR}/app-icon"

# UNIVERSAL=1 builds an arm64 + x86_64 binary (used by the release workflow).
# CODESIGN_IDENTITY overrides the signing identity ("-"/ad-hoc by default).
# NOTARYTOOL_PROFILE=<keychain profile> notarizes + staples before packing
# the DMG (requires a Developer ID Application signing identity).
UNIVERSAL="${UNIVERSAL:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

echo "=== Building ${APP_NAME} ${APP_VERSION} ==="

mkdir -p "${BUILD_DIR}/module-cache"
ARCH_FLAGS=(--arch arm64)
if [[ "${UNIVERSAL}" == "1" ]]; then
  echo "Building universal binary (arm64 + x86_64)"
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
PRODUCT_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
swift build -c release "${ARCH_FLAGS[@]}" -Xcc -fmodules-cache-path="${BUILD_DIR}/module-cache"
if [[ ! -x "${PRODUCT_DIR}/${APP_NAME}" ]]; then
  echo "Built binary not found under ${PRODUCT_DIR}" >&2
  exit 1
fi
echo "Using product at ${PRODUCT_DIR}"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${PRODUCT_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/"

# Copy bundled resources (menu-bar icon, .lproj strings) into
# Contents/Resources. Loaded via Bundle.main; no SwiftPM resource bundle
# needed (avoids launch-time "could not load resource bundle" in release
# builds).
RESOURCE_DIR="Sources/${APP_NAME}/Resources"
if [[ -d "${RESOURCE_DIR}" ]]; then
  cp -R "${RESOURCE_DIR}/." "${APP_DIR}/Contents/Resources/"
fi

rm -rf "${ICON_BUILD_DIR}"
mkdir -p "${ICON_BUILD_DIR}"
xcrun actool \
  --compile "${ICON_BUILD_DIR}" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon "${APP_NAME}" \
  --output-partial-info-plist "${ICON_BUILD_DIR}/partial.plist" \
  --warnings --errors \
  --output-format human-readable-text \
  "${ICON_SOURCE}"
cp "${ICON_BUILD_DIR}/Assets.car" "${APP_DIR}/Contents/Resources/"
cp "${ICON_BUILD_DIR}/${APP_NAME}.icns" "${APP_DIR}/Contents/Resources/"

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
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>DeepSeekBarGitHubLatestReleaseURL</key>
    <string>https://api.github.com/repos/mengxu98/deepseekbar/releases/latest</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DeepSeekBar</string>
    <key>CFBundleIconFile</key>
    <string>DeepSeekBar</string>
    <key>CFBundleIconName</key>
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
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
    echo "NOTARYTOOL_PROFILE requires a Developer ID Application identity." >&2
    exit 1
  fi
  codesign --force --deep --options runtime --timestamp --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
else
  codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"
fi

# Optional notarization: submit for approval, then staple the ticket onto
# the app before the DMG is packed, so Gatekeeper accepts it offline.
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  echo ""
  echo "=== Notarizing (profile: ${NOTARYTOOL_PROFILE}) ==="
  ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"
  rm -f "${ZIP_PATH}"
  ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
  xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
  xcrun stapler staple "${APP_DIR}"
  rm -f "${ZIP_PATH}"
fi

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
