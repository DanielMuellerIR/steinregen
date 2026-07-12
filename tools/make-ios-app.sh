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
# "Apple Development"-Zertifikat ableiten. WICHTIG: Die Team-ID ist die OU des Zertifikats,
# NICHT die Klammer im CN ("Apple Development: Name (XXXXXXXXXX)" — das ist die Member-/Zert-ID).
# Bleibt aus dem Repo raus (kontoidentifizierend). Fuer reine Simulator-Builds nicht noetig.
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | grep -oE 'OU *= *[A-Z0-9]{10}' | grep -oE '[A-Z0-9]{10}' | head -1 || true)"
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

# Geschweifte Klammern trennen den Variablennamen vom Unicode-Auslassungszeichen. Ohne sie
# interpretiert Bash bei aktiver UTF-8-Locale das Zeichen als Teil des Namens (`VERSION…`).
echo "==> Build (iOS-Simulator) v${VERSION}…"
xcodebuild -project "$PROJ" -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  build | tail -6

APP="$(/usr/bin/find "$DERIVED/Build/Products" -maxdepth 2 -name 'Steinregen.app' -type d 2>/dev/null | head -1)"
echo "    App-Bundle: $APP"

if [ "${1:-}" = "run" ]; then
  echo "==> Simulator '$SIM_NAME' headless booten…"
  # Die Gerätekennung steht als letztes, eingeklammertes Feld in der simctl-Zeile. `awk` entfernt
  # nur die Klammern; ein identifier-artiges Regex muss dadurch weder im Repo noch im Log stehen.
  DEVICE_ID="$(xcrun simctl list devices available | awk -v name="$SIM_NAME" '
    index($0, name " (") { value=$NF; gsub(/[()]/, "", value); print value; exit }
  ')"
  [ -n "$DEVICE_ID" ] || { echo "FEHLER: Simulator '$SIM_NAME' nicht gefunden"; exit 1; }
  xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
  xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1   # warten bis voll gebootet (sonst Install-Race)
  xcrun simctl install "$DEVICE_ID" "$APP"
  xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" || true
  echo "    Simulator gestartet · Bundle=$BUNDLE_ID"
  echo "    Screenshot: xcrun simctl io booted screenshot /tmp/steinregen-ios.png"
fi
echo "Fertig."
