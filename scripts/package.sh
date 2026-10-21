#!/bin/bash
# Builds a Matcha disk image to install by hand, without Apple's signature: universal Release build (Apple silicon and
# Intel) signed ad hoc, with its entitlements (sandbox, network, camera…); the version and build numbers are given to
# xcodebuild (the project isn't modified). Run by GitHub Actions for each version tag (.github/workflows/release.yml).
# The signed and notarized path, with Developer ID, is scripts/release.sh.
#
#   scripts/package.sh 1.2.0          →  build/package/1.2.0/Matcha-1.2.0.dmg and its SHA-256
#   scripts/package.sh 1.2.0-beta.1   →  same, the app says 1.2.0
#
# macOS blocks the first opening of an app downloaded without Apple's signature: the release notes say what to do.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.]+)?$ ]]; then
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

VERSION="$1"
# The app's version has numbers only: “1.2.0-beta.1” gives 1.2.0.
SHORT_VERSION="${VERSION%%-*}"
# Always increasing, like scripts/release.sh: the number of commits.
BUILD="$(git rev-list --count HEAD)"
WORK="build/package/$VERSION"
APP="$WORK/DerivedData/Build/Products/Release/Matcha.app"
DMG="$WORK/Matcha-$VERSION.dmg"

step() {
    printf '\n▸ %s\n' "$1"
}

fail() {
    echo "✗ $1" >&2
    exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK"

step "Compilation Release universelle $SHORT_VERSION ($BUILD), signée ad hoc"
# “Sign to Run Locally”: no team, the entitlements stay.
xcodebuild -project Matcha.xcodeproj -scheme Matcha -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$WORK/DerivedData" MARKETING_VERSION="$SHORT_VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build > "$WORK/build.log" 2>&1 || {
    grep -E "error:" "$WORK/build.log" | sort -u || true
    fail "compilation en échec (journal : $WORK/build.log)"
}

step "Signature sans droit de débogage"
# Xcode adds `get-task-allow` (a debugger may attach) to any ad hoc signature, and turning that off
# (CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO) drops every entitlement: signed again with the same ones, less that.
codesign --display --xml --entitlements "$WORK/entitlements.plist" "$APP" 2>/dev/null
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$WORK/entitlements.plist" > /dev/null 2>&1 || true
codesign --force --sign - --options runtime --entitlements "$WORK/entitlements.plist" "$APP" 2>/dev/null

step "Vérifications"
codesign --verify --deep --strict "$APP" || fail "signature invalide"
entitlements=$(codesign --display --entitlements - "$APP" 2>/dev/null || true)
grep -q "com.apple.security.app-sandbox" <<< "$entitlements" || fail "l'app n'est pas dans le bac à sable"
grep -q "get-task-allow" <<< "$entitlements" && fail "l'app garde un droit de débogage (get-task-allow)"
archs=$(lipo -archs "$APP/Contents/MacOS/Matcha")
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "l'app n'est pas universelle : $archs"
echo "✓ signée ad hoc, bac à sable, $archs"

step "Image disque"
ROOT="$WORK/image"
mkdir -p "$ROOT"
ditto "$APP" "$ROOT/Matcha.app"
ln -s /Applications "$ROOT/Applications"
# hdiutil sometimes finds the volume busy on GitHub's machines: a few tries.
for attempt in 1 2 3; do
    if hdiutil create -volname "Matcha $VERSION" -srcfolder "$ROOT" -format UDZO -ov "$DMG" > "$WORK/hdiutil.log" 2>&1; then
        break
    fi
    [[ $attempt == 3 ]] && { cat "$WORK/hdiutil.log"; fail "image disque impossible à créer"; }
    sleep 5
done
shasum -a 256 "$DMG" | awk '{ print $1 }' > "$DMG.sha256"
echo "✓ $DMG"
echo "  SHA-256 : $(cat "$DMG.sha256")"
