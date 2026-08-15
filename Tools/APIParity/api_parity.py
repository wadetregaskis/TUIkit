#!/usr/bin/env python3
"""Compare TUIkit's public API against SwiftUI's, symbol by symbol.

    Tools/APIParity/api_parity.py            # extract, compare, report
    Tools/APIParity/api_parity.py --check    # same, but exit 1 on new gaps (CI)
    Tools/APIParity/api_parity.py --accept   # record today's gaps as the baseline
    Tools/APIParity/api_parity.py --stale    # only audit the curated map

Everything the comparison rests on is derived, never asserted:

  * Both sides come from `swift symbolgraph-extract`, run with the same flags,
    so any bias in what counts as public applies equally.
  * SwiftUI is TWO frameworks. `View`, `Text`, `Binding` and most modifiers
    live in SwiftUICore, not SwiftUI; extracting only SwiftUI hides most of it.
  * A symbol graph replicates every protocol-extension member onto every
    conforming type — 79,162 of SwiftUI's 83,254 entries on the SDK this was
    written against. Those are one declaration each and are dropped.
  * Deprecated and unavailable symbols are dropped from both sides. Keeping
    them makes live API look missing: SwiftUI deprecated `foregroundColor`,
    which TUIkit has, so an unfiltered diff reports it as absent from BOTH.

What is left is a real difference, and every real difference is either
explained by `parity-map.json` or reported. The map is the curated half — a
rename TUIkit made on purpose, or a capability a character grid cannot carry —
and the tool audits it back: an entry naming a symbol that no longer exists, or
claiming something is unimplemented when it now is, is reported as STALE. A map
that is never wrong is a map nobody is reading.

Requires macOS with Xcode: SwiftUI's symbol graph comes out of the SDK.
"""
import argparse
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MAP_PATH = os.path.join(HERE, "parity-map.json")
BASELINE_PATH = os.path.join(HERE, "baseline.json")

# How many owner groups to print before deferring to --json.
LIST_LIMIT = 30

SWIFTUI_MODULES = ["SwiftUI", "SwiftUICore"]
TUIKIT_MODULES = ["TUIkit", "TUIkitCore", "TUIkitStyling", "TUIkitView"]

# The symbol kinds a caller can name. Deliberately excludes the ones that are
# artefacts of how a type is spelled rather than API anyone writes.
KINDS = {
    "swift.struct": "struct", "swift.class": "class", "swift.enum": "enum",
    "swift.protocol": "protocol", "swift.actor": "actor",
    "swift.type.method": "static func", "swift.method": "func",
    "swift.type.property": "static var", "swift.property": "var",
    "swift.init": "init", "swift.enum.case": "case",
    "swift.typealias": "typealias", "swift.func": "global func",
    "swift.var": "global var", "swift.subscript": "subscript",
    "swift.type.subscript": "static subscript",
    "swift.associatedtype": "associatedtype",
}


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def sdk_path():
    result = run(["xcrun", "--show-sdk-path"])
    if result.returncode:
        sys.exit("no SDK: this tool needs macOS with Xcode installed")
    return result.stdout.strip()


def toolchain_version():
    """Stamped into the report and the baseline: a symbol graph is only
    reproducible against the toolchain that produced it."""
    result = run(["swift", "--version"])
    return result.stdout.strip().splitlines()[0] if result.stdout else "unknown"


def extract(modules, out_dir, search_paths, sdk, target):
    os.makedirs(out_dir, exist_ok=True)
    for module in modules:
        command = [
            "swift", "symbolgraph-extract", "-module-name", module,
            "-target", target, "-sdk", sdk,
            "-output-dir", out_dir, "-minimum-access-level", "public",
        ]
        for path in search_paths:
            command += ["-I", path]
        result = run(command)
        if result.returncode:
            sys.exit(f"symbolgraph-extract failed for {module}:\n{result.stderr}")


