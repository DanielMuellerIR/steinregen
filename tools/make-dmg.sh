#!/bin/bash
# tools/make-dmg.sh — baut ein verteilbares macOS-DMG für Steinregen:
#   Steinregen.app (Developer-ID-signiert, Hardened Runtime) IN einem DMG mit Hintergrundbild,
#   Applications-Shortcut und festen Icon-Positionen; das DMG wird signiert, notarisiert und
#   gestapelt → öffnet auf jedem Mac per Doppelklick ohne Gatekeeper-Warnung.
#   Ergebnis: dist/Steinregen-<version>.dmg — Testläufe: dist/Steinregen-<version>-test.dmg
#
# Nutzung:
#   bash tools/make-dmg.sh                  # signiert + notarisiert (braucht Zertifikat + Notar-Profil)
#   bash tools/make-dmg.sh --no-notarize    # ad-hoc, UNSIGNIERT — nur zum lokalen Layout-Test
#   bash tools/make-dmg.sh --no-finder-layout   # ohne Finder-Fensterlayout (headless, kein Release)
#   (beide Testmodi schreiben nach dist/Steinregen-<version>-test.dmg und lassen ein fertiges
#    Release-DMG derselben Version unangetastet)
#   bash tools/make-dmg.sh --publish        # zusätzlich: Tag vX.Y.Z + GitHub-Release mit dem DMG
#
# Voraussetzungen fürs Signieren/Notarisieren (einmalig je Mac — Schlüsselbund wird NICHT gesynct):
#   1) Developer-ID-Application-Zertifikat in der Login-Keychain
#        security find-identity -v -p codesigning
#   2) notarytool-Keychain-Profil (Name beim Aufruf über NOTARY_PROFILE angeben)
#        xcrun notarytool store-credentials profile-name --apple-id apple-id@example.com --team-id TEAMID1234
#
# Überschreibbar per Umgebungsvariablen:
#   SIGN_ID         Optional: Signing-Identität. Ohne Wert wird die erste Developer-ID-
#                   Application-Identität aus dem lokalen Schlüsselbund verwendet.
#   NOTARY_PROFILE  notarytool-Keychain-Profil (beim Notarisieren Pflicht).
#   GITHUB_REPO     GitHub-Repository in der Form owner/name (bei --publish Pflicht).
#   GITHUB_REMOTE   git-Remote-Name fürs Tag-Pushen bei --publish (Default: github).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

APP="dist/Steinregen.app"
VOLNAME="Steinregen"
BACKGROUND="assets/dmg-background.png"
DMG="dist/Steinregen-$VERSION.dmg"
RW_DMG="dist/Steinregen-$VERSION-rw.dmg"
SIGN_ID="${SIGN_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# --- Argumente ---
NOTARIZE=1
PUBLISH=0
FINDER_LAYOUT=1
for arg in "$@"; do
    case "$arg" in
        --no-notarize)      NOTARIZE=0 ;;
        --publish)          PUBLISH=1 ;;
        --no-finder-layout) FINDER_LAYOUT=0 ;;
        *) echo "Unbekanntes Argument: $arg"; exit 2 ;;
    esac
done
if [ "$PUBLISH" = "1" ] && [ "$NOTARIZE" = "0" ]; then
    echo "FEHLER: --publish setzt eine signierte+notarisierte App voraus (nicht mit --no-notarize kombinierbar)."
    exit 2
fi
# Ohne Finder-Layout fehlen dem DMG Icon-Positionen und Hintergrundbild (siehe Kommentar beim
# Layout-Schritt weiter unten). Ein solches Image ist ein Testartefakt und kein Release.
if [ "$PUBLISH" = "1" ] && [ "$FINDER_LAYOUT" = "0" ]; then
    echo "FEHLER: --publish braucht das Finder-Layout (nicht mit --no-finder-layout kombinierbar)."
    echo "        Ohne Layout fehlen Icon-Positionen und Hintergrundbild — das ist kein Release-DMG."
    exit 2
fi
if [ "$NOTARIZE" = "1" ] && [ -z "$NOTARY_PROFILE" ]; then
    echo "FEHLER: NOTARY_PROFILE muss für die Notarisierung gesetzt sein."
    echo "        Beispiel: NOTARY_PROFILE=profil-name bash tools/make-dmg.sh"
    exit 2
