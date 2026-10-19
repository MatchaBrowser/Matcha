#!/bin/bash
# Every check a task must pass (CLAUDE.md, audit C7), in one command: formatting, lint, Debug build without any
# warning, unit tests, translations. Run locally before each commit, and by GitHub Actions on each push
# (.github/workflows/check.yml).
#
#   scripts/check.sh            checks everything, changes nothing
#   scripts/check.sh --fix      formats the code first (swiftformat), then checks
#
# Needs SwiftFormat and SwiftLint (brew install swiftformat swiftlint). Extra xcodebuild settings can be given in
# MATCHA_XCODEBUILD_FLAGS (GitHub Actions: no signing team on its machines).
set -euo pipefail

cd "$(dirname "$0")/.."

FIX=false
[[ "${1:-}" == "--fix" ]] && FIX=true

# Word splitting wanted: several settings in one variable.
# shellcheck disable=SC2206
FLAGS=(${MATCHA_XCODEBUILD_FLAGS:-})
DESTINATION="platform=macOS,arch=arm64"
LOGS="build/check"
mkdir -p "$LOGS"

step() {
    printf '\n▸ %s\n' "$1"
}

step "Mise en forme (SwiftFormat)"
if $FIX; then
    swiftformat .
else
    swiftformat --lint .
fi

step "Style (SwiftLint, avertissements compris)"
swiftlint --strict --quiet

step "Compilation Debug, sans avertissement"
xcodebuild -project Matcha.xcodeproj -scheme Matcha -configuration Debug -destination "$DESTINATION" \
    -derivedDataPath build ${FLAGS[@]+"${FLAGS[@]}"} build > "$LOGS/build.log" 2>&1 || {
    grep -E "error:" "$LOGS/build.log" | sort -u
    echo "✗ compilation en échec (journal : $LOGS/build.log)"
    exit 1
}
# The App Intents metadata step warns about a framework the app doesn't use: not ours.
if grep -E "warning:" "$LOGS/build.log" | grep -v "appintents" | sort -u | grep .; then
    echo "✗ avertissements de compilation (journal : $LOGS/build.log)"
    exit 1
fi
echo "✓ compilation sans avertissement"

step "Traductions"
scripts/check-localizations.sh

step "Tests unitaires"
xcodebuild -project Matcha.xcodeproj -scheme Matcha -destination "$DESTINATION" -derivedDataPath build \
    ${FLAGS[@]+"${FLAGS[@]}"} test -only-testing:MatchaTests > "$LOGS/tests.log" 2>&1 || {
    grep -E "error:|✘|failed" "$LOGS/tests.log" | head -40
    echo "✗ tests en échec (journal : $LOGS/tests.log ; détail : xcrun xcresulttool, build/Logs/Test)"
    exit 1
}
echo "✓ tests unitaires"

printf '\n✓ Tout est en ordre.\n'