def load_symbols(directory, modules):
    """Every public, live, first-party declaration in these modules.

    Keyed by "Owner.name" — a `View` modifier is `View.padding(_:)`, a
    top-level type is just its name. Overloads collapse onto one key on
    purpose: this compares vocabulary, and a signature diff belongs to the
    compile corpus (see the README), not here.
    """
    wanted = set(modules)
    symbols = {}
    for entry in sorted(os.listdir(directory)):
        if not entry.endswith(".symbols.json"):
            continue
        # "SwiftUI@SwiftUICore.symbols.json" is SwiftUI's extensions to
        # SwiftUICore types — where a good many View modifiers actually live.
        owner_module = entry.split(".symbols.json")[0].split("@")[0]
        if owner_module not in wanted:
            continue
        with open(os.path.join(directory, entry)) as handle:
            graph = json.load(handle)
        for symbol in graph.get("symbols", []):
            kind = KINDS.get(symbol.get("kind", {}).get("identifier"))
            if not kind:
                continue
            # One declaration replicated onto every conforming type.
            if "::SYNTHESIZED::" in symbol.get("identifier", {}).get("precise", ""):
                continue
            parts = symbol.get("pathComponents") or []
            if not parts or any(part.startswith("_") for part in parts):
                continue
            if unavailable(symbol):
                continue
            key = ".".join(parts)
            symbols.setdefault(key, kind)
    return symbols


def unavailable(symbol):
    """Deprecated, obsoleted or unavailable — the source-compatibility tail."""
    for entry in symbol.get("availability") or []:
        if entry.get("isUnconditionallyUnavailable"):
            return True
        if entry.get("isUnconditionallyDeprecated") or "deprecated" in entry:
            return True
        if "obsoleted" in entry:
            return True
    return False


def load_map():
    with open(MAP_PATH) as handle:
        return json.load(handle)


def explain(key, parity_map):
    """Why this SwiftUI symbol is absent, or None if nothing explains it.

    An explanation is inherited by everything inside it. `AccessibilityRotor`
    being deliberately absent explains `AccessibilityRotor.Body` too — listing
    the members of a type nobody implements would bury the map in entries that
    all say the same thing, and would demand a new one every time Apple adds a
    property to a type this framework was never going to have.
    """
    parts = key.split(".")
    for depth in range(len(parts), 0, -1):
        prefix = ".".join(parts[:depth])
        entry = parity_map["renamed"].get(prefix)
        if entry:
            return ("renamed", entry, prefix)
        entry = parity_map["differentShape"].get(prefix)
        if entry:
            return ("different-shape", entry, prefix)
        entry = parity_map["notImplemented"].get(prefix)
        if entry:
            return ("not-implemented", entry, prefix)
        for rule in parity_map["families"]:
            if any(fnmatch.fnmatch(prefix, pattern) for pattern in rule["match"]):
                return ("family", rule, prefix)
    return None


def signature(key):
    """("View.border", ("_", "color")) — the name, and its argument labels."""
    if "(" not in key:
        return key, None
    base, rest = key.split("(", 1)
    return base, tuple(label for label in rest.rstrip(")").split(":") if label)


def label_deviations(swiftui, tuikit):
    """Absent SwiftUI symbols whose name AND arity TUIkit has, spelled
    differently.

    A different label is worse than an absence: the capability is there, so
    nobody notices it is unreachable until SwiftUI source fails to compile
    against it. Argument labels are the API — types may legitimately differ
    (a terminal counts cells where SwiftUI counts points), labels may not,
    unless the behaviour genuinely differs too.

    Arity has to match for this to mean anything; without it every missing
    overload would look like a misspelling.
    """
    by_name = {}
    for key in tuikit:
        name, labels = signature(key)
        if labels is not None:
            by_name.setdefault(name, []).append((labels, key))
    found = {}
    for key in swiftui:
        if key in tuikit:
            continue
        name, labels = signature(key)
        if labels is None or name not in by_name:
            continue
        same_arity = [
            other for other_labels, other in by_name[name]
            if len(other_labels) == len(labels) and other_labels != labels
        ]
        if same_arity:
            found[key] = sorted(same_arity)
    return found


