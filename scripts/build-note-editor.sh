#!/usr/bin/env bash
# Builds the notes editor (task 12.2): OpenBlock and its React menus, from the files of its GitHub release at a fixed
# version (their SHA-256 are checked against the ones written here), with the page code of scripts/note-editor/src,
# into one script and one style sheet in Matcha/Resources/NoteEditor/ (kept in the repository: Xcode and the CI need
# neither Node nor the network). Their SHA-256 go to scripts/note-editor/note-editor.sha256, which scripts/check.sh
# checks.
#
# Usage: scripts/build-note-editor.sh            builds and replaces the files
#        scripts/build-note-editor.sh --verify   builds elsewhere and compares with the files kept (reproducible build)
#
# Needs curl, Node and pnpm (brew install node pnpm), and the network. Packages are installed without their install
# scripts. A package outside ALLOWED_PACKAGES in the bundle stops the build: its license must first be added to
# Matcha/Resources/ThirdPartyNotices.txt. A new version of OpenBlock: change OPENBLOCK_VERSION and the two SHA-256
# below (those of its SHA256SUMS.txt, after reading what changed).
set -euo pipefail

cd "$(dirname "$0")/.."

OPENBLOCK_VERSION="1.3.0"
OPENBLOCK_RELEASE="https://github.com/Labbs/openblock/releases/download/v$OPENBLOCK_VERSION"
# The core file carries ProseMirror (and orderedmap, rope-sequence, w3c-keyname, uuid); the React file imports the
# core, React and React DOM.
OPENBLOCK_CORE_SHA256="a8d5016d27fa71f4c489c275ef7c0f4961eb0649c938bb629c80fc0cbedebe36"
OPENBLOCK_REACT_SHA256="7af6661ad77564f98364e47c89686db40053a450c8c1148dcde112e1203b28d5"
SOURCES="scripts/note-editor"
OUTPUT="Matcha/Resources/NoteEditor"
MANIFEST="$SOURCES/note-editor.sha256"
# Packages whose license is in ThirdPartyNotices.txt; the core file covers all of ProseMirror's.
ALLOWED_PACKAGES="@labbs/openblock-core @labbs/openblock-react react react-dom scheduler"

VERIFY=false
[[ "${1:-}" == "--verify" ]] && VERIFY=true

for tool in curl node pnpm shasum; do
    command -v "$tool" > /dev/null || { echo "✗ $tool is missing (brew install node pnpm)"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "▸ OpenBlock $OPENBLOCK_VERSION"
mkdir -p "$WORK/openblock"
for file in openblock-core.esm.js openblock-react.esm.js; do
    curl --fail --silent --show-error --location --proto '=https' --output "$WORK/openblock/$file" "$OPENBLOCK_RELEASE/$file"
done
echo "$OPENBLOCK_CORE_SHA256  $WORK/openblock/openblock-core.esm.js
$OPENBLOCK_REACT_SHA256  $WORK/openblock/openblock-react.esm.js" | shasum -a 256 --check --quiet || {
    echo "✗ the files of OpenBlock $OPENBLOCK_VERSION differ from the SHA-256 written in this script"
    exit 1
}

echo "▸ Page of the editor"
(cd "$SOURCES" && pnpm install --frozen-lockfile --ignore-scripts --reporter=silent)
mkdir -p "$WORK/out"
modules="$PWD/$SOURCES/node_modules"
"$SOURCES/node_modules/.bin/esbuild" "$SOURCES/src/main.tsx" \
    --bundle --minify --format=iife --target=safari18 --jsx=automatic --charset=utf8 --legal-comments=none \
    --define:process.env.NODE_ENV='"production"' \
    --alias:@labbs/openblock-core="$WORK/openblock/openblock-core.esm.js" \
    --alias:@labbs/openblock-react="$WORK/openblock/openblock-react.esm.js" \
    --alias:react="$modules/react" --alias:react-dom="$modules/react-dom" \
    --metafile="$WORK/meta.json" --log-level=warning \
    --outfile="$WORK/out/note-editor.js"

# Packages in the bundle: the folder after the last `node_modules/` of each input, or OpenBlock's own files.
packages=$(node -e '
    const inputs = Object.keys(require(process.argv[1]).inputs);
    const names = new Set(inputs.map((path) => {
        if (path.endsWith("/openblock/openblock-core.esm.js")) return "@labbs/openblock-core";
        if (path.endsWith("/openblock/openblock-react.esm.js")) return "@labbs/openblock-react";
        const match = path.match(/.*node_modules\/((?:@[^/]+\/)?[^/]+)\//);
        return match ? match[1] : null;
    }).filter(Boolean));
    console.log([...names].sort().join("\n"));
' "$WORK/meta.json")
for package in $packages; do
    allowed=false
    for pattern in $ALLOWED_PACKAGES; do
        # shellcheck disable=SC2053
        [[ "$package" == $pattern ]] && allowed=true
    done
    if ! $allowed; then
        echo "✗ $package is in the bundle without its license in ThirdPartyNotices.txt (ALLOWED_PACKAGES)"
        exit 1
    fi
done
echo "  packages: $(echo "$packages" | tr '\n' ' ')"

hashes=$(cd "$WORK/out" && shasum -a 256 note-editor.js note-editor.css | sed "s|  |  $OUTPUT/|")
if $VERIFY; then
    if [[ "$hashes" == "$(cat "$MANIFEST")" ]]; then
        echo "✓ same files as the ones kept"
        exit 0
    fi
    echo "✗ the build differs from the files kept"
    diff <(echo "$hashes") "$MANIFEST" || true
    exit 1
fi
mkdir -p "$OUTPUT"
cp "$WORK/out/note-editor.js" "$WORK/out/note-editor.css" "$OUTPUT/"
echo "$hashes" > "$MANIFEST"
echo "✓ $OUTPUT/note-editor.js ($(wc -c < "$OUTPUT/note-editor.js" | tr -d ' ') bytes), note-editor.css; $MANIFEST"
