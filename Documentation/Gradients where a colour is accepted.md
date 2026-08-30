# Gradients where a colour is accepted

**Status: proposal. No code.** Written in answer to "if you apply a gradient as
the colour of a `Text`, it would automatically apply the gradient across the
contents of that `Text` — what about things which don't have the inherent
ability to display a gradient, and what does it mean for the gradient vs colour
picker dialogs?"

## What exists today

A colour is ``Color``. A gradient is a bare `[Color]` — stops at even intervals
— and it is accepted in exactly four places, all of them things that draw a
*strip*:

| site | spelling |
|---|---|
| `TrackConfiguration` | `fillGradient: [Color]?`, `emptyGradient: [Color]?` |
| `TrackStyle` | `.gradient([Color])`, `.shadeRamp(gradient:)` |
| `IndeterminateStyle` | `.gradient(colors: [Color]? = nil)` |
| `SegmentColoring` | `.gradient` |

Nothing else takes one. `foregroundStyle(_ style: Color?)`, `background(_:)`,
`tint(_:)`, `listRowBackground(_:)` and every `Palette` slot take a single
colour.

Two pieces of the machinery a general answer needs already exist and are
already debugged:

- `Color.quantisedRamp(stops:count:depth:)` — a gradient's per-cell colours
  quantised **as a sequence**, with the monotonicity repair. Per-cell
  quantisation is not a substitute: it is what produced the out-of-place
  colours that repair exists to remove, and the underlying metric must not be
  retuned (three attempts, three reverts — it is load-bearing for palette
  derivation).
- `Color.interpolate(stops:phase:)` — the colour at one point of a ramp.

## The type

**Recommendation: a concrete `Gradient`, and no `ShapeStyle`.**

SwiftUI's answer is a protocol: `foregroundStyle(_ style: some ShapeStyle)`,
with `Color`, `Gradient`, `LinearGradient`, `Material` and the hierarchical
styles conforming. Adopting the protocol would make every one of those spell
correctly and do nothing, which is precisely the failure mode this project
rejects: **anything unhonourable must not compile**. A protocol whose useful
conformances are three out of a dozen is a promise the terminal cannot keep.

The *value* type, though, should match SwiftUI exactly, because that costs
nothing and buys the spelling:

```swift
Gradient(colors: [.red, .orange, .yellow])          // even spacing
Gradient(stops: [.init(color: .red, location: 0),
                 .init(color: .yellow, location: 0.8)])
```

Positioned stops are a real gain, not just parity: today's `[Color]` cannot
express "mostly red, then a fast run to yellow at the end", which is the shape
most hand-made ramps actually want. The tone-curve work already introduced
positioned stops for the same reason (``ASCIIToneCurve/Stop/position``).

Overload the modifiers that can honour it, one by one, rather than generalising
them all through a protocol:

```swift
func foregroundStyle(_ gradient: Gradient) -> some View
func background(_ gradient: Gradient) -> some View
func tint(_ gradient: Gradient) -> some View
```

`TrackConfiguration.fillGradient`, `TrackStyle.gradient` and
`IndeterminateStyle.gradient` change from `[Color]` to `Gradient`. No shims:
pre-1.0, delete the old spelling.

## The hard part: what is the gradient's extent?

A colour needs no domain. A gradient needs to know over what extent `t` runs
from 0 to 1, and SwiftUI answers that with the bounds of the shape being
filled. TUIkit has no fill pass: the environment carries a colour and each leaf
uses it whole.

Three candidate domains:

1. **The leaf's own cells.** `VStack { Text("a"); Text("bbbbbb") }` under one
   `.foregroundStyle(gradient)` gives two ramps of different lengths, both
   running the full sweep. Trivial to build and visibly wrong.
2. **The modified subtree's rendered rectangle.** What SwiftUI means, and what
   anyone applying a gradient to a stack expects.
3. **The screen.** Well-defined and useless.

(2) is the answer, and the shape of its implementation is already in the
codebase under another name.

### It is the opacity design

``FrameBuffer`` carries `opacityRegions`: a rectangle plus an alpha, stamped by
the modifier, shifted through layout exactly as `hitTestRegions` and
`animatedCells` are, and **resolved late** — at the root, where what is behind
the region is finally known. `Documentation/Opacity as composition.md` §6b is
the argument for resolving there and not at the modifier.

A gradient is the same shape with an easier late step: no blending, just a
rewrite of the foreground (or background) SGR of the covered cells. So:

- `.foregroundStyle(gradient)` stamps a `GradientRegion` naming its rectangle,
  the stops, and the axis.
- The region is shifted through layout with the rest of the buffer's metadata.
- At the root, each covered cell's `t` comes from its position **within the
  region**, and the ramp is `Color.quantisedRamp` over the region's extent, so
  the repair applies once to the whole sweep rather than per cell.

Stamping rather than baking also keeps the render memo intact: the subtree
renders exactly as it would have, and only the final buffer is rewritten —
which is what lets a gradient sit over a `List` without disabling its row
memoization.

### The one thing the opacity design does not have to solve

A fade applies to every cell it covers. A **foreground** gradient must not: a
nested `.foregroundStyle(.red)` beats the cascade, and a rectangle over the
buffer cannot tell a cell that took the cascade from one that stated its own
colour.

