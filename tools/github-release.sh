#!/bin/bash
# Einziger GitHub-Mutationspfad für make-dmg.sh. `preflight` ist rein lesend; `publish` wird erst
# nach erfolgreichem signiertem/notarisiertem DMG-Build aufgerufen und pusht genau einen Tag.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "FEHLER: $*" >&2
    exit 1
}

MODE="${1:-}"
[ -n "$MODE" ] || fail "Modus fehlt (preflight oder publish)."
shift

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION_VALUE" ] || fail "VERSION ist leer."
TAG="v$VERSION_VALUE"
REPO="${GITHUB_REPO:-}"
REMOTE="${GITHUB_REMOTE:-github}"

canonical_github_repo() {
    local url="$1" path
    case "$url" in
        https://github.com/*) path="${url#https://github.com/}" ;;
        git@github.com:*) path="${url#git@github.com:}" ;;
        ssh://git@github.com/*) path="${url#ssh://git@github.com/}" ;;
        *) return 1 ;;
    esac
    path="${path%/}"
    path="${path%.git}"
    [[ "$path" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    printf '%s' "$path" | tr '[:upper:]' '[:lower:]'
}

preflight() {
    command -v gh >/dev/null || fail "gh CLI fehlt."
    [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
        || fail "GITHUB_REPO muss die Form owner/name haben."

    local remote_url push_url remote_repo push_repo requested_repo head remote_main
    remote_url="$(git remote get-url "$REMOTE" 2>/dev/null)" \
        || fail "Git-Remote »${REMOTE}« fehlt."
    push_url="$(git remote get-url --push "$REMOTE" 2>/dev/null)" \
        || fail "Git-Remote »${REMOTE}« hat keine Push-URL."
    remote_repo="$(canonical_github_repo "$remote_url")" \
        || fail "Git-Remote »${REMOTE}« ist keine kanonische github.com-Repository-URL."
    push_repo="$(canonical_github_repo "$push_url")" \
        || fail "Git-Remote »${REMOTE}« hat keine kanonische github.com-Push-URL."
    requested_repo="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"
    [ "$remote_repo" = "$requested_repo" ] && [ "$push_repo" = "$requested_repo" ] \
        || fail "Fetch-/Push-URL von GITHUB_REMOTE und GITHUB_REPO bezeichnen nicht dasselbe Repository."

    [ "$(git branch --show-current)" = "main" ] \
        || fail "Releases dürfen nur vom Branch main entstehen."
    [ -z "$(git status --porcelain --untracked-files=normal)" ] \
        || fail "Arbeitsbaum ist nicht sauber; Release abgebrochen."
    grep -qF "## [$VERSION_VALUE]" CHANGELOG.md \
        || fail "CHANGELOG.md enthält keinen Abschnitt für $VERSION_VALUE."

    head="$(git rev-parse HEAD)"
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        [ "$(git rev-list -n 1 "$TAG")" = "$head" ] \
            || fail "Lokaler Tag $TAG zeigt nicht auf HEAD."
    fi

    gh auth status -h github.com >/dev/null 2>&1 \
        || fail "gh ist für github.com nicht angemeldet."
    remote_main="$(git ls-remote "$REMOTE" refs/heads/main 2>/dev/null | awk 'NR == 1 {print $1}')"
    [ -n "$remote_main" ] \
        || fail "Remote-Branch main ist auf »${REMOTE}« nicht erreichbar."
    [ "$remote_main" = "$head" ] \
        || fail "Remote-main und lokales HEAD sind nicht identisch."
}

remote_tag_commit() {
    local lines
    lines="$(git ls-remote "$REMOTE" "refs/tags/$TAG" "refs/tags/$TAG^{}" 2>/dev/null)" \
        || return 1
    awk -v direct="refs/tags/$TAG" -v peeled="refs/tags/$TAG^{}" '
        $2 == peeled { print $1; found = 1; exit }
        $2 == direct { fallback = $1 }
        END { if (!found && fallback != "") print fallback }
    ' <<<"$lines"
}

case "$MODE" in
    preflight)
        [ "$#" -eq 0 ] || fail "preflight akzeptiert keine weiteren Argumente."
        preflight
        echo "GitHub-Release-Preflight grün ($REPO, $TAG)."
        ;;
    publish)
        [ "$#" -eq 2 ] || fail "publish erwartet DMG und Release-Notes-Datei."
        DMG="$1"
        NOTES_FILE="$2"
        [ -s "$DMG" ] || fail "Release-DMG fehlt oder ist leer: $DMG"
        [ -s "$NOTES_FILE" ] || fail "Release-Notes fehlen oder sind leer: $NOTES_FILE"
        preflight

        if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
            git tag -a "$TAG" -m "Steinregen $TAG"
        fi
        # Explizite Ziel-Ref: Nie andere lokale Tags oder Branches mitsenden.
        git push "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"

        HEAD_SHA="$(git rev-parse HEAD)"
        REMOTE_TAG_SHA="$(remote_tag_commit)"
        [ -n "$REMOTE_TAG_SHA" ] || fail "Remote-Tag $TAG ist nach dem Push nicht lesbar."
        [ "$REMOTE_TAG_SHA" = "$HEAD_SHA" ] \
            || fail "Remote-Tag $TAG zeigt nicht auf das geprüfte HEAD."

        if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
            gh release upload "$TAG" "$DMG" -R "$REPO" --clobber
        else
            gh release create "$TAG" "$DMG" -R "$REPO" --verify-tag \
                --title "Steinregen $TAG" --notes-file "$NOTES_FILE"
        fi
        echo "==> Release online: https://github.com/$REPO/releases/tag/$TAG"
        ;;
    *)
        fail "Unbekannter Modus: $MODE"
        ;;
esac
