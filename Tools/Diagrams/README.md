# Diagram generation

The architecture / lifecycle diagrams in the DocC catalog
(`Sources/TUIkit/TUIkit.docc/Resources/`) are generated **from source** by a
small Swift tool that describes each diagram, emits [Graphviz](https://graphviz.org)
DOT, and renders it with `dot`. Graphviz does the layout — no hand-placed
coordinates — so the diagrams stay clean and can be regenerated whenever the
architecture changes.

(They used to be hand-drawn PNGs with no committed source; when the run loop went
demand-driven they silently went stale with no way to redraw them. This is the
missing source.)

## Requirements

Graphviz `dot` on `PATH`:

```bash
brew install graphviz        # macOS
apt-get install graphviz     # Debian / Ubuntu
```

…or set the `DOT` environment variable to the path of `dot`. Graphviz is only
needed to **regenerate** diagrams — viewing the committed SVGs needs nothing.

## Regenerate

```bash
swift run --package-path Tools/Diagrams diagrams
```

This rewrites `<name>.svg` for every diagram into the DocC Resources directory.
Each SVG is **self-theming**: a `prefers-color-scheme` block recolours the
connectors and edge labels for dark mode, and node text is white on a coloured
fill, so one file serves both light and dark — no `~dark` companion. Commit the
regenerated SVGs.

```bash
swift run --package-path Tools/Diagrams diagrams --list           # list names
swift run --package-path Tools/Diagrams diagrams --dot <name>      # print the DOT
swift run --package-path Tools/Diagrams diagrams --output <dir>    # write elsewhere
```

## Edit or add a diagram

Diagrams are described in Swift in `Sources/diagrams/Diagrams.swift`:

```swift
let lifecycleMainLoop = Diagram(
    name: "lifecycle-main-loop",
    title: "…",                                  // SVG accessibility label
    nodes: [
        Node(id: "setup", title: "Terminal setup",
             detail: ["install signals · alt screen"], kind: .terminal),
        Node(id: "shutdown", title: "shouldShutdown?", kind: .decision),
        // …
    ],
    edges: [
        Edge("setup", "shutdown"),
        Edge("shutdown", "cleanup", label: "yes"),
        Edge("block", "shutdown", label: "loop", loop: true),   // back-edge
    ]
)
```

Add it to `allDiagrams`, re-run, then point an article at it with
`@Image(source: "your-name.svg", alt: "…")` — always write a descriptive `alt:`,
since DocC has no other text for screen readers.

Node `kind`s: `.normal` (teal), `.accent` (darker teal), `.decision` (diamond),
`.terminal` (red — entry/exit). An `Edge(…, loop: true)` is drawn with
`constraint=false`, so a loop-back doesn't distort the rank layout.

## How it works

`Diagram.dot()` emits Graphviz DOT → `runDot` shells out to `dot -Tsvg` →
`postProcess` strips the XML prolog and injects the dark-mode `<style>`. The
`dot` hierarchical engine computes all geometry, so boxes are auto-sized to their
text and edges are routed without overlaps.

## Not yet migrated

The other `Resources/*.png` diagrams (dependency graphs, input/render dispatch,
the render pipeline) describe accurate, stable architecture and haven't been
ported. To migrate one, add a `Diagram` to `Diagrams.swift` and switch its
article's `@Image` to the generated `.svg`. (Graphviz lays out DAGs natively, so
the dependency graphs are a good fit.)
