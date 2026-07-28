#!/usr/bin/env python3
"""Stage every library module's symbol graph as if it were one module.

TUIkit is split into five library modules for layering and test isolation
(TUIkitCore / TUIkitStyling / TUIkitView / TUIkitImage, plus the TUIkit
umbrella that `@_exported import`s them). That split is OUR business, not the
reader's: `import TUIkit` is one API, so the documentation has to be one API
reference.

DocC builds from symbol graphs, one module at a time, and an `@_exported`
re-export does not put the re-exported symbols into the importing module's
graph. Pointing DocC at the TUIkit target therefore produces an archive with
no page at all for `View`, `Color`, `Binding`, `State`, `FrameBuffer` — the
most basic types in the framework — and every catalog link to them dangles.

So: take the graphs for all five modules and rewrite the module identity to
`TUIkit` before handing them to `docc convert`. Three things need changing,
and all three matter:

  1. `module.name` — decides which module page a symbol is filed under, and
     hence its URL. Without this the pages land under /documentation/tuikitcore.
  2. `swiftExtension.extendedModule` on every symbol — DocC treats an
     extension whose extended module differs from the current one as an
     extension to an *external* type and does not give its members pages.
     `extension View { … }` declared in TUIkit is exactly that shape, so
     leaving it alone costs you every `View` modifier.
  3. The FILE NAME — DocC decides "is this a primary graph or an extension
     graph" from the `A@B.symbols.json` convention, before it reads the JSON.
     An extension graph's symbols are skipped unless extended types are
     enabled, so `TUIkit@TUIkitView.symbols.json` must not keep its `@`.

Symbol identity is the USR, which already encodes the defining module and
stays untouched, so relationships and cross-references still resolve.

Usage: unify_symbol_graphs.py <symbol-graph-dir> <output-dir>
"""

import json
import pathlib
import shutil
import sys

# The library modules that make up the public API surface. Test targets, the
# example apps, and the C image-decoder target are deliberately excluded.
MODULES = {"TUIkit", "TUIkitCore", "TUIkitStyling", "TUIkitView", "TUIkitImage"}
UMBRELLA = "TUIkit"


def main(source: pathlib.Path, destination: pathlib.Path) -> int:
    if not source.is_dir():
        print(f"error: no symbol-graph directory at {source}", file=sys.stderr)
        return 1

    shutil.rmtree(destination, ignore_errors=True)
    destination.mkdir(parents=True)

    seen: set[str] = set()
    staged = 0
    for path in sorted(source.glob("*.symbols.json")):
        stem = path.name.removesuffix(".symbols.json")
        owner = stem.split("@")[0]
        if owner not in MODULES:
            continue
        seen.add(owner)

        graph = json.loads(path.read_text())
        graph["module"]["name"] = UMBRELLA
        for symbol in graph.get("symbols", []):
            extension = symbol.get("swiftExtension")
            if extension and extension.get("extendedModule") in MODULES:
                extension["extendedModule"] = UMBRELLA

        # `A@B` marks an extension graph; rename so DocC reads it as primary.
        name = path.name.replace("@", "-ext-")
        (destination / name).write_text(json.dumps(graph))
        staged += 1

    missing = MODULES - seen
    if missing:
        print(
            "error: no symbol graph for " + ", ".join(sorted(missing))
            + " — did the build succeed?",
            file=sys.stderr,
        )
        return 1

    print(f"staged {staged} symbol graphs from {len(seen)} modules as '{UMBRELLA}'")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])))
