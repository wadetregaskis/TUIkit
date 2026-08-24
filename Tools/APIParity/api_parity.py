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
    them charges TUIkit with gaps for surface SwiftUI is itself retiring, and
    reports anything either side still has as absent from BOTH.

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


def load_symbols(directory, modules, collect_defaults=False):
    """Every public, live, first-party declaration in these modules.

    Keyed by "Owner.name" — a `View` modifier is `View.padding(_:)`, a
    top-level type is just its name. Overloads collapse onto one key on
    purpose: this compares vocabulary, and a signature diff belongs to the
    compile corpus (see the README), not here.

    With `collect_defaults`, also returns which parameters of each function
    carry a default value — what ``source_compatible`` needs to tell an added
    optional argument from a changed signature. An overloaded key keeps every
    overload's flags, because they are what distinguishes them here.
    """
    wanted = set(modules)
    symbols = {}
    defaults = {}
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
            if collect_defaults:
                defaults.setdefault(key, []).append(defaulted_parameters(symbol))
    return (symbols, defaults) if collect_defaults else symbols


def defaulted_parameters(symbol):
    """Which of this function's parameters have a default, in order.

    Read off `declarationFragments`, which is where a symbol graph renders
    ` = nil`; the per-parameter fragments omit defaults entirely. The scan
    walks the fragment list rather than the rendered string because a
    parameter list is full of commas, angle brackets and `->` that no amount
    of bracket-counting parses reliably: `externalParam` starts a parameter,
    and an `=` before the next one means that parameter is defaulted. It stops
    when the parameter list closes, so the `==` in a `where` clause cannot be
    mistaken for a default on the last parameter.
    """
    fragments = symbol.get("declarationFragments") or []
    depth, started, closed, defaulted = 0, False, False, []
    for fragment in fragments:
        if closed:
            break
        kind, spelling = fragment.get("kind"), fragment.get("spelling", "")
        if kind == "text":
            # Character by character: a fragment can both carry a default and
            # close the list (`" = 1) -> "`), so this cannot stop at fragment
            # granularity without losing the last parameter's default.
            for character in spelling:
                if character == "(":
                    depth += 1
                    started = True
                elif character == ")":
                    depth -= 1
                    if started and depth <= 0:
                        closed = True
                        break
                elif character == "=" and depth == 1 and defaulted:
                    defaulted[-1] = True
        elif kind == "externalParam" and depth == 1:
            defaulted.append(False)
    return defaulted


def omittable(wanted, labels, defaulted):
    """Can `wanted` be spelled by omitting only DEFAULTED parameters?

    Swift lets a call skip a defaulted parameter from ANYWHERE in the list, not
    just the tail — `f(a: 1, c: 2)` binds to `f(a:b:c:)` when `b` has one — but
    it does NOT let the remaining arguments be reordered (SE-0060). So the test
    is an order-preserving subsequence, and every parameter the call skips over
    must carry a default.

    The match is greedy from the left, which is what Swift does with unlabelled
    parameters: given `f(_ a: Int = 0, _ b: Int)`, `f(5)` binds 5 to `a` and
    then fails for want of `b` rather than quietly meaning `b: 5`.
    """
    index = 0
    for position, label in enumerate(labels):
        if index < len(wanted) and wanted[index] == label:
            index += 1
        elif not defaulted[position]:
            return False
    return index == len(wanted)


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


def source_compatible(swiftui, tuikit, tuikit_defaults):
    """Absent SwiftUI symbols that a SwiftUI call site nonetheless compiles to.

    TUIkit is aiming at SOURCE compatibility, not identical declarations, so a
    TUIkit function may add optional parameters of its own:
    `alert(_:isPresented:actions:message:)` is spelled
    `alert(_:isPresented:actions:message:borderStyle:borderColor:titleColor:)`
    here, and `border(_:width:)` is `border(_:style:width:)`. The SwiftUI call
    compiles verbatim in both cases. Comparing argument labels alone cannot see
    that, so those read as gaps — the report claiming TUIkit has no `.alert`,
    which is false, and a report that cries wolf is one nobody reads.

    The extras need not be trailing: `omittable` implements Swift's actual rule
    — skip any DEFAULTED parameter, from anywhere, but never reorder what is
    left. Requiring a prefix instead (the first version of this) was sound but
    incomplete, and missed `border(_:width:)` and `ScrollView(_:content:)`
    precisely because the added parameter sits in the middle.

    What it proves is that the call COMPILES, not that it MEANS the same
    thing: `fixedSize()` reaches `fixedSize(horizontal:vertical:)` whatever
    those defaults are, and it is only right because TUIkit defaults both to
    `true` as SwiftUI does. Flipping such a default would turn a match here
    into a silent behaviour difference, which is why every one of these is
    printed rather than quietly folded into the explained count — and why each
    also appears in `CompileCorpus.swift`, where the compiler has the last word.
    """
    by_name = {}
    for key in tuikit:
        name, labels = signature(key)
        if labels is not None:
            by_name.setdefault(name, []).append((labels, key))
    # The value recorded is A satisfying overload, not necessarily the one
    # Swift's overload resolution would pick, and not a promise that exactly
    # one qualifies — two equally-good candidates would make the call
    # ambiguous and so uncompilable. `CompileCorpus.swift` is what rules that
    # out; this can only ever say "something here accepts those labels".
    satisfied = {}
    for key in sorted(swiftui):
        if key in tuikit:
            continue
        name, labels = signature(key)
        if labels is None or name not in by_name:
            continue
        for other_labels, other in sorted(by_name[name]):
            if len(other_labels) <= len(labels):
                continue
            # One entry per overload sharing the key; any of them satisfying
            # the call is enough, and only the one whose arity matches its own
            # flag list can be judged at all.
            for defaulted in tuikit_defaults.get(other, []):
                if len(defaulted) != len(other_labels):
                    continue
                if omittable(labels, other_labels, defaulted):
                    satisfied[key] = other
                    break
            if key in satisfied:
                break
    return satisfied


