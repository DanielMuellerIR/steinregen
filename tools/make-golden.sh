#!/bin/bash
# Erzeugt die Vergleichsdaten des Spielkerns (golden/steinregen-golden.json) oder prüft, ob die
# eingecheckte Datei noch zum aktuellen Kern passt. Format und Aufbau: golden/README.md
#
# Nutzung:
#   bash tools/make-golden.sh            neu erzeugen (überschreibt die Datei)
#   bash tools/make-golden.sh --check    nur prüfen; Exit-Code 1 bei Abweichung
#
# Das Werkzeug hängt allein am Kern-Modul und braucht deshalb weder Xcode-Toolchain noch
# SpriteKit — die blanken CommandLineTools genügen.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="golden/steinregen-golden.json"

# Argumente ZUERST prüfen — ein Tippfehler soll nicht erst nach einem Build auffallen.
CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=1
    shift
fi
if [[ $# -gt 0 ]]; then
    echo "unbekannte Option: $1" >&2
    echo "Nutzung: bash tools/make-golden.sh [--check]" >&2
    exit 1
fi

swift build --product steinregen-golden

TOOL="$(swift build --product steinregen-golden --show-bin-path)/steinregen-golden"

if [[ "$CHECK_ONLY" == "1" ]]; then
    exec "$TOOL" --check "$OUT"
fi

mkdir -p golden
"$TOOL" --out "$OUT"

# Nach dem Schreiben sichtbar machen, was sich geändert hat: Die Datei ist der Prüfmaßstab der
# Portierung, ein unbemerkt verändertes Spielverhalten wäre hier genau der Fehler, den niemand
# sehen will.
if git rev-parse --git-dir >/dev/null 2>&1; then
    if ! git ls-files --error-unmatch "$OUT" >/dev/null 2>&1; then
        echo "Hinweis: $OUT ist noch nicht eingecheckt."
    elif git diff --quiet -- "$OUT" 2>/dev/null; then
        echo "unverändert gegenüber dem eingecheckten Stand."
    else
        echo
        echo "ACHTUNG: Die Vergleichsdaten haben sich geändert. Das heißt, der Spielkern verhält"
        echo "sich anders als zuvor. Den Unterschied prüfen, bevor er eingecheckt wird:"
        echo "  git diff --stat -- $OUT"
    fi
fi
