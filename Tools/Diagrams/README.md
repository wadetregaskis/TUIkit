# Diagram generation

The architecture / lifecycle / render diagrams in the DocC catalog
(`Sources/TUIkit/TUIkit.docc/Resources/`) are generated **from source** by a
zero-dependency Python script, so they stay in step with the code and can be
regenerated autonomously — no Graphviz, Mermaid, Node, headless browser, or
network required, just `python3`.

(The diagrams used to be hand-drawn PNGs with no committed source. When the
architecture changed — e.g. the run loop went demand-driven — they silently went
stale and there was no way to redraw them. This is the missing source.)

## Regenerate

```bash
python3 Tools/Diagrams/build.py
```

This (re)writes `<name>.svg` and `<name>~dark.svg` into the DocC Resources
directory for every diagram defined in `build.py`. DocC automatically uses the
`~dark` variant in dark mode. Commit the regenerated SVGs.

```bash
python3 Tools/Diagrams/build.py --list          # list diagram names
python3 Tools/Diagrams/build.py --stdout NAME    # print one diagram's SVG to stdout
```

## Edit or add a diagram

Each diagram is a small builder in `build.py` that returns a `Flow`:

```python
def lifecycle_main_loop() -> Flow:
    f = Flow(title="…")                 # title becomes the SVG accessibility label
    f.step("setup", "Terminal setup", ["install signals · alt screen"])
    f.step("shutdown", "shouldShutdown?", kind="decision")
    f.branch("cleanup", "shutdown", "Cleanup", kind="terminal")   # box to the right
    f.edge("setup", "shutdown")                                   # straight down the column
    f.edge("shutdown", "cleanup", label="yes", route="right")     # into the side branch
    f.edge("block", "shutdown", route="loopback")                 # arrow back up the gutter
    return f
```

Register it in the `DIAGRAMS` dict, re-run `build.py`, then point an article at
it: `@Image(source: "your-name.svg", alt: "…")`. Always write an `alt:` that
describes the flow — DocC has no other text for screen readers.

## How it works

`tuidiagram.py` lays a diagram out **automatically**. You describe a
top-to-bottom *flow* of nodes (plus optional right-hand `branch`es and a
`loopback` edge); the engine computes every coordinate from each node's measured
size. Boxes are sized to their widest line and stacked with fixed gaps, and the
loop-back is routed up a reserved left gutter — so text can't overflow and arrows
can't cross boxes. A diagram is correct by construction, without anyone eyeballing
pixels (which matters because the generator runs headless). Output is
self-contained, themed SVG — one render per light/dark theme.

- Node `kind`s: `normal` (teal), `accent` (darker teal), `decision` (diamond),
  `terminal` (red — entry/exit).
- Edge `route`s: `down` (default, straight down the centre column), `right` (to a
  side branch), `loopback` (out and up the left gutter, back to an earlier node).

## Keeping diagrams honest

A diagram's **content is documentation**: keep it in step with the prose of the
matching DocC article and with the code it describes. When the architecture
changes, edit the builder and re-run — that's the whole point of having source.

## Not yet migrated

The other `Resources/*.png` diagrams (dependency graphs, input/render dispatch,
the render pipeline) still describe accurate, stable architecture and have not
been ported to this system. To migrate one, add a builder to `build.py` and
switch its article's `@Image` to the generated `.svg`. (The current `Flow` model
covers vertical flowcharts with branches and a loop-back; a DAG-style layout for
the dependency graphs would be a small extension.)
