#!/bin/bash
# Run by the “Build Commit” build phase of the Matcha target: writes the commit of a Debug build (“3f2a9c1”, with
# “-dirty” when the working tree has changes) to BuildCommit.txt in the app's resources. About Matcha shows it in
# place of the build number (AboutVersion). Other configurations get an empty file: a published build shows its
# version. Without git or outside a repository, the file stays empty.
# Needs the target's “User Script Sandboxing” off: git reads the whole repository.
set -euo pipefail

output="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/BuildCommit.txt"
mkdir -p "$(dirname "$output")"
commit=""
if [[ "$CONFIGURATION" == "Debug" ]] && commit="$(git -C "$SRCROOT" rev-parse --short HEAD 2>/dev/null)"; then
    if [[ -n "$(git -C "$SRCROOT" status --porcelain 2>/dev/null)" ]]; then
        commit+="-dirty"
    fi
fi
printf '%s' "$commit" > "$output"
