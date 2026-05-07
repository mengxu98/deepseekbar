#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "== Typecheck =="
mkdir -p .build/module-cache
swiftc -typecheck -module-cache-path .build/module-cache Sources/DeepSeekBar/*.swift

echo "== Shell syntax =="
bash -n build.sh

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
