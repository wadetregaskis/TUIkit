# GenerateImageGlyphs

Font-rasterisation calibration for the `Image` glyph renderers.

The luminance ramps and the shape-aware matcher both need to know **how much
ink each candidate glyph actually puts on screen, and where** — so a density
level can pick the glyph that carries the right tone, and a cell's sampled
darkness can be matched to the glyph that looks most like it. Those numbers
depend on the font the terminal renders with. This tool measures them from
the real font instead of guessing.

It rasterises each candidate glyph in a reference monospace font
(**SF Mono Regular 11** by default — the font macOS Terminal.app ships with) via
CoreText, measures ink coverage, and regenerates
[`Sources/TUIkitImage/ImageGlyphCalibration.generated.swift`](../../Sources/TUIkitImage/ImageGlyphCalibration.generated.swift).

## Output

One table, **`generatedGlyphCalibration`** — for every candidate glyph:

- its **total ink coverage** over the whole cell (0…1), which drives
  density-ramp selection (evenly-spaced tonal levels; near-duplicate
  coverages add banding, not levels, so the runtime dedupes them, preferring
  the flattest glyph per level);
- its raw **6-component coverage vector**, sampled at the *same* six
  staggered circles (`ShapeRegion.centres`, `radius`, 16-sample sunflower
  spiral) the runtime uses to sample the source image. It reads fractional
  grey ink, not a binary bitmap. The runtime normalises these at load, and
  derives per-glyph *flatness* (region-ink variance) from them.

The runtime (`GlyphRepertoire` in `Sources/TUIkitImage`) partitions the table
into the fundamental charsets by Unicode range — printable ASCII; non-block
Unicode (box drawing, geometric shapes); the Block Elements plus the corner
triangles `◢◣◤◥` for the shape-aware block repertoire — and selects the
ideal sized subsets (`glyphs:` counts) from them on demand.

Candidates the reference font lacks natively are skipped (CoreText silently
falls back to other fonts, which would calibrate glyphs most terminal fonts
show as tofu) — except an explicit `fallbackAllowedGlyphs` allowlist (the
corner triangles), measured through the fallback deliberately because they
ship in the common terminal fallback fonts and are essential to the block
repertoire's diagonals.

## Usage

```sh
Tools/GenerateImageGlyphs/generate.sh
```

Run from the repository root. macOS only (CoreText/CoreGraphics/AppKit); the
generated file is committed and consumed by every platform, so Linux never runs
this. It prints the resolved font, the cell pixel size, the glyph count, any
skipped candidates, and a few orientation sanity checks (`T` should be
upper-heavy, `_` lower-only, `▘`/`▗`/`◢` corner-heavy in their own corners).

## Why one profile is enough

Only *relative* coverage matters — the vectors are normalised at load and the
ramps are ordered, both of which are robust to font face and point size (a
denser font shifts every glyph together). So a single canonical profile from
the assumed-default font calibrates the renderers well across terminals; there
is no need for a per-emulator / per-font / per-size matrix. Change `pointSize`
or the `NSFont` lookup at the top of `main.swift` to retarget.

## Shared geometry (no drift)

The sampling geometry — the circle centres, radius, sample count, and the
golden-angle spiral that places the samples — is **not** copied into this tool.
`generate.sh` compiles the framework's own
[`Sources/TUIkitImage/ShapeSampling.swift`](../../Sources/TUIkitImage/ShapeSampling.swift)
alongside `main.swift`, and both the runtime and this tool call
`ShapeRegion.normalizedSamplePoints()`. So there is one definition of *where* a
cell is sampled; changing it in `ShapeSampling.swift` changes both at once, and
re-running the tool re-measures against the new geometry. The glyph pool is
authored here (it becomes the keys of `generatedGlyphCalibration`, which the
runtime reads back), so it too has no second copy to sync.

## Regenerating

The output is deterministic. Re-run `generate.sh` after changing the reference
font, the candidate glyph pools (`shapeGlyphs` / `unicodeExtraGlyphs` in
`main.swift`), or the shared sampling geometry (`ShapeRegion` in
`ShapeSampling.swift`). Then run `swift test` and SwiftLint — the width and
taxonomy pins in `GlyphRepertoireTests` gate the new table.
