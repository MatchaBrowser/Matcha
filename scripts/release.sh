#!/bin/bash
# Publishes a Matcha release (task 8.5): Release archive signed with Developer ID, notarized and stapled, disk image
# signed and notarized, Sparkle signature, entry added to appcast.xml (gh-pages branch, served by GitHub Pages),
# git tag and GitHub “Release” with the disk image.
#
#   scripts/release.sh 1.2.0             publishes version 1.2.0
#   scripts/release.sh 1.2.0 --dry-run   prepares everything in build/release/1.2.0 without publishing anything
#
# Once and for all (manual steps, see TESTS_MANUELS.md, phase 8): “Developer ID Application” certificate of the
# project's team, notarization profile (xcrun notarytool store-credentials matcha-notary), Sparkle EdDSA key in the
# keychain (generate_keys), `brew install create-dmg`, `gh auth login`, GitHub Pages on the gh-pages branch.
# The project isn't modified: the version and build numbers are passed to xcodebuild. MATCHA_SIGNING_IDENTITY (SHA-1
# or full name) picks the certificate when the team has several.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

# Any other argument stops everything: a typo such as `--dryrun` must not publish (review DI3).
VERSION=""
DRY_RUN=false
for argument in "$@"; do
    case "$argument" in
        --dry-run) DRY_RUN=true ;;
        -*) echo "Option inconnue : $argument" >&2; usage ;;
        *) [[ -z "$VERSION" ]] || usage; VERSION="$argument" ;;
    esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || usage

REPO="MatchaBrowser/Matcha"
NOTARY_PROFILE="${MATCHA_NOTARY_PROFILE:-matcha-notary}"
TAG="v$VERSION"
# Build number: always increasing (Sparkle compares `sparkle:version`).
BUILD="$(git rev-list --count HEAD)"
WORK="build/release/$VERSION"
ARCHIVE="$WORK/Matcha.xcarchive"
EXPORT="$WORK/export"
APP="$EXPORT/Matcha.app"
DMG="$WORK/Matcha-$VERSION.dmg"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/Matcha-$VERSION.dmg"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# MARK: Checks

step "Vérifications"
[[ -z "$(git status --porcelain)" ]] || fail "Des changements ne sont pas commités."
for tool in xcodebuild xcbeautify create-dmg python3; do
    command -v "$tool" >/dev/null || fail "$tool manque."
done
$DRY_RUN || command -v gh >/dev/null || fail "gh manque (brew install gh)."

git fetch --quiet origin main
git fetch --quiet origin gh-pages 2>/dev/null || true
if ! $DRY_RUN; then
    # The build number counts the commits: published from another branch, it could pass main's (review DI3).
    [[ "$(git branch --show-current)" == main ]] || fail "La publication se fait depuis main."
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main n'est pas à jour avec origin/main."
fi
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "L'étiquette $TAG existe déjà."
[[ -z "$(git ls-remote --tags origin "refs/tags/$TAG")" ]] || fail "L'étiquette $TAG existe déjà sur GitHub."
PAGES_PARENT="$(git rev-parse -q --verify origin/gh-pages || true)"
if [[ -n "$PAGES_PARENT" ]] && git cat-file -e "${PAGES_PARENT}:appcast.xml" 2>/dev/null; then
    LAST_BUILD="$(git show "${PAGES_PARENT}:appcast.xml" | python3 -I -c '
import sys
import xml.etree.ElementTree as ET

tag = "{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
print(max((int(item.text) for item in ET.parse(sys.stdin).iter(tag) if (item.text or "").isdigit()), default=0))
')"
    (( BUILD > LAST_BUILD )) || fail "Le build $BUILD ne dépasse pas celui de la dernière version publiée ($LAST_BUILD)."
fi

# The project's team signs both the archive and the export, with a certificate of that team (review DI1). `awk`
# reads to the end: closing the pipe early would fail `xcodebuild` (SIGPIPE, `pipefail`).
TEAM_ID="$(xcodebuild -project Matcha.xcodeproj -scheme Matcha -configuration Release -showBuildSettings 2>/dev/null \
    | awk '$1 == "DEVELOPMENT_TEAM" && !found { print $3; found = 1 }')"
[[ -n "$TEAM_ID" ]] || fail "Aucune équipe de signature dans le projet (DEVELOPMENT_TEAM)."
IDENTITY="${MATCHA_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -v team="($TEAM_ID)\"" '/"Developer ID Application: / && index($0, team) && !found { print $2; found = 1 }')}"
[[ -n "$IDENTITY" ]] || fail "Certificat « Developer ID Application » de l'équipe $TEAM_ID absent du trousseau."
echo "Équipe $TEAM_ID, build $BUILD"

# MARK: Archive and export

step "Archive Release $VERSION ($BUILD)"
rm -rf "$WORK"
mkdir -p "$WORK"
xcodebuild -project Matcha.xcodeproj -scheme Matcha -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" MATCHA_RELEASE_VERSION="$VERSION" archive | xcbeautify --quiet

step "Export Developer ID"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$WORK/ExportOptions.plist" \
    | xcbeautify --quiet
