#!/bin/bash
# Every check a task must pass (CLAUDE.md, audit C7), in one command: formatting, lint, Debug build without any
# warning, unit tests, translations. Run locally before each commit, and by GitHub Actions on each push
# (.github/workflows/check.yml).
#
#   scripts/check.sh            checks everything, changes nothing
#   scripts/check.sh --fix      formats the code first (swiftformat), then checks
#
# Needs SwiftFormat and SwiftLint (brew install swiftformat swiftlint). Extra xcodebuild settings can be given in
# MATCHA_XCODEBUILD_FLAGS (GitHub Actions: no signing team on its machines), and options of the unit tests alone in
# MATCHA_TEST_FLAGS (GitHub Actions: one test at a time).
set -euo pipefail

cd "$(dirname "$0")/.."

FIX=false
[[ "${1:-}" == "--fix" ]] && FIX=true

# Word splitting wanted: several settings in one variable.
# shellcheck disable=SC2206
FLAGS=(${MATCHA_XCODEBUILD_FLAGS:-})
# shellcheck disable=SC2206
TEST_FLAGS=(${MATCHA_TEST_FLAGS:-})
DESTINATION="platform=macOS,arch=arm64"
LOGS="build/check"
mkdir -p "$LOGS"

step() {
    printf '\n▸ %s\n' "$1"
}

# Why the unit tests failed. When the host app crashes or quits, every unfinished test fails: its crash comes first,
# then each failed test with its message, read from the test results (the log's format depends on parallel or serial
# runs). `awk` rather than `head`: it reads to the end, so that `grep` never writes into a closed pipe.
report_test_failures() {
    local log="$LOGS/tests.log"
    grep -E "error:" "$log" | grep -v "appintents" | sort -u | awk 'NR <= 20' || true
    grep -E "encountered an error|Crash: |unexpected exit|exited with code|Fatal error:" "$log" | sort -u | awk 'NR <= 20' || true
    report_crashes
    local result
    result=$(find build/Logs/Test -maxdepth 1 -name '*.xcresult' -newer "$LOGS/tests-started" 2>/dev/null | sort | awk 'END { print }' || true)
    [[ -z "$result" ]] && return 0
    xcrun xcresulttool get test-results summary --path "$result" 2>/dev/null | python3 -c '
import json, sys

try:
    summary = json.load(sys.stdin)
except ValueError:
    sys.exit("  (résultats des tests illisibles)")
failures = summary.get("testFailures", [])
for failure in failures[:40]:
    name = failure.get("testIdentifierString") or failure.get("testName", "?")
    text = " ".join(failure.get("failureText", "").split())
    print(f"✘ {name} : {text[:400]}")
passed, total = summary.get("passedTests"), summary.get("totalTestCount")
print(f"  … {len(failures)} échecs ; {passed} tests passés sur {total}")
' || true
}

# Exception and first frames of the crashed thread of each Matcha crash report written during the tests (macOS keeps
# them in ~/Library/Logs/DiagnosticReports, as JSON after a header line).
report_crashes() {
    local reports
    reports=$(find "$HOME/Library/Logs/DiagnosticReports" -name 'Matcha*.ips' -newer "$LOGS/tests-started" 2>/dev/null || true)
    [[ -z "$reports" ]] && return 0
    mkdir -p "$LOGS/crashes"
    while IFS= read -r report; do
        cp "$report" "$LOGS/crashes/"
        echo "Plantage de Matcha : $report"
        python3 - "$report" <<'EOF' || true
import json, sys

body = json.loads(open(sys.argv[1]).read().split("\n", 1)[1])
exception = body.get("exception", {})
print("  ", exception.get("type"), exception.get("signal"), exception.get("subtype", ""))
for messages in (body.get("asi") or {}).values():
    for message in messages:
        print("  ", message.strip())
images = body.get("usedImages", [])
thread = body["threads"][body["faultingThread"]]
for frame in thread["frames"][:20]:
    image = images[frame["imageIndex"]].get("name", "?") if frame.get("imageIndex") is not None else "?"
    place = f" ({frame['sourceFile']}:{frame.get('sourceLine')})" if frame.get("sourceFile") else ""
    print(f"     {image}  {frame.get('symbol', '?')}{place}")
EOF
    done <<< "$reports"
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
# Crash reports and test results written from now on are this run's (`report_test_failures`).
touch "$LOGS/tests-started"
xcodebuild -project Matcha.xcodeproj -scheme Matcha -destination "$DESTINATION" -derivedDataPath build \
    ${FLAGS[@]+"${FLAGS[@]}"} ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"} test -only-testing:MatchaTests > "$LOGS/tests.log" 2>&1 || {
    report_test_failures
    echo "✗ tests en échec (journal : $LOGS/tests.log ; détail : xcrun xcresulttool, build/Logs/Test)"
    exit 1
}
echo "✓ tests unitaires"

printf '\n✓ Tout est en ordre.\n'
