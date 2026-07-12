#!/bin/bash
# Prüft die lokal und in CI beweisbaren Veröffentlichungsgates, ohne etwas zu veröffentlichen.
# Netzwerkabhängige Prüfungen (externe Links, Notarisierung, GitHub-Einstellungen) bleiben bewusst
# außerhalb dieses Skripts, damit CI reproduzierbar und frei von Kontodaten läuft.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "FEHLER: $*" >&2
    exit 1
}

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION_VALUE" ] || fail "VERSION ist leer."

# VERSION, Core-Konstante und Changelog müssen immer dieselbe veröffentlichbare Version nennen.
grep -qF "steinregenVersion = \"$VERSION_VALUE\"" Sources/SteinregenCore/Version.swift \
    || fail "VERSION und SteinregenCore/Version.swift sind nicht synchron."
grep -qF "## [$VERSION_VALUE]" CHANGELOG.md \
    || fail "CHANGELOG.md enthält keinen Abschnitt für $VERSION_VALUE."

# Diese Dateien werden im öffentlichen Repository oder im Release-Prozess direkt benötigt.
required_files=(
    LICENSE
    README.md
    README.de.md
    SECURITY.md
    THIRD-PARTY-ASSETS.md
    CHANGELOG.md
    assets/social-preview.png
    assets/dmg-background.png
    Sources/SteinregenRender/Resources/FREEDOOM-LICENSE.txt
    Sources/SteinregenRender/Resources/GrenzeGotisch-OFL.txt
)
for path in "${required_files[@]}"; do
    [ -s "$path" ] || fail "Pflichtdatei fehlt oder ist leer: $path"
done

# Beide verteilten App-Bundles müssen die eigene MIT-Lizenz und die Asset-Attribution mitführen.
grep -qF 'cp LICENSE "$APP/Contents/Resources/STEINREGEN-LICENSE.txt"' tools/make-app.sh \
    || fail "macOS-Bundle kopiert die MIT-Lizenz nicht."
grep -qF 'cp THIRD-PARTY-ASSETS.md "$APP/Contents/Resources/THIRD-PARTY-ASSETS.md"' tools/make-app.sh \
    || fail "macOS-Bundle kopiert die Asset-Attribution nicht."
grep -qF -- '- path: LICENSE' project.yml \
    || fail "iOS-Bundle enthält die MIT-Lizenz nicht."
grep -qF -- '- path: THIRD-PARTY-ASSETS.md' project.yml \
    || fail "iOS-Bundle enthält die Asset-Attribution nicht."

# GitHub empfiehlt 1280×640 Pixel. sips gehört zu macOS und ist auch auf dem CI-Runner vorhanden.
PREVIEW_WIDTH="$(sips -g pixelWidth assets/social-preview.png 2>/dev/null | awk '/pixelWidth:/ {print $2}')"
PREVIEW_HEIGHT="$(sips -g pixelHeight assets/social-preview.png 2>/dev/null | awk '/pixelHeight:/ {print $2}')"
[ "$PREVIEW_WIDTH" = "1280" ] && [ "$PREVIEW_HEIGHT" = "640" ] \
    || fail "Social Preview muss 1280×640 Pixel groß sein."
PREVIEW_BYTES="$(stat -f '%z' assets/social-preview.png)"
[ "$PREVIEW_BYTES" -lt 1000000 ] \
    || fail "Social Preview muss laut GitHub kleiner als 1 MB sein."

# MusicPlayer entdeckt eine lückenlose Folge. Eine fehlende Nummer würde alle späteren Titel
# unsichtbar machen, deshalb prüfen wir jede aktuell dokumentierte Datei einzeln.
for index in $(jot 13 1); do
    [ -s "Sources/SteinregenRender/Resources/musik-$index.mp3" ] \
        || fail "Musiktitel musik-$index.mp3 fehlt."
done
[ "$(find Sources/SteinregenRender/Resources -maxdepth 1 -name 'musik-*.mp3' | wc -l | tr -d ' ')" = "13" ] \
    || fail "Musikbestand und dokumentierte Anzahl 13 stimmen nicht überein."

