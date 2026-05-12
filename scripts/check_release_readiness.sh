#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "== Typecheck =="
mkdir -p .build/module-cache
swiftc -typecheck -module-cache-path .build/module-cache Sources/DeepSeekBar/*.swift

echo "== Shell syntax =="
bash -n build.sh
bash -n scripts/tag_release.sh

echo "== Release version =="
build_version="$(awk -F'"' '/^APP_VERSION=/ { print $2; exit }' build.sh)"
if [[ -z "${build_version}" ]]; then
  echo "APP_VERSION is missing from build.sh" >&2
  exit 1
fi
if [[ ! "${build_version}" =~ ^[0-9]+(\.[0-9]+)*([-+][A-Za-z0-9.-]+)?$ ]]; then
  echo "Invalid APP_VERSION in build.sh: ${build_version}" >&2
  exit 1
fi
if [[ -f .build/release/DeepSeekBar.app/Contents/Info.plist ]]; then
  plist_version="$(plutil -extract CFBundleShortVersionString raw .build/release/DeepSeekBar.app/Contents/Info.plist)"
  if [[ "${plist_version}" != "${build_version}" ]]; then
    echo "Built app version ${plist_version} does not match build.sh APP_VERSION ${build_version}" >&2
    exit 1
  fi
fi
if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" != "v${build_version}" ]]; then
  echo "Release tag ${GITHUB_REF_NAME} does not match build.sh APP_VERSION ${build_version}" >&2
  exit 1
fi

echo "== Release files =="
test -f README.md
test -f LICENSE
test -f .github/workflows/release.yml
test -f Package.swift
test -f Assets/AppIconSource.png
sips -g pixelWidth -g pixelHeight Assets/AppIconSource.png | grep -q "pixelWidth: 1024"
sips -g pixelWidth -g pixelHeight Assets/AppIconSource.png | grep -q "pixelHeight: 1024"

echo "== Code signature =="
codesign --verify --deep --strict --verbose=2 .build/release/DeepSeekBar.app

echo "== DMG =="
if [[ -f .build/release/DeepSeekBar.dmg ]]; then
  ls -lh .build/release/DeepSeekBar.dmg
else
  echo "DMG not found. Run ./build.sh before publishing." >&2
  exit 1
fi

echo "Release readiness checks passed."
