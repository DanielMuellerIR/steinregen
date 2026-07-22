#!/bin/bash
# Baut aus dem SwiftPM-Release ein doppelklickbares macOS-App-Bundle mit Dock-Icon:
# dist/Steinregen.app  (+ dist/Steinregen-<version>.zip). Headless/CI-tauglich.
#
# Nutzung:  bash tools/make-app.sh
#
# Optionale Umgebungsvariablen (Default = bisheriges Verhalten: ad-hoc-Signatur + ZIP):
#   SIGN_ID    Signing-Identität. Leer = Ad-hoc-Signatur (nur lokal lauffähig). Gesetzt (z.B.
#              "Developer ID Application: …") = echte Signatur MIT Hardened Runtime + Zeitstempel
#              (Pflicht für Notarisierung). Wird von tools/make-notarized.sh genutzt.
#   SKIP_SIGN   "1" = Bundle für einen lokalen Build-Nachweis gar nicht signieren. Nie für
#              Distribution/Notarisierung verwenden; mit SIGN_ID absichtlich unvereinbar.
#   SKIP_ZIP   "1" = das abschließende ZIP überspringen (die notarisierte Variante zippt selbst
#              erst NACH dem Stapeln). Sonst wird wie bisher dist/Steinregen-<version>.zip gebaut.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/Steinregen.app"
EXE_NAME="Steinregen"                              # = Produktname in Package.swift
RES_BUNDLE="Steinregen_SteinregenRender.bundle"
BUNDLE_ID="com.steinregen.app"
ICON="tools/AppIcon.icns"

if [ "${SKIP_SIGN:-0}" = "1" ] && [ -n "${SIGN_ID:-}" ]; then
    echo "FEHLER: SKIP_SIGN=1 und SIGN_ID dürfen nicht kombiniert werden."
    exit 2
fi

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
# Auch Binärkopien müssen die eigene MIT-Lizenz und die vollständige Asset-Attribution begleiten.
# Die Dritt-Lizenzen für Freedoom und Grenze Gotisch stecken bereits im Ressourcen-Bundle.
cp LICENSE "$APP/Contents/Resources/STEINREGEN-LICENSE.txt"
cp THIRD-PARTY-ASSETS.md "$APP/Contents/Resources/THIRD-PARTY-ASSETS.md"
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

if [ "${SKIP_SIGN:-0}" = "1" ]; then
    echo "==> Signatur bewusst übersprungen (nur lokaler Build-Nachweis)."
elif [ -n "${SIGN_ID:-}" ]; then
    # Echte Signatur mit Hardened Runtime (--options runtime) + Zeitstempel (--timestamp).
    # Beides ist Pflicht für die Notarisierung; KEIN --deep (Apple rät davon ab, und das Bundle
    # hat ohnehin nur EINE Mach-O-Datei — die Haupt-Binary; das Ressourcen-Bundle ist reiner Inhalt).
    # Klammern verhindern, dass Bash das folgende Unicode-Zeichen dem Variablennamen zurechnet.
    echo "==> Signatur mit »${SIGN_ID}« (Hardened Runtime)…"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP" && echo "    Signatur ok."
else
    echo "==> Ad-hoc-Signatur (nötig auf Apple Silicon)…"
    codesign --force --deep --sign - "$APP"
    codesign --verify --deep --strict "$APP" && echo "    Signatur ok."
fi

if [ "${SKIP_ZIP:-0}" = "1" ]; then
    echo "==> ZIP übersprungen (SKIP_ZIP=1)."
    echo ""
    echo "Fertig:"
    echo "  $ROOT/$APP   (doppelklickbar)"
else
    echo "==> ZIP für die Weitergabe…"
    ZIP="dist/Steinregen-$VERSION.zip"
    rm -f "$ZIP"
    ( cd dist && zip -qry "Steinregen-$VERSION.zip" "Steinregen.app" )

    echo ""
    echo "Fertig:"
    echo "  $ROOT/$APP   (doppelklickbar)"
    echo "  $ROOT/$ZIP"
fi
