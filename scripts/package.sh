#!/usr/bin/env bash
# Builds MacPulse.app and packages it for sharing as a .dmg and a .zip in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MacPulse"
APP="dist/${APP_NAME}.app"

./scripts/build-app.sh release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="dist/${APP_NAME}-${VERSION}.dmg"
ZIP="dist/${APP_NAME}-${VERSION}.zip"

echo "▸ Creating ${DMG}"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT
ditto --norsrc --noextattr "${APP}" "${STAGING}/${APP_NAME}.app"
ln -s /Applications "${STAGING}/Applications"
cp Resources/HOW-TO-OPEN.txt "${STAGING}/Como abrir - How to open.txt"
rm -f "${DMG}"
hdiutil create -quiet -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG}"

echo "▸ Creating ${ZIP}"
rm -f "${ZIP}"
ZIP_STAGING="${STAGING}/zip/${APP_NAME}"
mkdir -p "${ZIP_STAGING}"
ditto --norsrc --noextattr "${APP}" "${ZIP_STAGING}/${APP_NAME}.app"
cp Resources/HOW-TO-OPEN.txt "${ZIP_STAGING}/Como abrir - How to open.txt"
ditto -c -k --norsrc --noextattr --keepParent "${ZIP_STAGING}" "${ZIP}"

echo "✓ Ready to share:"
ls -lh "${DMG}" "${ZIP}" | awk '{print "  " $5 "  " $9}'
