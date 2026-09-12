#!/bin/bash
# release.sh — Release-DMG bauen: App bauen, signieren, notarisieren, DMG packen
# und notarisieren.
#
# Die drei Einstiegspunkte des Projekts trennen bewusst:
#   ./build.sh               baut die App nach dist/, mehr nicht (Unterbau: tools/make-app.sh)
#   ./install.sh             baut, notarisiert und installiert nach /Applications
#   ./release.sh             baut, notarisiert und packt das DMG — installiert NIE
#
# Die eigentliche Arbeit macht tools/make-dmg.sh; dieses Skript ist der
# einheitliche Einstiegspunkt nach dem projektübergreifenden Schema und reicht
# alle Argumente durch (z. B. --publish).
#
# Wichtig ist die doppelte Notarisierung: Erst bekommt die App ihr eigenes
# Ticket angeheftet, dann das fertige DMG. Nur so startet die App auch dann
# sauber, wenn jemand sie aus dem Image herauszieht — ein Ticket allein am DMG
# reicht dafür nicht.
#
# Voraussetzungen:
#   - "Developer ID Application"-Zertifikat im Schlüsselbund
#   - NOTARY_PROFILE oder `git config steinregen.notaryProfile`
#
# Aufruf:
#   ./release.sh                 # vollständiger Release-Lauf, DMG bleibt lokal
#   ./release.sh --publish       # zusätzlich Tag + GitHub-Release (nur nach Auftrag)
#   ./release.sh --no-notarize   # unsigniertes Test-DMG, nur zum Layout-Test
set -euo pipefail
cd "$(dirname "$0")"

exec bash tools/make-dmg.sh "$@"
