# GenerateImageGlyphs

Font-rasterisation calibration for the `Image` ASCII/shape renderers.

The shape renderer (`.shapeBased` / `.shapeUnicode`) and the detailed ASCII
renderer (`.asciiDetailed`) both need to know **how much ink each candidate
glyph actually puts on screen, and where** — so a cell's sampled darkness can be
matched to the glyph that looks most like it. Those numbers depend on the font
the terminal renders with. This tool measures them from the real font instead of
guessing.

It rasterises each candidate glyph in a reference monospace font
(**SF Mono Regular 11** by default — the font macOS Terminal.app ships with) via
CoreText, measures ink coverage, and regenerates
[`Sources/TUIkitImage/ImageGlyphCalibration.generated.swift`](../../Sources/TUIkitImage/ImageGlyphCalibration.generated.swift).

## Output

Two tables:

- **`generatedShapeCoverage`** — for each of the shape renderer's 29 glyphs, a
  raw 6-component coverage vector, sampled at the *same* six staggered circles
  (`ShapeRegion.centres`, `radius`, 16-sample sunflower spiral) the runtime uses
  to sample the source image. It reads fractional grey ink, not a binary
  bitmap. `computeShapeTable()` normalises these at load, exactly as before —
  the only change is that the raw numbers now come from the font rather than
  hand-drawn 5×10 bitmaps.
- **`generatedAsciiDetailedRamp`** — a coverage-ordered, gap-free pure-ASCII
  ramp (light → dense) for `.asciiDetailed`, built by measuring every printable
  ASCII glyph's total ink and dropping near-duplicate coverages. Fewer but
  correctly-ordered levels beat a longer hand-picked ramp whose ordering
  doesn't match this font's real tones.

## Usage

```sh
Tools/GenerateImageGlyphs/generate.sh
```

Run from the repository root. macOS only (CoreText/CoreGraphics/AppKit); the
generated file is committed and consumed by every platform, so Linux never runs
this. It prints the resolved font, the cell pixel size, the ramp, and a couple
of orientation sanity checks (`T` should be upper-heavy, `_` lower-only).

## Why one profile is enough

Only *relative* coverage matters — the vectors are normalised at load and the
ramp is ordered, both of which are robust to font face and point size (a denser
font shifts every glyph together). So a single canonical profile from the
assumed-default font calibrates the renderers well across terminals; there is no
need for a per-emulator / per-font / per-size matrix. Change `pointSize` or the
`NSFont` lookup at the top of `main.swift` to retarget.

## Shared geometry (no drift)

The sampling geometry — the circle centres, radius, sample count, and the
golden-angle spiral that places the samples — is **not** copied into this tool.
`generate.sh` compiles the framework's own
[`Sources/TUIkitImage/ShapeSampling.swift`](../../Sources/TUIkitImage/ShapeSampling.swift)
alongside `main.swift`, and both the runtime and this tool call
`ShapeRegion.normalizedSamplePoints()`. So there is one definition of *where* a
cell is sampled; changing it in `ShapeSampling.swift` changes both at once, and
re-running the tool re-measures against the new geometry. The glyph set is
authored here (it becomes the keys of `generatedShapeCoverage`, which the
runtime reads back), so it too has no second copy to sync.

## Regenerating

The output is deterministic. Re-run `generate.sh` after changing the reference
font, the shape glyph set (`shapeGlyphs` in `main.swift`), or the shared
sampling geometry (`ShapeRegion` in `ShapeSampling.swift`). Then run
`swift test` and SwiftLint.
