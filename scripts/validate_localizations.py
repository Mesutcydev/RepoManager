#!/usr/bin/env python3
"""Check translation coverage, format arguments, and tool presentation metadata.

Optionally pass --stringsdata-dir <DerivedData/Build> after an Xcode build to
also verify every compiler-extracted key against its owning bundle's catalog.
No network access or third-party Python dependencies are required.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"en", "hi", "de", "es", "ar", "tr", "ja"}
CATALOGS = {
    "app": "App/Localizable.xcstrings",
    "share": "ShareExtension/Localizable.xcstrings",
    "core": "Packages/RepoManagerCore/Sources/RepoManagerCore/Resources/Localizable.xcstrings",
    "ui": "Packages/RepoManagerUI/Sources/RepoManagerUI/Resources/Localizable.xcstrings",
}
FORMAT = re.compile(r"%(?:(\d+)\$)?([-+ #0]*\d*(?:\.\d+)?(?:ll|l|h|z|t|j|L)?[@diuoxXfFeEgGcCsSp])")


def signature(value):
    result = Counter()
    for index, match in enumerate(FORMAT.finditer(value.replace("%%", "")), 1):
        result[(int(match[1] or index), match[2])] += 1
    return result


def units(node):
    if "stringUnit" in node:
        yield node["stringUnit"]
    for value in node.get("variations", {}).values():
        for variant in value.values():
            yield from units(variant)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stringsdata-dir", type=Path)
    args = parser.parse_args()
    failures = []
    catalogs = {}
    translated = 0
    paths = list(CATALOGS.values()) + ["App/InfoPlist.xcstrings", "ShareExtension/InfoPlist.xcstrings"]
    for relative in paths:
        catalog = json.loads((ROOT / relative).read_text())
        catalogs[relative] = catalog["strings"]
        if catalog["sourceLanguage"] != "en":
            failures.append(f"{relative}: English source language required")
        for key, entry in catalog["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            locales = entry.get("localizations", {})
            if set(locales) != LANGUAGES:
                failures.append(f"{relative}: {key!r}: missing/extra locales {set(locales) ^ LANGUAGES}")
            source_units = list(units(locales.get("en", {})))
            expected = signature(source_units[0]["value"] if source_units else key)
            for language, localization in locales.items():
                values = list(units(localization))
                if not values:
                    failures.append(f"{relative}: {key!r}: {language} has no translation")
                for unit in values:
                    if unit.get("state") != "translated" or not unit.get("value", "").strip():
                        failures.append(f"{relative}: {key!r}: {language} is incomplete")
                    if signature(unit.get("value", "")) != expected:
                        failures.append(f"{relative}: {key!r}: {language} format arguments differ")
            translated += 1

    for target in ["App", "ShareExtension"]:
        info = plistlib.loads((ROOT / target / "Info.plist").read_bytes())
        if set(info.get("CFBundleLocalizations", [])) != LANGUAGES:
            failures.append(f"{target}: supported language declaration differs")
        permission_keys = {k for k in info if k.startswith("NS") and k.endswith("UsageDescription")}
        if not permission_keys <= catalogs[f"{target}/InfoPlist.xcstrings"].keys():
            failures.append(f"{target}: untranslated system permission prompt")

    metadata = catalogs[CATALOGS["core"]]
    def check_schema(schema):
        for key, rule in schema.get("properties", {}).items():
            if key.replace("_", " ").title() not in metadata:
                failures.append(f"Missing schema label: {key}")
            check_schema(rule)
        if "items" in schema:
            check_schema(schema["items"])

    for tool in json.loads((ROOT / "Docs/tool-catalog.json").read_text())["tools"]:
        for key in [tool["name"].replace("_", " ").title(), tool["group"], tool["description"]]:
            if key not in metadata:
                failures.append(f"Missing tool presentation: {key}")
        check_schema(tool["schema"])

    checked_extractions = 0
    if args.stringsdata_dir:
        # arm64 is the simulator/device architecture used by the localization QA
        # build; ignore stale output from other architectures in DerivedData.
        extracted = list(args.stringsdata_dir.rglob("*.stringsdata"))
        if not extracted:
            failures.append("No compiler-extracted strings found")
        for path in extracted:
            if "arm64" not in path.parts:
                continue
            data = json.loads(path.read_text())
            source = data["source"]
            bundle = "core" if "/RepoManagerCore/Sources/RepoManagerCore/" in source else "ui" if "/RepoManagerUI/Sources/" in source else "share" if "/ShareExtension/" in source else "app"
            for key in [row["key"] for row in data.get("tables", {}).get("Localizable", [])]:
                if key not in catalogs[CATALOGS[bundle]]:
                    failures.append(f"{source}: unlocalized extracted key {key!r}")
                checked_extractions += 1
    print(json.dumps({"passed": not failures, "languages": sorted(LANGUAGES), "translated_entries": translated,
                      "compiler_keys_checked": checked_extractions, "failures": failures}, ensure_ascii=False, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
