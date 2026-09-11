#!/bin/bash
# build.sh — einheitlicher Einstieg zum Bauen (Daniels Regel vom 2026-09-11:
# jedes Projekt hat build.sh, install.sh und release.sh an der Repo-Wurzel).
#
# Baut nur: keine Notarisierung, keine Installation, ad-hoc-Signatur wie bisher
# (SIGN_ID setzt eine echte Identität, SKIP_ZIP=1 lässt das ZIP weg — genau so
# rufen tools/make-notarized.sh und tools/make-dmg.sh den Bauschritt auf). Die
# eigentliche Arbeit macht tools/make-app.sh, das seinen Ort wegen Doku und
# Aufrufern behält; Argumente und Umgebungsvariablen gehen unverändert durch,
# der Exit-Code ist der von make-app.sh (exec ersetzt diesen Prozess).
#
# Aufruf:  ./build.sh
# Letzte Zeile bei Erfolg: BUILD OK: <pfad>/dist/Steinregen.app
set -euo pipefail
cd "$(dirname "$0")"
exec bash tools/make-app.sh "$@"
