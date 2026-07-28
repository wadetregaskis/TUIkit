# Documentation build

Builds the DocC reference as **one archive covering the whole package**, with
every public symbol under `/documentation/tuikit/`.

```bash
Tools/BuildDocs/build-docs.sh                      # → .build/docs/TUIkit.doccarchive
Tools/BuildDocs/build-docs.sh --analyze            # every diagnostic, for a docs audit
Tools/BuildDocs/build-docs.sh --static-hosting \
    --output docc-output                           # servable from a plain web server
```

## Why this exists (don't replace it with `generate-documentation`)

The obvious command —

```bash
swift package generate-documentation --target TUIkit     # ← produces a BROKEN site
```

— builds an archive with **no page for `View`, `Color`, `Binding`, `State`,
`EnvironmentValues`, `FrameBuffer` or `Palette`**, and every catalog link to
them dangling.

TUIkit is five library modules — `TUIkitCore`, `TUIkitStyling`, `TUIkitView`,
`TUIkitImage`, and the `TUIkit` umbrella that `@_exported import`s the rest.
That split buys layering and per-module test isolation, and it is *ours*: a
reader writing `import TUIkit` sees one API and should never have to learn
which module happens to declare `Color`.

DocC, though, builds from symbol graphs one module at a time, and an
`@_exported` re-export does **not** copy the re-exported symbols into the
importing module's graph. Point it at `TUIkit` and you document only what
`TUIkit` itself declares. Point it at all five and you get five separate
module trees — which leaks exactly the structure we want hidden.

So this script emits the symbol graphs, rewrites their module identity to
`TUIkit`, and hands the result to `docc convert` as one module. The three
things that must be rewritten, and what each one costs if you skip it, are
documented at the top of `unify_symbol_graphs.py` — the third (the `A@B`
filename convention) is the non-obvious one, and skipping it silently drops
every `View` modifier from the docs.

Symbol identity is the USR, which already encodes the defining module and is
left untouched, so relationships and cross-references still resolve. Nothing
about the built product changes; this is purely how the docs are assembled.

## The regression guard

After converting, the script asserts that pages exist for a handful of types
declared in the sibling modules. That is precisely the failure mode this tool
exists to prevent, it costs nothing to check, and it fails loudly the day
someone "simplifies" the build back to a single target.

## Diagnostics

`--analyze` turns on DocC's full diagnostic set. The current residue is
per-symbol doc-comment hygiene — undocumented parameters, links to internal
types that have no page — not structural. Fix them at the source comment; a
link to something internal should be single-backtick code, not a
``doc-link``.