# Öffentliche Dateien dürfen weder rechnergebundene Userpfade/private IPs noch eine persönliche
# Apple-Signing-Identität enthalten. Historische Commits werden separat mit gitleaks geprüft.
if git grep -n -I -E '(/Users/|192\.168\.|Daniel Mueller|9QSWKSR4NQ)' -- . \
        ':!tools/check-release-readiness.sh' >/dev/null; then
    fail "Öffentliche Dateien enthalten persönliche oder rechnergebundene Strings."
fi

# Relative Markdown-Links und Bildquellen müssen auf vorhandene Dateien bzw. Überschriften zeigen.
python3 - <<'PY'
from pathlib import Path
import re
import sys
from urllib.parse import unquote

documents = [Path("README.md"), Path("README.de.md"), Path("THIRD-PARTY-ASSETS.md")]
problems: list[str] = []

def anchors(text: str) -> set[str]:
    result: set[str] = set()
    for line in text.splitlines():
        if not line.startswith("#"):
            continue
        heading = line.lstrip("#").strip().lower()
        anchor = re.sub(r"[^a-z0-9äöüß -]", "", heading)
        # GitHub entfernt Satzzeichen, ersetzt aber jedes Leerzeichen einzeln. Dadurch wird
        # "Build & Run" zu "build--run" (zwei Leerzeichen nach dem entfernten &).
        anchor = anchor.replace(" ", "-")
        result.add(anchor)
    return result

for document in documents:
    text = document.read_text(encoding="utf-8")
    own_anchors = anchors(text)
    # Erfasst Markdown-Links sowie die src-Attribute der drei README-Screenshots.
    targets = re.findall(r"\[[^]]*]\(([^)]+)\)", text)
    targets += re.findall(r'src="([^"]+)"', text)
    for raw_target in targets:
        target = unquote(raw_target.split()[0].strip("<>"))
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        if target.startswith("#"):
            if target[1:] not in own_anchors:
                problems.append(f"{document}: unbekannter Anker {target}")
            continue
        path_part, _, anchor = target.partition("#")
        resolved = (document.parent / path_part).resolve()
        if not resolved.exists():
            problems.append(f"{document}: fehlendes Ziel {path_part}")
        elif anchor and resolved.suffix.lower() == ".md":
            target_anchors = anchors(resolved.read_text(encoding="utf-8"))
            if anchor not in target_anchors:
                problems.append(f"{document}: unbekannter Anker #{anchor} in {path_part}")

if problems:
    print("\n".join(problems), file=sys.stderr)
    raise SystemExit(1)
PY

# Syntaxfehler in einem Release-Skript sollen vor einem teuren Build auffallen.
bash -n tools/*.sh
git diff --check

# Bash kann bei UTF-8-Locale ein direkt folgendes Unicode-Zeichen dem Variablennamen zurechnen.
# Solche Stellen müssen `${NAME}` verwenden, sonst bricht `set -u` erst im seltenen Build-Pfad ab.
python3 - <<'PY'
from pathlib import Path
import re

problems: list[str] = []
for path in Path("tools").glob("*.sh"):
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if re.search(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]", line):
            problems.append(f"{path}:{line_number}: Unicode direkt hinter unklammerter Variable")
if problems:
    raise SystemExit("\n".join(problems))
PY

# Wenn gitleaks lokal oder in einer gehärteten CI installiert ist, prüfen wir die gesamte
# erreichbare Historie. --redact verhindert, dass ein Fund als Klartext im Terminal landet.
if command -v gitleaks >/dev/null 2>&1; then
    # Auch Diagnoseausgaben können Remote-Adressen enthalten. Deshalb bleibt der vollständige
    # Scanner-Output aus dem Sitzungs-/CI-Protokoll; bei einem Fund genügt die sichere Fehlermeldung.
    if ! gitleaks git --no-banner --redact=100 . >/dev/null 2>&1; then
        fail "gitleaks hat einen möglichen Secret-Fund gemeldet; lokal mit redigierter Ausgabe prüfen."
    fi
else
    echo "HINWEIS: gitleaks fehlt; Historien-Secret-Scan übersprungen."
fi

echo "Veröffentlichungs-Gates lokal grün (Version $VERSION_VALUE)."
