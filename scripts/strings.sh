#!/bin/bash
# Shows the texts of one language of the catalogs, readable in the terminal: English → translation.
#
#   scripts/strings.sh fr               all the texts in French
#   scripts/strings.sh de --missing     only what is missing or needs review in German
#   scripts/strings.sh it --comments    with the comment left for translators
#
# Languages: fr, de, es, it (en shows the English texts). Changes nothing.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -lt 1 ]]; then
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

exec python3 -I - "$@" <<'PYTHON'
import json
import sys

language = sys.argv[1]
show_missing_only = "--missing" in sys.argv[2:]
show_comments = "--comments" in sys.argv[2:]
catalogs = ["Matcha/Resources/Localizable.xcstrings", "Matcha/Resources/InfoPlist.xcstrings"]

color = sys.stdout.isatty()
def paint(text, code):
    return f"\033[{code}m{text}\033[0m" if color else text
dim = lambda text: paint(text, "2")
warn = lambda text: paint(text, "31")
title = lambda text: paint(text, "1")

STATES = {"translated": None, "new": "à traduire", "needs_review": "à revoir", "stale": "plus utilisé"}

def units(localization):
    """(variant, text, state) of a localization: one line, or one per plural form."""
    if localization is None:
        return []
    plural = localization.get("variations", {}).get("plural")
    if plural:
        return [(form, entry["stringUnit"]["value"], entry["stringUnit"].get("state", "translated"))
                for form, entry in sorted(plural.items())]
    unit = localization.get("stringUnit")
    return [(None, unit["value"], unit.get("state", "translated"))] if unit else []

shown = missing = 0
for path in catalogs:
    try:
        with open(path, encoding="utf-8") as file:
            catalog = json.load(file)
    except FileNotFoundError:
        continue
    source_language = catalog.get("sourceLanguage", "en")
    print(title(f"── {path.split('/')[-1]} ({language}) ──"))
    for key in sorted(catalog["strings"], key=str.casefold):
        entry = catalog["strings"][key]
        # Never translated (a name, a symbol): neither shown nor counted (review DI11).
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        source = units(localizations.get(source_language)) or [(None, key, "translated")]
        target = units(localizations.get(language))
        if language == source_language:
            target = source
        by_form = {form: (text, state) for form, text, state in target}
        lines = []
        for form, english, _ in source:
            text, state = by_form.get(form, (None, "new"))
            problem = None if text is not None and state == "translated" else STATES.get(state, state)
            if problem or text is None:
                missing += 1
            if show_missing_only and not problem:
                continue
            label = f"[{form}] " if form else ""
            arrow = f"{dim(label + english)}  →  {text if text is not None else ''}"
            lines.append(arrow + (f"  {warn('[' + problem + ']')}" if problem else ""))
        if not lines:
            continue
        shown += 1
        print("\n".join(lines))
        if show_comments and entry.get("comment"):
            print(dim(f"    # {entry['comment']}"))
    print()

summary = f"{shown} texte(s) affiché(s)"
print(dim(summary + (f", {missing} à traduire ou à revoir" if missing else ", tout est traduit")))
PYTHON
