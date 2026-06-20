#!/bin/bash
# Baut das App-Icon (tools/AppIcon.icns) aus den Stein-PNGs.
# Nutzung:  bash tools/make-icon.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
RES="Sources/SteinregenRender/Resources"
SWIFT="${DEVELOPER_DIR:+DEVELOPER_DIR=$DEVELOPER_DIR }xcrun swift"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MASTER="$TMP/icon_1024.png"

echo "==> Icon-Master rendern…"
xcrun swift tools/icon-compose.swift "$RES" "$MASTER"

echo "==> Iconset in allen Groessen…"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
gen() { sips -z "$2" "$2" "$MASTER" --out "$ICONSET/$1" >/dev/null; }
gen icon_16x16.png        16
gen icon_16x16@2x.png     32
gen icon_32x32.png        32
gen icon_32x32@2x.png     64
gen icon_128x128.png      128
gen icon_128x128@2x.png   256
gen icon_256x256.png      256
gen icon_256x256@2x.png   512
gen icon_512x512.png      512
gen icon_512x512@2x.png   1024

echo "==> iconutil → tools/AppIcon.icns…"
iconutil -c icns "$ICONSET" -o "tools/AppIcon.icns"
echo "Fertig: $ROOT/tools/AppIcon.icns"