codesign --verify --deep --strict "$APP" || fail "Signature de l'app invalide."
SIGNER="$(codesign --display --verbose=2 "$APP" 2>&1)"
grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$SIGNER" || fail "L'app n'est pas signée par l'équipe $TEAM_ID."
# The compiled app's own minimum, never a copy of it (review DI11).
MINIMUM_SYSTEM="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")"

# MARK: Notarization

# Sends $1 to Apple and waits for the answer; a refusal brings Apple's log back next to it (review DI3).
notarize() {
    local name result status id
    name="$(basename "$1")"
    result="$WORK/notarization-$name.json"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$result" || true
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
    [[ "$status" == "Accepted" ]] && return 0
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    if [[ -n "$id" ]]; then
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$WORK/notarization-$name-log.json" >/dev/null || true
    fi
    fail "Notarisation de $name refusée (${status:-sans réponse}) : voir $result et $WORK/notarization-$name-log.json."
}

step "Notarisation de l'app"
ditto -c -k --keepParent "$APP" "$WORK/Matcha.zip"
notarize "$WORK/Matcha.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -vv "$APP"

step "Image disque"
# create-dmg takes the folder whose contents make the image, as package.sh does (review DI3).
STAGE="$WORK/image"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Matcha.app"
create-dmg --volname "Matcha" --window-size 540 360 --icon-size 128 --icon "Matcha.app" 140 170 \
    --app-drop-link 400 170 --hide-extension "Matcha.app" "$DMG" "$STAGE" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

# MARK: Sparkle

step "Signature Sparkle"
SIGN_UPDATE="${SPARKLE_BIN:-$(find build/SourcePackages/artifacts -name sign_update -type f -perm -u+x -print -quit 2>/dev/null || true)}"
[[ -x "$SIGN_UPDATE" ]] || fail "sign_update introuvable (compiler une fois pour récupérer Sparkle, ou SPARKLE_BIN=…)."
SIGNATURE="$("$SIGN_UPDATE" "$DMG")"
EDSIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE")"
LENGTH="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$SIGNATURE")"
[[ -n "$EDSIGNATURE" && -n "$LENGTH" ]] || fail "Signature Sparkle illisible : $SIGNATURE"

step "appcast.xml (branche gh-pages)"
FEED="$WORK/appcast.xml"
if [[ -n "$PAGES_PARENT" ]]; then
    git show "${PAGES_PARENT}:appcast.xml" > "$FEED" 2>/dev/null || rm -f "$FEED"
fi
python3 -I scripts/appcast.py "$FEED" \
    --version "$BUILD" --short-version "$VERSION" --url "$DOWNLOAD_URL" \
    --signature "$EDSIGNATURE" --length "$LENGTH" --minimum-system "$MINIMUM_SYSTEM"
# The commit of gh-pages is written with a separate index, without a worktree or a local branch (review DI3): nothing
# to clean up after a failure, and a dry run leaves nothing that would block the first publication.
INDEX="$WORK/pages.index"
if [[ -n "$PAGES_PARENT" ]]; then
    GIT_INDEX_FILE="$INDEX" git read-tree "$PAGES_PARENT"
else
    GIT_INDEX_FILE="$INDEX" git read-tree --empty
fi
BLOB="$(git hash-object -w "$FEED")"
GIT_INDEX_FILE="$INDEX" git update-index --add --cacheinfo "100644,$BLOB,appcast.xml"
TREE="$(GIT_INDEX_FILE="$INDEX" git write-tree)"
PAGES_COMMIT="$(git commit-tree "$TREE" ${PAGES_PARENT:+-p "$PAGES_PARENT"} -m "Matcha $VERSION")"

if $DRY_RUN; then
    step "Essai : rien n'est publié"
    echo "Image disque : $DMG"
    echo "appcast.xml  : $FEED (commit $PAGES_COMMIT, non poussé)"
    exit 0
fi

# MARK: Publishing

# What is already public when a step fails, and how to go on or undo it.
STAGE_DONE=""
report() {
    local status=$?
    [[ $status -eq 0 || -z "$STAGE_DONE" ]] && return
    case "$STAGE_DONE" in
        tag) echo "L'étiquette $TAG est sur GitHub. Pour annuler : git push origin :refs/tags/$TAG && git tag -d $TAG" ;;
        draft) echo "Release brouillon $TAG créée, non publiée : gh release delete $TAG --repo $REPO --cleanup-tag --yes" ;;
        release) echo "Release $TAG publiée ; reste l'appcast : git push origin $PAGES_COMMIT:refs/heads/gh-pages" ;;
    esac >&2
}
trap report EXIT

step "Publication"
git tag -a "$TAG" -m "Matcha $VERSION"
git push origin "$TAG"
STAGE_DONE=tag
# A draft first: published with its notarized image already there, the release never gets the image of release.yml
# in its place (review DI2). The appcast comes last: an update is offered only once its image can be downloaded.
gh release create "$TAG" "$DMG" --repo "$REPO" --title "Matcha $VERSION" --generate-notes --draft
STAGE_DONE=draft
gh release edit "$TAG" --repo "$REPO" --draft=false
STAGE_DONE=release
git push origin "$PAGES_COMMIT:refs/heads/gh-pages"
STAGE_DONE=""
echo "Matcha $VERSION publié : $DOWNLOAD_URL"
