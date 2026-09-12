#!/bin/bash
# install.sh — Steinregen notarisiert nach /Applications installieren.
#
# Die drei Einstiegspunkte des Projekts trennen bewusst:
#   ./build.sh               baut die App nach dist/, mehr nicht (Unterbau: tools/make-app.sh)
#   ./install.sh             baut, notarisiert und installiert nach /Applications
#   ./release.sh             baut, notarisiert und packt das DMG — installiert nie
#
# Die eigentliche Bau- und Notarisierungsarbeit macht tools/make-notarized.sh;
# dieses Skript ergänzt nur die Installation.
#
# Warum notarisiert: In /Applications gehören nur Bundles mit angeheftetem
# Notary-Ticket, die Gatekeeper akzeptiert. Ein ad-hoc signierter Testbuild
# bleibt in dist/.
#
# Voraussetzungen:
#   - "Developer ID Application"-Zertifikat im Schlüsselbund
#   - NOTARY_PROFILE oder `git config steinregen.notaryProfile`
#
# Aufruf:  ./install.sh
# Letzte Zeile bei Erfolg: INSTALL OK: /Applications/Steinregen.app (<version>)
set -euo pipefail
cd "$(dirname "$0")"
APP="dist/Steinregen.app"
DESTINATION="/Applications/Steinregen.app"
VERSION="$(tr -d '[:space:]' < VERSION)"

echo "=== 1/2 Bauen, signieren, notarisieren ==="
bash tools/make-notarized.sh

echo "=== 2/2 Installieren ==="
# Ohne angeheftetes Ticket nichts nach /Applications — make-notarized.sh sollte
# das erledigt haben, aber belegt ist es erst durch die Prüfung.
xcrun stapler validate "$APP"

# Erst neben das Ziel legen, dann atomar austauschen: ein Abbruch mittendrin
# darf keine halb ersetzte App in /Applications hinterlassen.
STAGED="/Applications/.Steinregen.app.install-$$"
rm -rf "$STAGED"
trap 'rm -rf "$STAGED"' EXIT
ditto "$APP" "$STAGED"

# Gatekeeper-Bewertung VOR dem Austausch: Wird erst danach geprüft, ist eine funktionierende
# Installation bereits durch ein abgelehntes Bundle ersetzt. Bewertet wird genau die gestagte
# Kopie, die gleich ins Ziel wandert; die fehlende .app-Endung stört spctl nicht (geprüft).
# Ausgabe erst sammeln, dann anzeigen — sonst liefert die Pipeline nur den Status von tail.
if ! SPCTL_STAGED_OUT="$(spctl -a -t exec -vv "$STAGED" 2>&1)"; then
    printf '%s\n' "$SPCTL_STAGED_OUT" | tail -2
    echo "FEHLER: Gatekeeper lehnt das gebaute Bundle ab; $DESTINATION bleibt unverändert." >&2
    exit 1
fi
printf '%s\n' "$SPCTL_STAGED_OUT" | tail -2

pkill -x Steinregen 2>/dev/null || true
/usr/bin/swift - "$STAGED" "$DESTINATION" <<'SWIFT'
import Foundation

let fileManager = FileManager.default
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
if fileManager.fileExists(atPath: destination.path) {
    _ = try fileManager.replaceItemAt(
        destination,
        withItemAt: source,
        backupItemName: nil,
        options: [.usingNewMetadataOnly]
    )
} else {
    try fileManager.moveItem(at: source, to: destination)
}
SWIFT
trap - EXIT

# Nach dem Kopieren erneut prüfen: erst dann ist die Installation belegt.
xcrun stapler validate "$DESTINATION"
spctl -a -t exec -vv "$DESTINATION" 2>&1 | tail -2

echo "INSTALL OK: $DESTINATION ($VERSION)"