def compare(swiftui, tuikit, parity_map, compatible=None):
    absent = {key: kind for key, kind in swiftui.items() if key not in tuikit}
    compatible = compatible or {}
    gaps, explained = {}, {}
    for key, kind in sorted(absent.items()):
        if key in compatible:
            # Not absent in any sense a call site can tell — see
            # `source_compatible`. Counted with the explained, since that is
            # what "accounted for" means here.
            explained[key] = (kind, {"why": f"added optional arguments: `{compatible[key]}`"})
            continue
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
    # A family pattern that matches nothing absent is either obsolete or was
    # always wrong. Checked one PATTERN at a time, not one rule at a time: a
    # rule is a list of spellings for the same reason, and a live sibling hides
    # a dead one indefinitely. `View.gesture` sat dead in the gesture family for
    # as long as `*Gesture` next to it kept matching, and the nine symbols it
    # was written for were reported as unexplained gaps the whole time.
    absent = {key for key in swiftui if key not in tuikit}
    for rule in parity_map["families"]:
        for pattern in rule["match"]:
            if not any(fnmatch.fnmatch(key, pattern) for key in absent):
                stale.append((pattern, "family", "matches nothing absent"))
    return stale


def report(swiftui, tuikit, gaps, explained, stale, deviations, baseline, compatible=None):
    print(f"toolchain:  {toolchain_version()}")
    recorded = baseline.get("toolchain")
    if recorded and recorded != toolchain_version():
        print(f"  BASELINE RECORDED AGAINST: {recorded}")
    print(f"SwiftUI:    {len(swiftui):>5} live public symbols "
          f"({'+'.join(SWIFTUI_MODULES)})")
    print(f"TUIkit:     {len(tuikit):>5} live public symbols "
          f"({', '.join(TUIKIT_MODULES)})")
    shared = len(set(swiftui) & set(tuikit))
    print(f"shared:     {shared:>5} symbols by name")
    if compatible:
        print(f"compatible: {len(compatible):>5} spelled with extra OPTIONAL arguments "
              f"(SwiftUI source still compiles)")
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

    if compatible:
        print("\nSpelled with extra OPTIONAL arguments — SwiftUI's call site compiles "
              "verbatim.\nListed in full: the rule proves SOME overload accepts those "
              "labels, not what the\ncall means nor which overload wins "
              "(see `source_compatible` and CompileCorpus.swift).")
        for key in sorted(compatible):
            print(f"  {key}\n      <- {compatible[key]}")

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
        tuikit, tuikit_defaults = load_symbols(
            tuikit_dir, TUIKIT_MODULES, collect_defaults=True)
        compatible = source_compatible(swiftui, tuikit, tuikit_defaults)
        parity_map = load_map()

        stale = audit_map(swiftui, tuikit, parity_map)
        if args.stale:
            for key, section, why in stale:
                print(f"[{section}] {key}: {why}")
            print(f"{len(stale)} stale entries")
            return 1 if (stale and args.check) else 0

        gaps, explained = compare(swiftui, tuikit, parity_map, compatible)
        baseline = {}
        if os.path.exists(BASELINE_PATH):
            with open(BASELINE_PATH) as handle:
                baseline = json.load(handle)
        deviations = label_deviations(swiftui, tuikit)
        new, fixed = report(
            swiftui, tuikit, gaps, explained, stale, deviations, baseline,
            compatible)
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

        # `fixed` counts too. A closed gap left unrecorded is how the baseline
        # goes quietly out of date, and an out-of-date baseline is the one thing
        # that makes every other number here untrustworthy: `new` is measured
        # against it. The remedy is the same one command either way.
        if args.check and (new or fixed or stale or new_deviations):
            print("\nFAIL: the recorded baseline no longer describes reality.")
            print("Either implement the API, add it to parity-map.json with a "
                  "reason, or run --accept to record gaps you are accepting "
                  "and gaps you have closed.")
            recorded = baseline.get("toolchain")
            if recorded and recorded != toolchain_version():
                print("Note: the baseline was recorded against a DIFFERENT "
                      "toolchain, which is enough on its own to move these "
                      "numbers. Compare against a matching one before reading "
                      "the differences as real.")
            return 1
        return 0
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
