#!/bin/bash
# Gemeinsame Profilermittlung für install.sh und release.sh.
# Wird gesourct, nicht ausgeführt. Credential-Werte bleiben ausschließlich im
# macOS-Schlüsselbund; hier steht nur der Profil-NAME.
#
# Die eigentliche Bau-/Signier-/Notarisierungsarbeit liegt weiterhin in
# tools/make-notarized.sh (App als ZIP) und tools/make-dmg.sh (App + DMG).

# Profilnamen bestimmen: Umgebung schlägt clone-lokale Git-Konfiguration.
# Kein fester Default — ein eingecheckter Name existiert auf fremden Macs nicht
# und ließe den Lauf erst nach dem Bauen scheitern. Keychain-Profile sind ohnehin
# pro Mac lokal und werden nicht synchronisiert.
require_notary_profile() {
    if [[ -z "${NOTARY_PROFILE:-}" ]]; then
        NOTARY_PROFILE="$(git config --local --get steinregen.notaryProfile 2>/dev/null || true)"
    fi
    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "FEHLER: Kein Notary-Profil bekannt." >&2
        echo "Entweder NOTARY_PROFILE setzen oder einmalig für diesen Clone:" >&2
        echo "  git config --local steinregen.notaryProfile <profil>" >&2
        echo "Das Profil selbst einmal pro Mac anlegen:" >&2
        echo "  xcrun notarytool store-credentials <profil> --apple-id <apple-id> --team-id <team-id>" >&2
        return 2
    fi
    export NOTARY_PROFILE

    # Nur ein echter Aufruf erkennt, ob das Profil auf diesem Mac benutzbar ist.
    # Fünf Versuche statt einem: `notarytool history` meldet gelegentlich
    # fälschlich „No Keychain password item found", obwohl das Profil da ist
    # (2026-07-26 auf M3 belegt — Versuch 1 fehlgeschlagen, Versuch 2 sofort ok).
    # Ein einzelner Fehlversuch würde sonst einen ganzen Lauf grundlos abbrechen;
    # ein wirklich fehlendes Profil scheitert auch nach fünf Versuchen.
    local attempt
    for attempt in 1 2 3 4 5; do
        xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 && return 0
        sleep 3
    done
    echo "FEHLER: Das Notary-Profil '$NOTARY_PROFILE' ist auf diesem Mac nicht verwendbar." >&2
    echo "Über SSH ist der Login-Schlüsselbund gesperrt — dann in einer lokalen" >&2
    echo "Terminalsitzung erneut versuchen." >&2
    return 2
}
