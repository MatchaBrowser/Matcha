#!/usr/bin/env bash
# Builds the notes editor (task 12.2): OpenBlock and its React menus, from the sources of the public repository at a
# fixed tag (the commit is checked), with the page code of scripts/note-editor/src, into one script and one style
# sheet in Matcha/Resources/NoteEditor/ (kept in the repository: Xcode and the CI need neither Node nor the network).
# Their SHA-256 go to scripts/note-editor/note-editor.sha256, which scripts/check.sh checks.
#
# Usage: scripts/build-note-editor.sh            builds and replaces the files
#        scripts/build-note-editor.sh --verify   builds elsewhere and compares with the files kept (reproducible build)
#
# Needs git, Node and pnpm (brew install node pnpm), and the network. Packages are installed without their install
# scripts. A package outside ALLOWED_PACKAGES in the bundle stops the build: its license must first be added to
# Matcha/Resources/ThirdPartyNotices.txt.
set -euo pipefail

cd "$(dirname "$0")/.."

OPENBLOCK_REPOSITORY="https://github.com/Labbs/openblock.git"
OPENBLOCK_TAG="v1.2.0"
OPENBLOCK_COMMIT="40b110f8425acd6ee7c0bf5bdb4c582b9a94728e"
SOURCES="scripts/note-editor"
OUTPUT="Matcha/Resources/NoteEditor"
MANIFEST="$SOURCES/note-editor.sha256"
# Packages whose license is in ThirdPartyNotices.txt; `prosemirror-*` covers all of ProseMirror's.
ALLOWED_PACKAGES="@labbs/openblock-core @labbs/openblock-react prosemirror-* orderedmap rope-sequence w3c-keyname uuid react react-dom scheduler"

VERIFY=false
[[ "${1:-}" == "--verify" ]] && VERIFY=true

for tool in git node pnpm shasum; do
    command -v "$tool" > /dev/null || { echo "✗ $tool is missing (brew install node pnpm)"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "▸ OpenBlock $OPENBLOCK_TAG"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$OPENBLOCK_TAG" "$OPENBLOCK_REPOSITORY" "$WORK/openblock"
commit=$(git -C "$WORK/openblock" rev-parse HEAD)
if [[ "$commit" != "$OPENBLOCK_COMMIT" ]]; then
    echo "✗ $OPENBLOCK_TAG is commit $commit, $OPENBLOCK_COMMIT expected: the tag moved"
    exit 1
fi
(
    cd "$WORK/openblock"
    # The lockfile of v1.2.0 misses two optional peers added to core's package.json (yjs, y-prosemirror, which the
    # bundle doesn't use): the other packages keep the versions of the lockfile; `--verify` shows any drift.
    pnpm install --no-frozen-lockfile --ignore-scripts --reporter=silent
    pnpm --filter @labbs/openblock-core run build > /dev/null
    pnpm --filter @labbs/openblock-react run build > /dev/null
)

echo "▸ Page of the editor"
(cd "$SOURCES" && pnpm install --frozen-lockfile --ignore-scripts --reporter=silent)
mkdir -p "$WORK/out"
modules="$PWD/$SOURCES/node_modules"
"$SOURCES/node_modules/.bin/esbuild" "$SOURCES/src/main.tsx" \
    --bundle --minify --format=iife --target=safari18 --jsx=automatic --charset=utf8 --legal-comments=none \
    --define:process.env.NODE_ENV='"production"' \
    --alias:@labbs/openblock-core="$WORK/openblock/packages/core/dist/index.js" \
    --alias:@labbs/openblock-react="$WORK/openblock/packages/react/dist/index.js" \
    --alias:react="$modules/react" --alias:react-dom="$modules/react-dom" \
    --metafile="$WORK/meta.json" --log-level=warning \
    --outfile="$WORK/out/note-editor.js"

# Packages in the bundle: the folder after the last `node_modules/` of each input, or OpenBlock's own sources.
packages=$(node -e '
    const inputs = Object.keys(require(process.argv[1]).inputs);
    const names = new Set(inputs.map((path) => {
        if (path.includes("/openblock/packages/core/")) return "@labbs/openblock-core";
        if (path.includes("/openblock/packages/react/")) return "@labbs/openblock-react";
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
