#!/bin/bash
# Spielt die FreeDoom-Sound-Kandidaten zum Probehören ab (macOS `afplay`), mit Name + Vorschlag,
# wofür der Effekt im Spiel taugt. Die WAVs liegen gitignored in assets/sound-candidates/
# (geholt via tools/get-sound-candidates.sh).
#
# Nutzung:
#   bash tools/audition-sounds.sh            # alle der Reihe nach abspielen
#   bash tools/audition-sounds.sh dsbarexp   # nur einen abspielen
#   bash tools/audition-sounds.sh -l         # nur auflisten, nichts abspielen
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/sound-candidates"

# name|Verwendungsvorschlag — gruppiert nach Spiel-Event.
items=(
  "dsswtchn|Drehen (W/↑) — Schalter-Klick (dezent)"
  "dstink|Drehen — Tink (Alternative)"
  "dsitemup|Drehen/Level — kurzer Pickup-Blip (Alternative)"
  "dsstnmov|Aufsetzen — »stone move«, thematisch passend"
  "dspstop|Aufsetzen — Plattform-Clunk (Alternative)"
  "dsoof|Aufsetzen/Block — Grunt (Alternative)"
  "dsdorcls|Aufsetzen — Tür-Clunk (Alternative)"
  "dsbarexp|Auflösen — Explosion"
  "dsslop|Auflösen — Gib-Splat (blutig, Alternative)"
  "dsfirxpl|Auflösen — Feuer-Explosion (Alternative)"
  "dstelept|Auflösen/Level — Teleport-Whoosh (Alternative)"
  "dspldeth|Game Over — Todesschrei"
  "dspdiehi|Game Over — hoher Todesschrei (Alternative)"
  "dsgetpow|Level geschafft — Powerup"
  "dswpnup|Level geschafft — Waffe aufgenommen (Alternative)"
)

list_only=0
filter=""
case "${1:-}" in
  -l) list_only=1 ;;
  "") ;;
  *)  filter="$1" ;;
esac

play() {
  local name=$1
  local desc=$2
  local f="$DIR/$name.wav"
  if [ -f "$f" ]; then
    printf '▶ %-10s %s\n' "$name" "$desc"
    [ "$list_only" = 1 ] || afplay "$f"
  else
    printf '✗ %-10s (fehlt — erst tools/get-sound-candidates.sh laufen lassen)\n' "$name"
  fi
}

for it in "${items[@]}"; do
  n="${it%%|*}"
  d="${it#*|}"
  if [ -n "$filter" ] && [ "$n" != "$filter" ]; then continue; fi
  play "$n" "$d"
  if [ "$list_only" = 0 ] && [ -z "$filter" ]; then sleep 0.4; fi
done