fi
# Ein Testlauf bekommt einen EIGENEN Dateinamen. Sonst überschreibt ein unsigniertes oder
# layout-loses Testimage das fertige, geprüfte Release-DMG derselben Version, und im Ausgabeordner
# läge unter dem Weitergabenamen ein ausdrücklich nicht veröffentlichbares Artefakt.
# --publish setzt NOTARIZE=1 und FINDER_LAYOUT=1 voraus (siehe oben) und trifft diesen Fall nie.
if [ "$NOTARIZE" = "0" ] || [ "$FINDER_LAYOUT" = "0" ]; then
    DMG="dist/Steinregen-$VERSION-test.dmg"
    RW_DMG="dist/Steinregen-$VERSION-test-rw.dmg"
    echo "==> Testlauf: Das Ergebnis heißt $DMG und ist kein Release."
fi
# Veröffentlichungsvoraussetzungen VOR dem langen Build prüfen. Diese Abfragen verändern weder
# Git noch GitHub. Diagnoseausgaben der Netzwerkwerkzeuge bleiben unterdrückt, damit Remote- oder
# Kontodaten nicht versehentlich im Terminalprotokoll landen.
if [ "$PUBLISH" = "1" ]; then
    bash tools/github-release.sh preflight
fi

if [ ! -f "$BACKGROUND" ]; then
    echo "FEHLER: DMG-Hintergrund fehlt: $BACKGROUND"
    echo "        Erzeugen:  swift tools/generate-dmg-background.swift $BACKGROUND"
    exit 1
fi

# --- 1) App bauen (+ ggf. mit Developer ID signieren) --------------------------------------
if [ "$NOTARIZE" = "1" ]; then
    # Vorab-Checks: lieber jetzt scheitern als nach dem langen Build.
    # (Ausgabe erst in eine Variable, dann per Here-String greppen — siehe make-notarized.sh:
    #  "befehl | grep -q" stirbt sonst an SIGPIPE und pipefail wertet es als Fehler.)
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    if [ -z "$SIGN_ID" ]; then
        # Zertifikatsnamen sind öffentlich; der private Signing-Key verlässt die Keychain nie.
        SIGN_ID="$(sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' <<<"$IDENTITIES" | sed -n '1p')"
    fi
    if [ -z "$SIGN_ID" ]; then
        echo "FEHLER: Keine Developer-ID-Application-Identität in der Keychain gefunden."
        echo "        (Zum reinen Layout-Test: bash tools/make-dmg.sh --no-notarize)"
        exit 1
    fi
    if ! grep -qF "$SIGN_ID" <<<"$IDENTITIES"; then
        echo "FEHLER: Signing-Identität nicht in der Keychain gefunden: »${SIGN_ID}«"
        echo "        Vorhandene:"; sed 's/^/          /' <<<"$IDENTITIES"
        echo "        (Zum reinen Layout-Test ohne Zertifikat: bash tools/make-dmg.sh --no-notarize)"
        exit 1
    fi
    # Fünf Versuche statt einem: `notarytool history` meldet gelegentlich
    # fälschlich „No Keychain password item found", obwohl das Profil da ist
    # (2026-07-26 auf M3 belegt). Ein einzelner Fehlversuch würde sonst einen
    # ganzen Lauf grundlos abbrechen; ein wirklich fehlendes Profil scheitert
    # auch nach fünf Versuchen.
    notary_profile_works() {
        local attempt
        for attempt in 1 2 3 4 5; do
            xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 && return 0
            sleep 3
        done
        return 1
    }
    if ! notary_profile_works; then
        echo "FEHLER: notarytool-Profil »${NOTARY_PROFILE}« fehlt oder ist ungültig."
        echo "        Anlegen:  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id apple-id@example.com --team-id TEAMID1234"
        exit 1
    fi
    echo "==> Bauen + Developer-ID-Signatur…"
    SIGN_ID="$SIGN_ID" SKIP_ZIP=1 bash tools/make-app.sh
    # Hardened Runtime gegenprüfen — ohne lehnt die Notarisierung ab.
    CODESIGN_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
    grep -q "flags=.*runtime" <<<"$CODESIGN_INFO" \
        && echo "    Hardened Runtime aktiv." \
        || { echo "FEHLER: Hardened Runtime nicht gesetzt — Notarisierung würde abgelehnt."; exit 1; }

    # Die APP bekommt ihr eigenes Ticket — vor dem DMG-Bau, damit hdiutil es
    # mitkopiert. Sonst hat, wer die App aus dem Image herauszieht, ein Bundle
    # ohne Ticket: Das DMG-Ticket reist nicht mit. (notarytool nimmt kein
    # nacktes .app, deshalb der Umweg über ein ZIP.)
    echo "==> App notarisieren (Profil $NOTARY_PROFILE) — kann ein paar Minuten dauern…"
    APP_ZIP="dist/Steinregen-$VERSION-submit.zip"
    rm -f "$APP_ZIP"
    ditto -c -k --keepParent "$APP" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$APP_ZIP"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    # Harte Bewertung statt bloßer Anzeige: Eine von Gatekeeper abgelehnte App darf gar nicht
    # erst ins DMG wandern und mit --publish veröffentlicht werden. Die Ausgabe wird erst
    # gesammelt und dann eingerückt gezeigt — `befehl | sed` würde den Fehlerstatus verschlucken.
    if ! SPCTL_APP_OUT="$(spctl --assess --type execute -vvv "$APP" 2>&1)"; then
        sed 's/^/    /' <<<"$SPCTL_APP_OUT"
        echo "FEHLER: Gatekeeper lehnt die notarisierte App ab — Abbruch vor dem DMG-Bau."
        exit 1
    fi
    sed 's/^/    /' <<<"$SPCTL_APP_OUT"