def compare(swiftui, tuikit, parity_map):
    absent = {key: kind for key, kind in swiftui.items() if key not in tuikit}
    gaps, explained = {}, {}
    for key, kind in sorted(absent.items()):
        reason = explain(key, parity_map)
        (explained if reason else gaps)[key] = (kind, reason)
    return gaps, explained


def audit_map(swiftui, tuikit, parity_map):
    """The map, checked against reality. Three ways an entry rots."""
    stale = []
    for key, entry in sorted(parity_map["renamed"].items()):
        if key not in swiftui:
            stale.append((key, "renamed", "SwiftUI no longer has this symbol"))
        elif entry["tuikit"] not in tuikit:
            stale.append(
                (key, "renamed",
                 f"TUIkit no longer has the replacement `{entry['tuikit']}`"))
    for section in ("notImplemented", "differentShape"):
        for key in sorted(parity_map[section]):
            if key not in swiftui:
                stale.append((key, section, "SwiftUI no longer has this symbol"))
            elif key in tuikit:
                stale.append((key, section,
                              "TUIkit has this symbol now — delete the entry"))
    # A family rule that no longer matches anything absent is either obsolete
    # or was always too narrow to earn its keep.
    absent = {key for key in swiftui if key not in tuikit}
    for rule in parity_map["families"]:
        if not any(
            fnmatch.fnmatch(key, pattern)
            for pattern in rule["match"] for key in absent
        ):
            stale.append((", ".join(rule["match"]), "family", "matches nothing absent"))
    return stale


