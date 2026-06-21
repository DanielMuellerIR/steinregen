#!/bin/bash
# Holt die FreeDoom-Sound-Kandidaten zum Probehören nach assets/sound-candidates/ (gitignored).
# FreeDoom-SFX stehen unter BSD-3-Clause (eigene, freie Aufnahmen — nicht die kommerziellen
# Original-Doom-Sounds). Quelle: https://github.com/freedoom/freedoom (Ordner sounds/).
# Erst die FINALE Auswahl wandert später (mit Lizenz/Attribution) in Sources/.../Resources/.
#
# Nutzung:  bash tools/get-sound-candidates.sh   (danach: bash tools/audition-sounds.sh)
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/sound-candidates"
BASE="https://raw.githubusercontent.com/freedoom/freedoom/master/sounds"
mkdir -p "$DIR"

names=(
  dsswtchn dstink dsitemup            # Drehen
  dsstnmov dspstop dsoof dsdorcls     # Aufsetzen
  dsbarexp dsslop dsfirxpl dstelept   # Auflösen
  dspldeth dspdiehi                   # Game Over
  dsgetpow dswpnup                    # Level geschafft
)

ok=0
for n in "${names[@]}"; do
  if curl -fsSL -o "$DIR/$n.wav" "$BASE/$n.wav"; then ok=$((ok + 1)); else echo "fehlgeschlagen: $n"; fi
done
echo "Geladen: $ok/${#names[@]} nach $DIR"
echo "Probehören: bash tools/audition-sounds.sh   (oder: … -l  zum nur-Auflisten)"