else
    echo "==> Bauen (ad-hoc, UNSIGNIERT — nur Layout-Test)…"
    SKIP_ZIP=1 bash tools/make-app.sh
fi

# --- 2) DMG-Layout (schreibbares HFS+ → mounten → Inhalt rein → Finder-Ansicht) -------------
echo "==> Erzeuge DMG-Layout…"
MOUNT_DIR="/Volumes/$VOLNAME"

# Ein bereits vorhandenes Volume gleichen Namens wird NICHT blind ausgeworfen. Früher stand hier
# ein `hdiutil detach -force` auf jeden Mountpunkt dieses Namens — das kann ein FREMDES Disk-Image
# treffen, in das gerade jemand schreibt. Ausgehängt wird nur noch ein Rest dieses Skripts, also
# ein Image, dessen Datei genau unser eigenes RW-DMG ist.
image_behind_mount() {      # $1 = Mountpunkt; Ausgabe: Pfad der Image-Datei (leer = kein Image)
    # `hdiutil info` listet je Image erst `image-path`, danach seine Geräte; in deren Zeilen steht
    # der Mountpunkt als letztes Feld. Also den zuletzt gesehenen Pfad merken und beim Treffer
    # ausgeben.
    hdiutil info | awk -v mount="$1" '
        /^image-path[[:space:]]*:/ {
            path = $0
            sub(/^image-path[[:space:]]*:[[:space:]]*/, "", path)
        }
        $NF == mount { print path; exit }
    '
}
if [ -d "$MOUNT_DIR" ]; then
    MOUNTED_IMAGE="$(image_behind_mount "$MOUNT_DIR")"
    # `-ef` vergleicht die Datei selbst (Gerät + Inode), nicht ihre Schreibweise — ein Symlink im
    # Pfad führt so nicht zu einem falschen Nein.
    if [ -n "$MOUNTED_IMAGE" ] && [ "$MOUNTED_IMAGE" -ef "$ROOT/$RW_DMG" ]; then
        echo "    (Rest eines früheren Laufs wird ausgehängt: $MOUNT_DIR)"
        hdiutil detach "$MOUNT_DIR" -force >/dev/null
    else
        echo "FEHLER: $MOUNT_DIR ist belegt und gehört nicht zu diesem Build."
        echo "        Das kann ein fremdes Disk-Image sein, in das gerade geschrieben wird;"
        echo "        zwangsweise ausgehängt wird es deshalb nicht."
        echo "        Bitte selbst auswerfen und den Lauf wiederholen."
        exit 1
    fi
fi

rm -f "$DMG" "$RW_DMG"

SIZE=$(( $(du -sm "$APP" | cut -f1) + 40 ))
hdiutil create -srcfolder "$APP" -volname "$VOLNAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size "${SIZE}m" "$RW_DMG"

# Das eigene Gerät merken und per `trap` genau dieses wieder aushängen — auch wenn das Skript
# zwischendrin abbricht. Ohne das bliebe nach einem Fehlschlag ein gemountetes Volume zurück,
# und genau daraus entstand die Versuchung, beim nächsten Lauf blind zu detachen.
ATTACH_OUT="$(hdiutil attach "$ROOT/$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -noverify -noautoopen)"
printf '%s\n' "$ATTACH_OUT"
DEVICE="$(awk 'NR == 1 { print $1; exit }' <<<"$ATTACH_OUT")"   # z. B. /dev/disk4
if [ -z "$DEVICE" ]; then
    echo "FEHLER: hdiutil attach hat kein Gerät gemeldet."
    exit 1
