#!/usr/bin/env bash
# Checks the string catalogs (Localizable.xcstrings, InfoPlist.xcstrings) without building:
# the keys are those the compiler extracted during the last build in build/
# (.stringsdata files) and those of the produced Info.plist. Reports keys missing from the catalog,
# stale keys, any key without a “translated” value in one of the app's languages (plurals included,
# with each of their categories) and any English text of the catalog that no longer matches the code
# or the Info.plist (its translations then need review).
#
# Usage: scripts/check-localizations.sh   (after the Debug build described in CLAUDE.md)
#        CONFIGURATION=Release scripts/check-localizations.sh
# Exit code: 0 if everything is in order, 1 otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

exec python3 -I - <<'PYTHON'
import glob
import json
import os
import plistlib
import re
import sys

ROOT = os.getcwd()
TARGET = "Matcha"
INTERMEDIATES = os.path.join(ROOT, "build/Build/Intermediates.noindex", f"{TARGET}.build")
PRODUCTS = os.path.join(ROOT, "build/Build/Products")
# Info.plist keys that we translate, and those that Xcode may add to the catalog on its own.
INFO_PLIST_KEY = re.compile(r"^(NS\w+UsageDescription|CFBundleDisplayName|CFBundleSpokenName|NSHumanReadableCopyright)$")
INFO_PLIST_OPTIONAL = {"CFBundleName"}
# Plural categories required per language (CLDR); “other” is the fallback for the others (many…).
REQUIRED_PLURALS = {language: {"one", "other"} for language in ("en", "fr", "de", "es", "it")}
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfFeEgGcCsSpaA]")

problems = []


def fail(message):
    print(f"✗ {message}")
    sys.exit(1)


def app_languages():
    """App languages: the project's knownRegions, without the source language or Base."""
    with open(os.path.join(ROOT, f"{TARGET}.xcodeproj/project.pbxproj"), encoding="utf-8") as file:
        project = file.read()
    regions = re.search(r"knownRegions = \(([^)]*)\);", project)
    development = re.search(r"developmentRegion = (\w+);", project)
    if not regions or not development:
        fail("knownRegions ou developmentRegion introuvable dans project.pbxproj")
    names = [name.strip().strip('"') for name in regions.group(1).split(",") if name.strip()]
    return development.group(1), [name for name in names if name not in ("Base", development.group(1))]


def last_build():
    """Intermediate folder and product of the last build (or of $CONFIGURATION)."""
    configuration = os.environ.get("CONFIGURATION")
    pattern = os.path.join(INTERMEDIATES, configuration or "*", f"{TARGET}.build/Objects-normal/*/{TARGET}.SwiftFileList")
    lists = glob.glob(pattern)
    if not lists:
        fail("aucune compilation trouvée dans build/ : compile d'abord l'app (commande de CLAUDE.md).")
    newest = max(lists, key=os.path.getmtime)
    configuration = newest[len(INTERMEDIATES) + 1 :].split(os.sep)[0]
    return configuration, os.path.dirname(newest)


def extracted_keys(objects):
    """Keys extracted per table, with their English text (`defaultValue` in the code, otherwise the key),
    for the files of the last build only."""
    with open(os.path.join(objects, f"{TARGET}.SwiftFileList"), encoding="utf-8") as file:
        sources = {line.strip() for line in file if line.strip()}
    tables, built = {}, {}
    for path in glob.glob(os.path.join(os.path.dirname(objects), "*", "*.stringsdata")):
        with open(path, encoding="utf-8") as file:
            data = json.load(file)
        source = data.get("source", "")
        if source.endswith(".swift") and source not in sources:
            continue  # file deleted since then: its strings no longer count
        # The compiler doesn't rewrite a .stringsdata whose strings haven't changed: the build date of
        # the file is the most recent of its outputs (.o, .d, .stringsdata).
        stem = os.path.splitext(path)[0]
        outputs = [path] + [stem + ext for ext in (".o", ".d") if os.path.exists(stem + ext)]
        built[source] = max(os.path.getmtime(output) for output in outputs)
        for table, entries in data.get("tables", {}).items():
            keys = tables.setdefault(table, {})
            for entry in entries:
                key, text = entry["key"], entry.get("value", entry["key"])
                if keys.get(key, text) != text:
                    problems.append(f"{table} : {key!r} a deux textes anglais dans le code : {keys[key]!r}, {text!r}")
                keys[key] = text
    # A build older than the sources would give a wrong list of keys.
    outdated = sorted(
        os.path.relpath(source, ROOT)
        for source in sources
        if source.startswith(os.path.join(ROOT, TARGET) + os.sep)
        and os.path.exists(source)
        and os.path.getmtime(source) > built.get(source, 0)
    )
    current = {
        path
        for path in glob.glob(os.path.join(ROOT, TARGET, "**", "*.swift"), recursive=True)
    }
    added = sorted(os.path.relpath(path, ROOT) for path in current - sources)
    removed = sorted(
        os.path.relpath(source, ROOT)
        for source in sources
        if source.startswith(os.path.join(ROOT, TARGET) + os.sep) and not os.path.exists(source)
    )
    if outdated or added or removed:
        fail("compilation périmée, recompile avant de vérifier : " + ", ".join(outdated + added + removed))
    return tables