So the leaf has to opt in, and the buffer has to carry the fact. A leaf that
reads the cascade and finds a gradient draws its glyphs **with no foreground**
and stamps a `GradientSpan` over its own cells. Spans ride layout like every
other piece of buffer metadata. At the root, the region supplies the ramp and
the extent, the spans say which cells asked for it, and the join is exact.

That is the whole design: **the region says what and how far; the span says
who.**

## Things that cannot display a gradient

This splits into three cases, and only one of them is really "cannot".

**A view that is one cell.** A `Toggle`'s indicator, a bullet, a scrollbar
thumb. One cell has one colour, but it also has a *position*, so the answer is
defined: sample the ramp there. Under a gradient applied to a whole form, the
toggles down the column each take their own colour and the column reads as one
sweep — which is the good outcome, and it needs no special case.

**A colour that is derived from rather than painted.** This is the real case,
and it is everywhere in the chrome: `ensuringRenderedContrast(atLeast:against:)`,
the button styles' face/border/label derivations, `ScrollbarColors`' separation
and groove rules, the pulse ramps. Each of these needs *one* colour to do
arithmetic with.

The rule to write down:

> **A gradient is accepted where a colour is PAINTED, never where a colour is
> DERIVED FROM.**

`Palette` therefore stays colour-only. A theme's `accent` is read by a dozen
derivations; a gradient there would have to collapse at each of them, twelve
times, differently.

Where a painted site nevertheless has to collapse — `tint(_:)` on a control
whose tint becomes four derived colours — the gradient supplies a
representative, and the API says so rather than refusing:

- `Gradient.representative` — the colour at `t = 0.5`. For identity, keying and
  derivation. Stable, and already implemented as `Color.interpolate`.
- `Gradient.leastContrasting(against:)` — the stop furthest from readable. What
  a contrast floor must be applied to, because flooring the midpoint leaves the
  ends below the floor.

**A site that genuinely refuses.** None found. Every painted surface in the
framework is at least one cell.

## Contrast

A gradient foreground over a themed background can dip under the floor
mid-ramp, and there are two ways to handle it that are not the same:

- Floor **each cell** after sampling. Correct per cell, and it can bend the ramp
  where it was smooth — which is exactly the banding the monotonicity repair
  exists to prevent.
- Floor **the stops**, then build the ramp, then quantise. The ramp keeps its
  shape, the repair still means something, and the floor holds everywhere
  because interpolation between two floored colours over one background cannot
  dip below both.

**Recommend flooring the stops.** It composes with the existing quantiser
instead of fighting it.

## The dialogs

They are already halfway combined: `GradientEditorPanel` embeds
`_ColorPickerBody` — the same preview-plus-tabs body `ColorPickerPanel` wraps —
to edit the selected stop, rather than nesting a second dialog.

**Recommendation: not one dialog, but one dialog with two floors.**

- `ColorPickerPanel(selection: Binding<Color>)` — unchanged, and deliberately
  offers no gradient affordance. Its callers include the theme editor's palette
  slots, which by the rule above cannot store one. Offering a tab that produces
  a value the caller cannot keep is worse than not offering it.
- `GradientEditorPanel(gradient: Binding<Gradient>)` — becomes the union
  surface by **relaxing its floor to one stop**. A one-stop gradient is a solid
  colour; today the panel forbids it ("Remove" disables at two) because a
  `[Color]` of one has no meaning to `TrackRenderer`. With a `Gradient` type
  that renders one stop as a flat fill, the restriction goes away and the panel
  can carry a plain **Solid / Gradient** switch that is nothing more than a
  shortcut for collapsing to, or expanding from, one stop.

So: the *binding type* is the discriminator, and the type system does the
work — a caller that can only take a colour cannot be handed a gradient, and it
does not compile rather than failing at runtime. Which is the same rule the
`ShapeStyle` decision above rests on.

## What falls out for free

`OpacityRegion` carries an optional `cycle`, and that is what lets a repeating
fade replay from pre-rendered phases instead of re-rendering. A `GradientRegion`
with a phase is the same trick, and it makes a **moving** gradient — a sweep
across arbitrary content — cost one render plus N re-colourings, replayed by
``AnimatedCellRun``. That is how `IndeterminateStyle.gradient` already animates;
generalising the region generalises the sweep.

Not a requirement. Worth building the region with the phase slot present.

## Cost

The late resolution is a per-cell SGR rewrite over the region, the same family
of work as `resolvingOpacity` — measured at 12–18 ms in a debug build for a
full-screen dim of a 120×40 terminal, and a gradient over a label is two orders
of magnitude smaller than that. The case to watch is `.foregroundStyle(gradient)`
applied to a whole page, which is a full-screen rewrite every render. Since the
region is stamped rather than baked, the memo survives and it is only the final
buffer that pays.

## Order of work, if this is taken

1. `Gradient` (+ `Gradient.Stop`), `representative`, `leastContrasting(against:)`.
   Convert the four existing sites off `[Color]`. No behaviour change.
2. `GradientRegion` + `GradientSpan` on `FrameBuffer`, shifted through layout,
   resolved at the root beside `resolvingOpacity`.
3. `foregroundStyle(_:)` and `background(_:)` overloads; `Text` opts in.
4. `tint(_:)`, with `representative` documented at each derivation.
5. The panel's one-stop floor and its Solid / Gradient switch.

Steps 1 and 2 are independently useful and independently testable; step 3 is
where it becomes visible.
