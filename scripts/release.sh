#!/bin/bash
# Publishes a Matcha release (task 8.5): Release archive signed with Developer ID, notarized and stapled, disk image
# signed and notarized, Sparkle signature, entry added to appcast.xml (gh-pages branch, served by GitHub Pages),
# git tag and GitHub “Release” with the disk image.
#
#   scripts/release.sh 1.2.0             publishes version 1.2.0
#   scripts/release.sh 1.2.0 --dry-run   prepares everything in build/release/1.2.0 without publishing anything
#
# Once and for all (manual steps, see TESTS_MANUELS.md, phase 8): “Developer ID Application” certificate,
# notarization profile (xcrun notarytool store-credentials matcha-notary), Sparkle EdDSA key in the keychain
# (generate_keys), `brew install create-dmg`, `gh auth login`, GitHub Pages on the gh-pages branch.
# The project isn't modified: the version and build numbers are passed to xcodebuild.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -lt 1 || ! "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

VERSION="$1"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

TEAM_ID="5ZXE2LBS37"
REPO="MatchaBrowser/Matcha"
NOTARY_PROFILE="${MATCHA_NOTARY_PROFILE:-matcha-notary}"
MINIMUM_SYSTEM="15.4"
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
git rev-parse "$TAG" >/dev/null 2>&1 && fail "L'étiquette $TAG existe déjà."
for tool in xcodebuild xcbeautify create-dmg python3; do
    command -v "$tool" >/dev/null || fail "$tool manque."
done
$DRY_RUN || command -v gh >/dev/null || fail "gh manque (brew install gh)."
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || fail "Certificat « Developer ID Application » absent du trousseau."

# MARK: Archive and export

step "Archive Release $VERSION ($BUILD)"
rm -rf "$WORK"
mkdir -p "$WORK"
xcodebuild -project Matcha.xcodeproj -scheme Matcha -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive | xcbeautify --quiet

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

# MARK: Notarization

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait \
        | tee "$WORK/notarization.log" | grep -q "status: Accepted" || fail "Notarisation refusée (voir $WORK/notarization.log)."
}

step "Notarisation de l'app"
ditto -c -k --keepParent "$APP" "$WORK/Matcha.zip"
notarize "$WORK/Matcha.zip"
xcrun stapler staple "$APP"

step "Image disque"
create-dmg --volname "Matcha" --window-size 540 360 --icon-size 128 --icon "Matcha.app" 140 170 \
    --app-drop-link 400 170 --hide-extension "Matcha.app" "$DMG" "$APP" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

# MARK: Sparkle

step "Signature Sparkle"
SIGN_UPDATE="${SPARKLE_BIN:-$(find build/SourcePackages/artifacts -name sign_update -type f -perm -u+x 2>/dev/null | head -1)}"
[[ -x "$SIGN_UPDATE" ]] || fail "sign_update introuvable (compiler une fois pour récupérer Sparkle, ou SPARKLE_BIN=…)."
SIGNATURE="$("$SIGN_UPDATE" "$DMG")"
EDSIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE")"
LENGTH="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$SIGNATURE")"
[[ -n "$EDSIGNATURE" && -n "$LENGTH" ]] || fail "Signature Sparkle illisible : $SIGNATURE"

step "appcast.xml (branche gh-pages)"
PAGES="$WORK/pages"
git fetch origin gh-pages >/dev/null 2>&1 || true
if git rev-parse --verify --quiet origin/gh-pages >/dev/null; then
    git worktree add --force "$PAGES" origin/gh-pages >/dev/null
    git -C "$PAGES" switch -C gh-pages >/dev/null
else
    git worktree add --force --detach "$PAGES" >/dev/null
    git -C "$PAGES" switch --orphan gh-pages >/dev/null
fi
python3 -I scripts/appcast.py "$PAGES/appcast.xml" \
    --version "$BUILD" --short-version "$VERSION" --url "$DOWNLOAD_URL" \
    --signature "$EDSIGNATURE" --length "$LENGTH" --minimum-system "$MINIMUM_SYSTEM"
git -C "$PAGES" add appcast.xml
git -C "$PAGES" commit -q -m "Matcha $VERSION"

if $DRY_RUN; then
    step "Essai : rien n'est publié"
    echo "Image disque : $DMG"
    echo "appcast.xml  : $PAGES/appcast.xml"
    git worktree remove --force "$PAGES"
    exit 0
fi

# MARK: Publishing

step "Publication"
git tag -a "$TAG" -m "Matcha $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --repo "$REPO" --title "Matcha $VERSION" --generate-notes
git -C "$PAGES" push origin gh-pages
git worktree remove --force "$PAGES"
echo "Matcha $VERSION publié : $DOWNLOAD_URL"