def report(swiftui, tuikit, gaps, explained, stale, deviations, baseline):
    print(f"toolchain:  {toolchain_version()}")
    print(f"SwiftUI:    {len(swiftui):>5} live public symbols "
          f"({'+'.join(SWIFTUI_MODULES)})")
    print(f"TUIkit:     {len(tuikit):>5} live public symbols "
          f"({', '.join(TUIKIT_MODULES)})")
    shared = len(set(swiftui) & set(tuikit))
    print(f"shared:     {shared:>5} symbols by name")
    print(f"explained:  {len(explained):>5} absent but accounted for "
          f"(renamed or deliberately not implemented)")
    print(f"gaps:       {len(gaps):>5} absent and unexplained")

    known = set(baseline.get("gaps", []))
    new = sorted(set(gaps) - known)
    fixed = sorted(known - set(gaps))

    if gaps:
        print("\nUnexplained differences — SwiftUI has these, TUIkit does not.")
        print("Grouped by the type they belong to; a bare name is a top-level type.")
        by_owner = {}
        for key in gaps:
            owner = key.split(".")[0] if "." in key else "(top level)"
            by_owner.setdefault(owner, []).append(key)
        shown = 0
        for owner in sorted(by_owner, key=lambda o: (-len(by_owner[o]), o)):
            members = sorted(by_owner[owner])
            if shown >= LIST_LIMIT:
                print(f"  … and {len(by_owner) - shown} more owners "
                      f"(use --json for the full list)")
                break
            names = [m.split(".", 1)[1] if "." in m else m for m in members]
            head = ", ".join(names[:8])
            more = f" … +{len(names) - 8}" if len(names) > 8 else ""
            print(f"  {owner} ({len(names)}): {head}{more}")
            shown += 1

    if deviations:
        accepted = set(baseline.get("labelDeviations", []))
        fresh = sorted(set(deviations) - accepted)
        print(f"\nARGUMENT-LABEL deviations ({len(deviations)}, {len(fresh)} new) — "
              f"same name and arity, different spelling.")
        print("A label difference is not a rename: SwiftUI source will not compile.")
        for key in (fresh or sorted(deviations))[:LIST_LIMIT]:
            mark = "NEW " if key in set(fresh) else "    "
            print(f"  {mark}SwiftUI {key}")
            for candidate in deviations[key][:2]:
                print(f"       TUIkit  {candidate}")
        if len(fresh or deviations) > LIST_LIMIT:
            print(f"  … and {len(fresh or deviations) - LIST_LIMIT} more")

    if stale:
        print(f"\nSTALE map entries ({len(stale)}) — the map disagrees with reality:")
        for key, section, why in stale:
            print(f"  [{section}] {key}: {why}")

    if new:
        print(f"\n{len(new)} NEW gap(s) since the baseline:")
        for key in new[:LIST_LIMIT]:
            print(f"  + {key}")
        if len(new) > LIST_LIMIT:
            print(f"  … and {len(new) - LIST_LIMIT} more")
    if fixed:
        print(f"\n{len(fixed)} baseline gap(s) no longer missing "
              f"(run --accept to record):")
        for key in fixed[:LIST_LIMIT]:
            print(f"  - {key}")
        if len(fixed) > LIST_LIMIT:
            print(f"  … and {len(fixed) - LIST_LIMIT} more")
    return new, fixed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if there are new gaps or stale map entries (CI)")
    parser.add_argument("--accept", action="store_true",
                        help="record the current gaps as the baseline")
    parser.add_argument("--stale", action="store_true",
                        help="only audit the curated map")
    parser.add_argument("--json", metavar="PATH", help="also write the full result as JSON")
    parser.add_argument("--work-dir", help="keep the symbol graphs here (they are large)")
    parser.add_argument("--target", default="arm64-apple-macosx26.0")
    args = parser.parse_args()

    sdk = sdk_path()
    work = args.work_dir or tempfile.mkdtemp(prefix="api-parity-")
    keep = bool(args.work_dir)
    try:
        swiftui_dir = os.path.join(work, "swiftui")
        tuikit_dir = os.path.join(work, "tuikit")

        # TUIkit's modules have to exist before they can be read.
        built = run(["swift", "build"], cwd=REPO)
        if built.returncode:
            sys.exit(f"swift build failed:\n{built.stderr}")
        modules = os.path.join(REPO, ".build", "arm64-apple-macosx", "debug", "Modules")
        if not os.path.isdir(modules):
            sys.exit(f"built modules not found at {modules}")

        extract(SWIFTUI_MODULES, swiftui_dir, [], sdk, args.target)
        extract(TUIKIT_MODULES, tuikit_dir, [modules], sdk, args.target)

        swiftui = load_symbols(swiftui_dir, SWIFTUI_MODULES)
        tuikit = load_symbols(tuikit_dir, TUIKIT_MODULES)
        parity_map = load_map()

        stale = audit_map(swiftui, tuikit, parity_map)
        if args.stale:
            for key, section, why in stale:
                print(f"[{section}] {key}: {why}")
            print(f"{len(stale)} stale entries")
            return 1 if (stale and args.check) else 0

        gaps, explained = compare(swiftui, tuikit, parity_map)
        baseline = {}
        if os.path.exists(BASELINE_PATH):
            with open(BASELINE_PATH) as handle:
                baseline = json.load(handle)
        deviations = label_deviations(swiftui, tuikit)
        new, fixed = report(
            swiftui, tuikit, gaps, explained, stale, deviations, baseline)
        new_deviations = sorted(
            set(deviations) - set(baseline.get("labelDeviations", [])))

        if args.json:
            with open(args.json, "w") as handle:
                json.dump({
                    "toolchain": toolchain_version(),
                    "counts": {"swiftui": len(swiftui), "tuikit": len(tuikit),
                               "gaps": len(gaps), "explained": len(explained)},
                    "gaps": sorted(gaps),
                    "labelDeviations": {k: v for k, v in sorted(deviations.items())},
                    "stale": [{"key": k, "section": s, "why": w} for k, s, w in stale],
                }, handle, indent=1)

        if args.accept:
            with open(BASELINE_PATH, "w") as handle:
                json.dump({
                    "comment": "Gaps accepted as known. Re-record with --accept "
                               "when one is closed or a new one is agreed.",
                    "toolchain": toolchain_version(),
                    "gaps": sorted(gaps),
                    "labelDeviations": sorted(deviations),
                }, handle, indent=1)
            print(f"\nbaseline recorded: {len(gaps)} gaps")
            return 0

        if args.check and (new or stale or new_deviations):
            print("\nFAIL: new unexplained differences, or the map has gone stale.")
            print("Either implement the API, add it to parity-map.json with a "
                  "reason, or run --accept if it is a gap you are accepting.")
            return 1
        return 0
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
