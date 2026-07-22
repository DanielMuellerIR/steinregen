#!/bin/bash
# Isolierte Regressionen für den Publish-Helfer. Alle Git-/gh-Aufrufe laufen über Fakes in einem
# temporären Repo; es gibt weder Netzwerkzugriffe noch echte Tags, Pushes oder Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/steinregen-release-test.XXXXXX")"
cleanup() {
    case "$TMP_ROOT" in
        "${TMPDIR:-/tmp}"/steinregen-release-test.*) rm -rf -- "$TMP_ROOT" ;;
        *) echo "Unsicherer Temp-Pfad: $TMP_ROOT" >&2; exit 1 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMP_ROOT/repo/tools" "$TMP_ROOT/bin"
cp "$ROOT/tools/github-release.sh" "$TMP_ROOT/repo/tools/github-release.sh"
printf '0.27.15\n' > "$TMP_ROOT/repo/VERSION"
printf '# Changelog\n\n## [0.27.15]\n\n- Test.\n' > "$TMP_ROOT/repo/CHANGELOG.md"
printf 'fake dmg\n' > "$TMP_ROOT/repo/app.dmg"
printf 'fake notes\n' > "$TMP_ROOT/repo/notes.md"

EVENT_LOG="$TMP_ROOT/events.log"
LOCAL_TAG_STATE="$TMP_ROOT/local-tag.state"
PUSH_STATE="$TMP_ROOT/push.state"

cat > "$TMP_ROOT/bin/git" <<'FAKE_GIT'
#!/bin/bash
set -euo pipefail
printf 'git %s\n' "$*" >> "$FAKE_EVENT_LOG"
case "$1" in
    remote)
        [ "$2" = get-url ] || exit 90
        if [ "${3:-}" = --push ]; then
            printf '%s\n' "${FAKE_PUSH_URL:-$FAKE_REMOTE_URL}"
        else
            printf '%s\n' "$FAKE_REMOTE_URL"
        fi
        ;;
    branch)
        printf '%s\n' "${FAKE_BRANCH:-main}"
        ;;
    status)
        [ "${FAKE_DIRTY:-0}" = 0 ] || printf '%s\n' ' M dirty-file'
        ;;
    rev-parse)
        if [ "$2" = HEAD ]; then
            printf '%s\n' "$FAKE_HEAD"
        elif [ "$2" = -q ] && [ "$3" = --verify ]; then
            [ -s "$FAKE_LOCAL_TAG_STATE" ] || exit 1
            printf '%s\n' fake-tag-object
        else
            exit 91
        fi
        ;;
    rev-list)
        printf '%s\n' "${FAKE_LOCAL_TAG_SHA:-$FAKE_HEAD}"
        ;;
    ls-remote)
        if [ "$3" = refs/heads/main ]; then
            printf '%s\t%s\n' "${FAKE_REMOTE_MAIN:-$FAKE_HEAD}" refs/heads/main
        else
            [ -s "$FAKE_PUSH_STATE" ] || exit 0
            printf '%s\t%s\n' fake-tag-object "refs/tags/$FAKE_TAG"
            printf '%s\t%s\n' "${FAKE_REMOTE_TAG_SHA:-$FAKE_HEAD}" "refs/tags/$FAKE_TAG^{}"
        fi
        ;;
    tag)
        printf 'tagged\n' > "$FAKE_LOCAL_TAG_STATE"
        ;;
    push)
        printf 'pushed\n' > "$FAKE_PUSH_STATE"
        ;;
    *) exit 92 ;;
esac
FAKE_GIT

cat > "$TMP_ROOT/bin/gh" <<'FAKE_GH'
#!/bin/bash
set -euo pipefail
printf 'gh %s\n' "$*" >> "$FAKE_EVENT_LOG"
case "$1 $2" in
    'auth status') exit 0 ;;
    'release view') [ "${FAKE_RELEASE_EXISTS:-0}" = 1 ] ;;
    'release create'|'release upload') exit 0 ;;
    *) exit 93 ;;
esac
FAKE_GH
chmod +x "$TMP_ROOT/bin/git" "$TMP_ROOT/bin/gh"

export PATH="$TMP_ROOT/bin:/usr/bin:/bin"
export FAKE_EVENT_LOG="$EVENT_LOG"
export FAKE_LOCAL_TAG_STATE="$LOCAL_TAG_STATE"
export FAKE_PUSH_STATE="$PUSH_STATE"
export FAKE_HEAD=1111111111111111111111111111111111111111
export FAKE_TAG=v0.27.15
export GITHUB_REMOTE=github

reset_fake_state() {
    : > "$EVENT_LOG"
    rm -f -- "$LOCAL_TAG_STATE" "$PUSH_STATE"
    unset FAKE_REMOTE_MAIN FAKE_REMOTE_TAG_SHA FAKE_LOCAL_TAG_SHA FAKE_RELEASE_EXISTS FAKE_PUSH_URL
}

cd "$TMP_ROOT/repo"

# HTTPS und SCP-artige SSH-URLs werden auf dieselbe owner/name-Identität normalisiert.
reset_fake_state
GITHUB_REPO=DanielMuellerIR/Steinregen \
FAKE_REMOTE_URL=https://github.com/danielmuellerir/steinregen.git \
    bash tools/github-release.sh preflight >/dev/null