def info_plist_keys(configuration):
    path = os.path.join(PRODUCTS, configuration, f"{TARGET}.app/Contents/Info.plist")
    if not os.path.exists(path):
        fail(f"{os.path.relpath(path, ROOT)} introuvable : compile d'abord l'app.")
    if os.path.getmtime(os.path.join(ROOT, f"{TARGET}.xcodeproj/project.pbxproj")) > os.path.getmtime(path):
        fail("project.pbxproj a changé depuis la dernière compilation : recompile avant de vérifier.")
    with open(path, "rb") as file:
        info = plistlib.load(file)
    return {key: value for key, value in info.items() if isinstance(value, str) and INFO_PLIST_KEY.match(key)}


def find_catalog(table):
    matches = glob.glob(os.path.join(ROOT, TARGET, "**", f"{table}.xcstrings"), recursive=True)
    return matches[0] if len(matches) == 1 else None


def string_units(localization, path=()):
    """All the values of a language: the simple value and each variant (plural, device…)."""
    if "stringUnit" in localization:
        yield path, localization["stringUnit"]
    for kind, cases in localization.get("variations", {}).items():
        for case, value in cases.items():
            yield from string_units(value, path + (f"{kind}.{case}",))
    for name, substitution in localization.get("substitutions", {}).items():
        yield from string_units(substitution, path + (f"substitution {name}",))


def placeholders(text):
    return sorted(re.sub(r"^%\d+\$", "%", match) for match in PLACEHOLDER.findall(text.replace("%%", "")))


def check_catalog(table, expected, languages, optional=frozenset()):
    """`expected`: key → English text as built (code or Info.plist)."""
    path = find_catalog(table)
    if path is None:
        problems.append(f"{table} : catalogue {table}.xcstrings introuvable (ou en double) sous {TARGET}/")
        return 0
    with open(path, encoding="utf-8") as file:
        strings = json.load(file).get("strings", {})
    name = os.path.relpath(path, ROOT)
    keys = set(expected)
    for key in sorted(keys - set(strings)):
        problems.append(f"{name} : clé absente du catalogue : {key!r}")
    for key in sorted(set(strings) - keys - optional):
        problems.append(f"{name} : clé périmée (plus utilisée dans le code) : {key!r}")
    for key in sorted(set(strings) & (keys | optional)):
        entry = strings[key]
        if entry.get("extractionState") == "stale":
            problems.append(f"{name} : clé marquée « stale » alors qu'elle est utilisée : {key!r}")
        localizations = entry.get("localizations", {})
        source = localizations.get(SOURCE_LANGUAGE, {})
        source_is_plural = "plural" in source.get("variations", {})
        source_text = source.get("stringUnit", {}).get("value", key)
        if key in keys and not source_is_plural and source_text != expected[key]:
            problems.append(
                f"{name} : {key!r} : texte anglais modifié ({expected[key]!r} dans le code, "
                f"{source_text!r} dans le catalogue) : traductions à revoir"
            )
        if source_is_plural:
            missing = REQUIRED_PLURALS.get(SOURCE_LANGUAGE, {"other"}) - set(source["variations"]["plural"])
            if missing:
                problems.append(f"{name} : {key!r} sans pluriel {', '.join(sorted(missing))} en {SOURCE_LANGUAGE}")
        for language in languages:
            localization = localizations.get(language)
            if not localization:
                problems.append(f"{name} : {key!r} n'est pas traduite en {language}")
                continue
            units = list(string_units(localization))
            if not units:
                problems.append(f"{name} : {key!r} n'a aucune valeur en {language}")
            for variant, unit in units:
                where = f"{language} ({', '.join(variant)})" if variant else language
                if unit.get("state") != "translated" or not unit.get("value", "").strip():
                    problems.append(f"{name} : {key!r} n'est pas traduite en {where} (état {unit.get('state')!r})")
                elif not variant and table != "InfoPlist" and placeholders(unit["value"]) != placeholders(source_text):
                    problems.append(f"{name} : {key!r} en {where} n'a pas les mêmes paramètres que la clé")
            plural = localization.get("variations", {}).get("plural")
            missing = REQUIRED_PLURALS.get(language, {"other"}) - set(plural or {})
            if source_is_plural and missing:
                problems.append(f"{name} : {key!r} sans pluriel {', '.join(sorted(missing))} en {language}")
    return len(expected)


development, languages = app_languages()
SOURCE_LANGUAGE = development
if not languages:
    fail("aucune langue de traduction dans knownRegions")
configuration, objects = last_build()
tables = extracted_keys(objects)
counts = {"Localizable": check_catalog("Localizable", tables.pop("Localizable", {}), languages)}
counts["InfoPlist"] = check_catalog("InfoPlist", info_plist_keys(configuration), languages, INFO_PLIST_OPTIONAL)
for table, keys in sorted(tables.items()):
    counts[table] = check_catalog(table, keys, languages)

if problems:
    for problem in problems:
        print(f"✗ {problem}")
    print(f"\n{len(problems)} problème(s) de traduction ({configuration}, langues : {', '.join(languages)}).")
    sys.exit(1)
summary = ", ".join(f"{table} {count} clés" for table, count in counts.items())
print(f"✓ Catalogues à jour et traduits ({configuration}) : {summary} ; langues : {development} (source), {', '.join(languages)}.")
PYTHON
