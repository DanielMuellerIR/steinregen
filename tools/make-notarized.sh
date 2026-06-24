#!/bin/bash
# Baut Steinregen.app, signiert sie mit Developer ID + Hardened Runtime, notarisiert sie bei
# Apple und heftet das Ticket an (stapler) → die App startet auf FREMDEN Macs ohne
# Gatekeeper-Warnung. Ergebnis: dist/Steinregen-<version>-notarized.zip
#
# Nutzung:  bash tools/make-notarized.sh
#
# Voraussetzungen (einmalig je Mac — Schlüsselbund wird NICHT zwischen Macs gesynct!):
#   1) Developer-ID-Application-Zertifikat in der Login-Keychain. Prüfen:
#        security find-identity -v -p codesigning   (zeigt „Developer ID Application: …“)
#   2) notarytool-Keychain-Profil (Default: steinregen-notary). Einmal anlegen mit:
#        xcrun notarytool store-credentials steinregen-notary \
#          --apple-id <APPLE_ID> --team-id <TEAM_ID>
#      (App-spezifisches Passwort wird INTERAKTIV abgefragt — nie als CLI-Argument.)
#      Profil testen:  xcrun notarytool history --keychain-profile steinregen-notary
#
# Überschreibbar per Umgebungsvariablen:
#   SIGN_ID         Signing-Identität (Default unten — die Developer-ID dieses Entwicklers).
#   NOTARY_PROFILE  notarytool-Keychain-Profil (Default: steinregen-notary).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/Steinregen.app"

# Default-Identität + -Profil; beide per Umgebung überschreibbar (auf anderem Mac / anderem Konto).
SIGN_ID="${SIGN_ID:-Developer ID Application: Daniel Mueller (9QSWKSR4NQ)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-steinregen-notary}"

# --- Vorab-Checks: lieber jetzt klar scheitern als nach dem langen Build --------------------
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
    echo "FEHLER: Signing-Identität nicht in der Keychain gefunden:"
    echo "        »$SIGN_ID«"
    echo "        Vorhandene Identitäten:"
    security find-identity -v -p codesigning 2>/dev/null | sed 's/^/          /'
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "FEHLER: notarytool-Profil »$NOTARY_PROFILE« fehlt oder ist ungültig."
    echo "        Anlegen:  xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    echo "                    --apple-id <APPLE_ID> --team-id <TEAM_ID>"
    exit 1
fi

# --- 1) Bauen + mit Developer ID signieren (Hardened Runtime), KEIN Zwischen-ZIP ------------
echo "==> Bauen + Developer-ID-Signatur…"
SIGN_ID="$SIGN_ID" SKIP_ZIP=1 bash tools/make-app.sh

# Hardened-Runtime-Flag gegenprüfen — ohne lehnt die Notarisierung ab.
if codesign -dvv "$APP" 2>&1 | grep -q "flags=.*runtime"; then
    echo "    Hardened Runtime aktiv."
else
    echo "FEHLER: Hardened Runtime nicht gesetzt — Notarisierung würde abgelehnt."; exit 1
fi

# --- 2) ZIP fürs Einreichen (notarytool nimmt ZIP/DMG/PKG) ---------------------------------
SUBMIT_ZIP="dist/Steinregen-$VERSION-submit.zip"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

# --- 3) Notarisieren (wartet auf Apple; dauert i.d.R. 1–10 Min) ----------------------------
echo "==> Notarisierung einreichen (Profil $NOTARY_PROFILE) — das kann ein paar Minuten dauern…"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

# --- 4) Ticket anheften + prüfen (offline-Gatekeeper) --------------------------------------
echo "==> Ticket anheften (stapler)…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
echo "==> Gatekeeper-Bewertung:"
spctl --assess --type execute -vvv "$APP" 2>&1 | sed 's/^/    /' || true

# --- 5) Finale, GESTAPELTE App neu zippen; Zwischen-ZIP entfernen --------------------------
OUT_ZIP="dist/Steinregen-$VERSION-notarized.zip"
rm -f "$OUT_ZIP"
ditto -c -k --keepParent "$APP" "$OUT_ZIP"
rm -f "$SUBMIT_ZIP"

echo ""
echo "Fertig (signiert · notarisiert · gestapelt):"
echo "  $ROOT/$APP"
echo "  $ROOT/$OUT_ZIP   (Weitergabe ohne Gatekeeper-Warnung)"
