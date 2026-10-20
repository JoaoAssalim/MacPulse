#!/usr/bin/env bash
# Captures fresh screenshots of every tab (personal details masked) and
# regenerates the README images in docs/images/.
set -euo pipefail
cd "$(dirname "$0")/.."

SHOTS="$(mktemp -d)"
trap 'rm -rf "${SHOTS}"' EXIT

echo "▸ Building debug app"
swift build

echo "▸ Capturing screenshots (the app opens and closes by itself)"
MACPULSE_SNAPSHOT_DIR="${SHOTS}" "$(swift build --show-bin-path)/MacPulse"

echo "▸ Composing images"
swift scripts/docs-images.swift "${SHOTS}" docs/images
sips -s format png -Z 256 Resources/AppIcon.icns --out docs/images/icon.png >/dev/null

echo "✓ docs/images updated"