GITHUB_REPO=danielmuellerir/steinregen \
FAKE_REMOTE_URL=git@github.com:DanielMuellerIR/Steinregen.git \
    bash tools/github-release.sh preflight >/dev/null

# Ein abweichendes Ziel muss vor jeder Remote-Abfrage oder gh-Release-Operation scheitern.
reset_fake_state
if GITHUB_REPO=someone/else FAKE_REMOTE_URL=https://github.com/danielmuellerir/steinregen.git \
        bash tools/github-release.sh preflight >"$TMP_ROOT/mismatch.out" 2>&1; then
    echo "Identitätsabweichung wurde akzeptiert" >&2
    exit 1
fi
grep -qF 'nicht dasselbe Repository' "$TMP_ROOT/mismatch.out"
if grep -qE 'git ls-remote|gh release' "$EVENT_LOG"; then
    echo "Identitätsabweichung erreichte Remote-/Release-Aufrufe" >&2
    exit 1
fi

# Eine abweichende Push-URL darf nicht hinter einer passenden Fetch-URL verborgen bleiben.
reset_fake_state
if GITHUB_REPO=danielmuellerir/steinregen \
        FAKE_REMOTE_URL=https://github.com/danielmuellerir/steinregen.git \
        FAKE_PUSH_URL=git@github.com:someone/else.git \
        bash tools/github-release.sh preflight >"$TMP_ROOT/push-mismatch.out" 2>&1; then
    echo "Abweichende Push-URL wurde akzeptiert" >&2
    exit 1
fi
grep -qF 'nicht dasselbe Repository' "$TMP_ROOT/push-mismatch.out"

# main muss genau dem geprüften lokalen HEAD entsprechen.
reset_fake_state
if GITHUB_REPO=danielmuellerir/steinregen \
        FAKE_REMOTE_URL=https://github.com/danielmuellerir/steinregen.git \
        FAKE_REMOTE_MAIN=2222222222222222222222222222222222222222 \
        bash tools/github-release.sh preflight >"$TMP_ROOT/main-mismatch.out" 2>&1; then
    echo "Abweichender Remote-main wurde akzeptiert" >&2
    exit 1
fi
grep -qF 'Remote-main und lokales HEAD' "$TMP_ROOT/main-mismatch.out"

# Erfolgsweg: einzelner Tag-Push, danach Remote-Tag-Prüfung, erst danach Release mit --verify-tag.
reset_fake_state
GITHUB_REPO=danielmuellerir/steinregen \
FAKE_REMOTE_URL=https://github.com/danielmuellerir/steinregen.git \
    bash tools/github-release.sh publish app.dmg notes.md >/dev/null
grep -qF 'git push github refs/tags/v0.27.15:refs/tags/v0.27.15' "$EVENT_LOG"
grep -qF 'git ls-remote github refs/tags/v0.27.15 refs/tags/v0.27.15^{}' "$EVENT_LOG"
grep -qE '^gh release create .*--verify-tag' "$EVENT_LOG"
TAG_CHECK_LINE="$(grep -nF 'git ls-remote github refs/tags/v0.27.15' "$EVENT_LOG" | cut -d: -f1)"
RELEASE_LINE="$(grep -nF 'gh release create' "$EVENT_LOG" | cut -d: -f1)"
[ "$TAG_CHECK_LINE" -lt "$RELEASE_LINE" ] || { echo "Release lief vor Remote-Tag-Prüfung" >&2; exit 1; }

# Ein falsch aufgelöster Remote-Tag stoppt vor jeder gh-Release-Operation.
reset_fake_state
if GITHUB_REPO=danielmuellerir/steinregen \
        FAKE_REMOTE_URL=https://github.com/danielmuellerir/steinregen.git \
        FAKE_REMOTE_TAG_SHA=3333333333333333333333333333333333333333 \
        bash tools/github-release.sh publish app.dmg notes.md >"$TMP_ROOT/tag-mismatch.out" 2>&1; then
    echo "Abweichender Remote-Tag wurde akzeptiert" >&2
    exit 1
fi
grep -qF 'zeigt nicht auf das geprüfte HEAD' "$TMP_ROOT/tag-mismatch.out"
if grep -qE '^gh release (view|create|upload)' "$EVENT_LOG"; then
    echo "Remote-Tag-Abweichung erreichte gh release" >&2
    exit 1
fi

# make-dmg muss ausschließlich den getesteten Helfer verwenden.
grep -qF 'bash tools/github-release.sh preflight' "$ROOT/tools/make-dmg.sh"
grep -qF 'bash tools/github-release.sh publish "$DMG" "$NOTES_FILE"' "$ROOT/tools/make-dmg.sh"
if grep -qE '^[[:space:]]*gh release ' "$ROOT/tools/make-dmg.sh"; then
    echo "make-dmg enthält einen ungetesteten direkten gh-release-Pfad" >&2
    exit 1
fi

echo "github-release-tests: Identität, main, Remote-Tag und --verify-tag grün"
