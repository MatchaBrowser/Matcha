"""Adds translated texts to the Localizable.xcstrings catalog, in the format and order that Xcode writes (keys
sorted by `localizedStandardCompare`, “ : ” separators), so that diffs stay small.

    python3 -I scripts/add-strings.py new.json
    python3 -I scripts/add-strings.py --check     # is the catalog in Xcode's order?
    python3 -I scripts/add-strings.py --remove "Old key" …   # removes keys no longer used by the code

`new.json`: {"English key": {"comment": "…", "fr": "…", "de": "…", "es": "…", "it": "…"}}; for a plural,
each language (English included) is {"one": "…", "other": "…"}. A key that is already present is rejected.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

CATALOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Matcha", "Resources", "Localizable.xcstrings")
LANGUAGES = ["de", "es", "fr", "it"]

SORTER = """
import Foundation
let path = CommandLine.arguments[1]
let keys = try! JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
let sorted = keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
FileHandle.standardOutput.write(try! JSONEncoder().encode(sorted))
"""


def xcode_order(keys):
    """Keys in Xcode's order (`localizedStandardCompare`, computed by Swift)."""
    folder = tempfile.mkdtemp()
    try:
        program = os.path.join(folder, "sort.swift")
        data = os.path.join(folder, "keys.json")
        with open(program, "w", encoding="utf-8") as file:
            file.write(SORTER)
        with open(data, "w", encoding="utf-8") as file:
            json.dump(keys, file, ensure_ascii=False)
        result = subprocess.run(["xcrun", "swift", program, data], capture_output=True, check=True)
        return json.loads(result.stdout)
    finally:
        shutil.rmtree(folder)


def sorted_value(value):
    if isinstance(value, dict):
        return {key: sorted_value(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [sorted_value(item) for item in value]
    return value


def dump(catalog):
    strings = catalog["strings"]
    ordered = {key: sorted_value(strings[key]) for key in xcode_order(list(strings))}
    rest = {key: sorted_value(catalog[key]) for key in sorted(catalog) if key != "strings"}
    document = {}
    for key in sorted(list(rest) + ["strings"]):
        document[key] = ordered if key == "strings" else rest[key]
    return json.dumps(document, indent=2, separators=(",", " : "), ensure_ascii=False)


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    if isinstance(value, dict):
        return {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}
    return unit(value)


def main(argv):
    with open(CATALOG, encoding="utf-8") as file:
        text = file.read()
    catalog = json.loads(text)
    if argv == ["--check"]:
        print("ordre de Xcode" if dump(catalog) == text else "ordre différent")
        return
    if argv[:1] == ["--remove"]:
        for key in argv[1:]:
            if catalog["strings"].pop(key, None) is None:
                sys.exit(f"Absent du catalogue : {key}")
        with open(CATALOG, "w", encoding="utf-8") as file:
            file.write(dump(catalog))
        return
    with open(argv[0], encoding="utf-8") as file:
        entries = json.load(file)
    for key, entry in entries.items():
        if key in catalog["strings"]:
            sys.exit(f"Déjà dans le catalogue : {key}")
        localizations = {language: localization(entry[language]) for language in LANGUAGES}
        if "en" in entry:
            localizations["en"] = localization(entry["en"])
        catalog["strings"][key] = {"localizations": localizations}
        if entry.get("comment"):
            catalog["strings"][key]["comment"] = entry["comment"]
    with open(CATALOG, "w", encoding="utf-8") as file:
        file.write(dump(catalog))


if __name__ == "__main__":
    main(sys.argv[1:])
