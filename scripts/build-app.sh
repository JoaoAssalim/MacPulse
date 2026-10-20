#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) MacPulse.app into dist/.
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MacPulse"
CONFIG="${1:-release}"
APP="dist/${APP_NAME}.app"
ARCHS=(arm64 x86_64)

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "▸ Generating icon"
    swift scripts/make-icon.swift Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf Resources/AppIcon.iconset
fi

BINARIES=()
for arch in "${ARCHS[@]}"; do
    echo "▸ Building ${arch} (${CONFIG})"
    triple="${arch}-apple-macosx14.0"
    swift build -c "${CONFIG}" --triple "${triple}"
    BINARIES+=("$(swift build -c "${CONFIG}" --triple "${triple}" --show-bin-path)/${APP_NAME}")
done

# Assemble and sign outside the project folder: if it lives in iCloud Drive
# (e.g. ~/Desktop with "Desktop & Documents" sync), File Provider keeps adding
# extended attributes to the bundle and codesign rejects them.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
STAGED="${WORK}/${APP_NAME}.app"

echo "▸ Assembling ${APP}"
mkdir -p "${STAGED}/Contents/MacOS" "${STAGED}/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "${STAGED}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${STAGED}/Contents/Info.plist"
cp Resources/AppIcon.icns "${STAGED}/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad-hoc)"
xattr -cr "${STAGED}"
codesign --force --deep --sign - "${STAGED}"
codesign --verify --deep --strict "${STAGED}"

rm -rf "${APP}"
mkdir -p dist
ditto --norsrc --noextattr "${STAGED}" "${APP}"

echo "✓ Done: ${APP} ($(lipo -archs "${APP}/Contents/MacOS/${APP_NAME}"))"
