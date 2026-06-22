#!/bin/bash
# Baut die iPhone-App (Steinregen iOS) fuer den iOS-Simulator.
#
# SwiftPM allein kann kein iOS-App-Bundle erzeugen → wir generieren mit xcodegen aus project.yml
# ein Xcode-Projekt (git-ignoriert, reproduzierbar) und bauen es mit xcodebuild. Headless/CI-tauglich.
#
# Nutzung:
#   bash tools/make-ios-app.sh           # nur bauen (Simulator-SDK)
#   bash tools/make-ios-app.sh run       # bauen + headless im Simulator installieren + starten
#
# Simulator waehlbar ueber STEINREGEN_SIM (Default: "iPhone 17").
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
# Volles Xcode (nicht die CommandLineTools) — sonst fehlt das iOS-SDK.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="$(tr -d '[:space:]' < VERSION)"
SCHEME="Steinregen"
PROJ="Steinregen.xcodeproj"
DERIVED="build/ios"
BUNDLE_ID="com.steinregen.app"
SIM_NAME="${STEINREGEN_SIM:-iPhone 17}"

command -v xcodegen >/dev/null || { echo "FEHLER: xcodegen fehlt (brew install xcodegen)"; exit 1; }

# Development-Team fuer Geraete-Signing: aus der Umgebung, sonst aus dem lokalen
# "Apple Development"-Zertifikat ableiten (Team-ID = Klammerwert). Bleibt aus dem Repo raus
# (kontoidentifizierend). Fuer reine Simulator-Builds nicht noetig (leer = ok).
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 'Apple Development' | grep -oE '\([A-Z0-9]{10}\)' | tr -d '()' || true)"
fi
export DEVELOPMENT_TEAM
if [ -n "$DEVELOPMENT_TEAM" ]; then
  echo "==> Development-Team aus Zertifikat/Umgebung übernommen (Geräte-Signing aktiv)."
else
  echo "==> Kein Development-Team gefunden — Simulator-Build ok, echtes Gerät braucht eins."
fi

# iOS-App-Icon (Pentagramm, full-bleed/deckend) reproduzierbar erzeugen, falls noch nicht da
# (git-ignoriert, wie tools/AppIcon.icns bei der macOS-App).
ICON_PNG="iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
if [ ! -f "$ICON_PNG" ]; then
  echo "==> iOS-App-Icon rendern…"
  xcrun swift tools/icon-compose.swift "Sources/SteinregenRender/Resources" "$ICON_PNG" ios >/dev/null
fi

echo "==> Xcode-Projekt aus project.yml erzeugen…"
xcodegen generate >/dev/null

echo "==> Build (iOS-Simulator) v$VERSION…"
xcodebuild -project "$PROJ" -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  build | tail -6

APP="$(/usr/bin/find "$DERIVED/Build/Products" -maxdepth 2 -name 'Steinregen.app' -type d 2>/dev/null | head -1)"
echo "    App-Bundle: $APP"

if [ "${1:-}" = "run" ]; then
  echo "==> Simulator '$SIM_NAME' headless booten…"
  UDID="$(xcrun simctl list devices available | grep -m1 "$SIM_NAME (" | sed -E 's/.*\(([0-9A-Fa-f-]+)\).*/\1/')"
  [ -n "$UDID" ] || { echo "FEHLER: Simulator '$SIM_NAME' nicht gefunden"; exit 1; }
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1   # warten bis voll gebootet (sonst Install-Race)
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$BUNDLE_ID" || true
  echo "    UDID=$UDID  Bundle=$BUNDLE_ID"
  echo "    Screenshot:  xcrun simctl io $UDID screenshot /tmp/steinregen-ios.png"
fi
echo "Fertig."
