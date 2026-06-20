#!/bin/bash
# Baut aus dem SwiftPM-Release ein doppelklickbares macOS-App-Bundle mit Dock-Icon:
# dist/Steinregen.app  (+ dist/Steinregen-<version>.zip). Headless/CI-tauglich.
#
# Nutzung:  bash tools/make-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/Steinregen.app"
EXE_NAME="Steinregen"                              # = Produktname in Package.swift
RES_BUNDLE="Steinregen_SteinregenRender.bundle"
BUNDLE_ID="com.steinregen.app"
ICON="tools/AppIcon.icns"

echo "==> Release-Build (kann beim ersten Mal etwas dauern)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

# Icon erzeugen, falls noch nicht vorhanden.
if [ ! -f "$ICON" ]; then
    echo "==> App-Icon erzeugen…"
    bash tools/make-icon.sh
fi

echo "==> App-Bundle zusammenstellen ($APP, v$VERSION)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$EXE_NAME" "$APP/Contents/MacOS/$EXE_NAME"
cp -R "$BIN_DIR/$RES_BUNDLE" "$APP/Contents/Resources/$RES_BUNDLE"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Steinregen</string>
    <key>CFBundleDisplayName</key><string>Steinregen</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXE_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.puzzle-games</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc-Signatur (nötig auf Apple Silicon)…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    Signatur ok."

echo "==> ZIP für die Weitergabe…"
ZIP="dist/Steinregen-$VERSION.zip"
rm -f "$ZIP"
( cd dist && zip -qry "Steinregen-$VERSION.zip" "Steinregen.app" )

echo ""
echo "Fertig:"
echo "  $ROOT/$APP   (doppelklickbar)"
echo "  $ROOT/$ZIP"
