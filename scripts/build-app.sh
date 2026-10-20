#!/usr/bin/env bash
# Builds MacPulse.app into dist/. Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MacPulse"
CONFIG="${1:-release}"
APP="dist/${APP_NAME}.app"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "▸ Gerando ícone"
    swift scripts/make-icon.swift Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf Resources/AppIcon.iconset
fi

echo "▸ Compilando (${CONFIG})"
swift build -c "${CONFIG}"
BIN_DIR="$(swift build -c "${CONFIG}" --show-bin-path)"

echo "▸ Montando ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"

echo "▸ Assinando (ad-hoc)"
xattr -cr "${APP}"
codesign --force --deep --sign - "${APP}"

echo "✓ Pronto: ${APP}"