fi
trap 'hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true' EXIT

ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND" "$MOUNT_DIR/.background/background.png"
chflags hidden "$MOUNT_DIR/.background"

# Finder-Ansicht setzen. Fenster-Innenmaß 600×400 = Hintergrundbild-Größe; Icon-Positionen
# müssen zu generate-dmg-background.swift passen (App 150,180 · Applications 450,180).
# --no-finder-layout überspringt diesen Schritt: Er öffnet ein echtes
# Finder-Fenster und reißt den Fokus an sich, was headless-Läufe (und Läufe neben
# laufender Arbeit) stört. Das DMG ist dann funktional, nur ohne Icon-Positionen
# und Hintergrundbild — für ein Release also nicht benutzen.
if [ "$FINDER_LAYOUT" = "1" ]; then
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Steinregen.app" of container window to {150, 180}
    set position of item "Applications" of container window to {450, 180}
    try
      set position of item ".background" of container window to {900, 900}
    end try
    -- macOS 26 übernimmt ein einmaliges `set bounds` gelegentlich nicht. Deshalb wird die
    -- Zielgröße wie beim erprobten Fastra-Release zurückgelesen und nötigenfalls wiederholt.
    repeat with i from 1 to 5
      set the bounds of container window to {200, 120, 800, 520}
      delay 1
      if (bounds of container window) = {200, 120, 800, 520} then exit repeat
    end repeat
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
else
    echo "    (Finder-Layout übersprungen: --no-finder-layout)"
fi

sync; sleep 2                       # Race: DS_Store-Schreibpuffer vs. detach
hdiutil detach "$DEVICE" -force     # genau unser Gerät, nicht „irgendwas an diesem Mountpunkt"
trap - EXIT                         # ab hier gibt es nichts mehr auszuhängen

echo "==> Komprimiere zu read-only DMG…"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG"

# --- 3) DMG signieren + notarisieren + stapeln ---------------------------------------------
if [ "$NOTARIZE" = "1" ]; then
    echo "==> Signiere DMG…"
    codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

    echo "==> Notarisierung einreichen (Profil $NOTARY_PROFILE) — kann ein paar Minuten dauern…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Ticket anheften (stapler)…"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    # Auch hier ein echtes Gate: Ein abgelehntes DMG ist kein veröffentlichbares Release.
    if ! SPCTL_DMG_OUT="$(spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1)"; then
        sed 's/^/    /' <<<"$SPCTL_DMG_OUT"
        echo "FEHLER: Gatekeeper lehnt das fertige DMG ab — keine Veröffentlichung."
        exit 1
    fi
    sed 's/^/    /' <<<"$SPCTL_DMG_OUT"
else
    echo "==> (übersprungen: Signieren/Notarisieren — UNSIGNIERTES Test-DMG)"
fi

echo ""
echo "Fertig:"
echo "  $ROOT/$DMG   ($(du -h "$DMG" | cut -f1))"
echo "  Test:  open \"$ROOT/$DMG\""

# --- 4) (optional) GitHub-Release ----------------------------------------------------------
# Nur mit --publish. Setzt Tag vX.Y.Z, erstellt/aktualisiert das Release und lädt das DMG hoch.
# Release-Notes aus dem passenden CHANGELOG.md-Abschnitt. Öffentliches Pushen ist
# rückfragepflichtig → daher opt-in, nicht Default.
if [ "$PUBLISH" = "1" ]; then
    echo ""
    echo "==> Veröffentliche GitHub-Release $TAG …"

    # Release-Notes aus CHANGELOG.md: Zeilen ab "## [VERSION]" bis zum nächsten "## [".
    NOTES_FILE="dist/release-notes-$VERSION.md"
    if [ -f CHANGELOG.md ]; then
        awk -v ver="$VERSION" '
            $0 ~ "^## \\[" ver "\\]" { grab=1; next }
            grab && /^## \[/         { exit }
            grab                     { print }
        ' CHANGELOG.md > "$NOTES_FILE"
    fi
    [ -s "$NOTES_FILE" ] || echo "Steinregen $TAG" > "$NOTES_FILE"

    # Unmittelbar vor der externen Mutation wird der gesamte Preflight wiederholt. Der Helfer
    # prüft nach dem Einzel-Tag-Push zusätzlich den Remote-Tag gegen HEAD und lässt `gh release
    # create` den vorhandenen Tag mit --verify-tag erzwingen.
    bash tools/github-release.sh publish "$DMG" "$NOTES_FILE"
fi
