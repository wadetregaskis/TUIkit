# Gradients where a colour is accepted

**Status: proposal, revision 3. No code.**

Revision 1 asserted a resolution model from recollection; it was wrong.
Revision 2 measured that, and then made its own central decision — not to adopt
`ShapeStyle` — from recollection, which was also wrong. Revision 3 is what
survived three adversarial reviews (mechanism, parity, performance), with every
claim below either measured or cited to a line of code. §10 records what the
reviews overturned, because the pattern in it is worth keeping.

---

## 1. What SwiftUI actually does

Measured with `ImageRenderer` at scale 1, pixels read back; probes under
`scratchpad/gradprobe*`. Block glyphs, so every pixel of a text's box is ink.

### `foregroundStyle(gradient)` resolves per LEAF, over the leaf's LAYOUT BLOCK

```
A  vertical gradient applied to the STACK        B  the same applied to EACH Text
   block 0  top #E05B66  bottom #5E7DDF             block 0  top #E05B66  bottom #5E7DDF
   block 1  top #E25A63  bottom #5E7BDD             block 1  top #E25A63  bottom #5E7BDD
```

Identical. Unequal widths say it again and unambiguously:

```
C  horizontal gradient applied to the STACK
   block 0   81px wide   left #E8555A   right #4E7DE7    ← full sweep in 81px
   block 1  321px wide   left #EA5257   right #4B7CE8    ← full sweep in 321px
```

The per-leaf claim survived every attempt to break it: it holds through an
interposed `.frame(width: 460)` (glyphs still sweep `#EA575B → #4F7FE9`),
through `.padding(80)` (identical), and at the seam of adjacent leaves (first
`Text` ends `#1A7BFB`, the next begins `#FB3F38` — a clean discontinuity). A
`Label` is **two** leaves, each running its own full ramp (icon
`#F44A48→#387CF4`, title `#FD3E36→#1C7BFC`); `Image(systemName:)` is its own
leaf; `Text + Text` concatenation is one.

**And the extent is the leaf's whole layout block, not its line.** A two-line
`Text("██\n████████")` under a horizontal gradient ends its short first line at
`#D56274` ≈ t 0.25 — exactly that line's fraction of the *block's* width, not
blue. This decides the tier-1 implementation (§7.2) and revision 2 had it open.

### Spanning is not expressible, and `.in(_:)` is not the exception

`ShapeStyle.in(_ rect: CGRect)` (interface 8711) exists precisely to override a
style's resolution extent, so it is the obvious counter-candidate to §4. It is
not one: **`.in(rect)` re-anchors at each leaf's own origin.** With
trailing-aligned unequal texts the short block reads `#FE3D33 → #D56174` — t 0…
0.25, red — not the blue its position in the container demands; and a vertical
gradient with `.in(whole-content-rect)` across three stacked rows renders all
three identically (`#E6575F`, `#E6575F`, `#E5575E`). It fixes the ramp's
**scale**, not its **origin**.

SwiftUI's only spanning idiom is `gradient.mask(content)`, which resolves over
the gradient view's frame (short block reaches only `#C86A84` where the long one
reaches `#747CD1`) and costs you either a duplicated copy of the content or its
interactivity — the masked view is what hit-tests, and it is the gradient.
(`.overlay(gradient.blendMode(.sourceAtop)).compositingGroup()` duplicates
nothing and keeps hit-testing, but TUIkit has no `blendMode`, so it is not an
option here either.)

### Stop semantics, which nothing documents

Measured, and all three must be pinned by test or TUIkit will diverge silently:

- **Unsorted stops render as if sorted.** `red@0.8, blue@0.2` renders blue→red.
- **Duplicate locations make a hard edge** — `#FF3B2F | #007BFE` at adjacent px.
- **Out-of-range locations are NOT clamped.** Stops at −0.5 and 1.5 show the
  0.25–0.75 window of the ramp (`#C96881 → #7F7AC8`).

### The rest

- A bare `Gradient` used as a style is a **vertical, top → bottom** linear
  gradient (`Rectangle().fill(Gradient(colors: [.red, .blue]))` → `TL #F64743`,
  `BL #327AF6`).
- `Color.gradient` is a subtle vertical ramp of that colour (`TL #FF6359 →
  BL #FF3930`), which in a terminal is exactly the treatment that makes a flat
  block read as a surface.
- Diagonals interpolate as expected (`TL #F64743, TR #A674A7, BL #A774A6,
  BR #317BF6`).
- **`.tint(gradient)` on real controls: no claim.** The probe rendered
  `#FFB108 / #FFC701 / #FFB706` — but so did `.tint(Color.red)`. Those
  AppKit-backed controls ignore `tint` under `ImageRenderer` entirely, so the
  experiment says nothing.

---

## 2. `ShapeStyle`: adopt it

**Revision 2 said don't, on the grounds that every requirement is underscored
SPI. That is false, and one `swiftc -typecheck` refutes it.**

The interface carries public default implementations for all three underscored
requirements (SwiftUICore interface 9452–9461):

```swift
extension ShapeStyle {
  nonisolated public static func _makeView<S>(…) -> _ViewOutputs where S : Shape
  public func _apply(to shape: inout _ShapeStyle_Shape)
  public static func _apply(to type: inout _ShapeStyle_ShapeType)
}
```

and the conformance point is public: `associatedtype Resolved : ShapeStyle =
Never` plus `func resolve(in: EnvironmentValues) -> Resolved` (macOS 14+). This
compiles clean:

```swift
struct MyStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.colorScheme == .dark ? Color.white : Color.black
    }
}
```

as do `.foregroundStyle(MyStyle())`, `Rectangle().fill(MyStyle())`,
`AnyShapeStyle(MyStyle())`, `.foregroundStyle(Gradient(colors:))`,
`.foregroundStyle(.linearGradient(…))`, `.foregroundStyle(.secondary)` and
`.foregroundStyle(.red, .blue)`.

Revision 2's justifying example was also backwards. `.foregroundStyle(.thickMaterial)`
would **not** compile-and-do-nothing under a TUIkit `ShapeStyle`: `.thickMaterial`
is a static member on `ShapeStyle where Self == Material`, and with no `Material`
type the member does not exist, so the source fails to compile — which is
exactly what the parity rules demand. **What compiles is decided by which types
and static members ship, not by whether the protocol exists.** And the `tint`
pair is not a protocol-free precedent: the generic overload *requires* the
protocol; the `@_disfavoredOverload Color?` twin exists so `.tint(nil)` can infer
a type. Every styling entry point in the SDK is `<S: ShapeStyle>`.

### The shape of it, and how it survives the memo

Adopt the **modern** surface only — `Resolved` / `resolve(in:)` — and leave the
underscored trio out entirely; nothing outside SwiftUI can call them.

```swift
public protocol ShapeStyle: Sendable, Equatable {
    associatedtype Resolved: ShapeStyle = Never
    func resolve(in environment: EnvironmentValues) -> Resolved
}
```

The performance review's hardest constraint lands here: an **existential** in the
environment turns memoization off for its whole subtree.
`RenderCache.noteAppliedEnvironment` tests `value is any Equatable`
([RenderCache.swift:599](Sources/TUIkitView/Rendering/RenderCache.swift:599));
`.incomparable` sets `hasUncomparableEnvironmentValue` and every store below is
refused ([Environment.swift:85](Sources/TUIkitView/Environment/Environment.swift:85)).

So: **generic API, concrete storage.** `foregroundStyle<S: ShapeStyle>(_ style: S)`
resolves `S` at the modifier — which is where SwiftUI resolves too, and what the
`Resolved` associated type is *for* — down to a concrete, `Equatable` `Paint`:

```swift
enum Paint: Equatable, Sendable { case color(Color), gradient(GradientPaint) }
```

One environment slot, one concrete type, cheap `==`. A third-party conformance
reaches a `Paint` through its own `resolve(in:)`, exactly as SwiftUI's does.

---

## 3. The type family

`UnitPoint` already exists in TUIkit with all ten SwiftUI constants
([UnitPoint.swift](Sources/TUIkit/Views/UnitPoint.swift)), so most of this is
source-**identical**.

| SwiftUI | TUIkit | note |
|---|---|---|
| `Gradient(colors:)` / `(stops:)`, `Gradient.Stop(color:location:)` | same | also `: ShapeStyle`, meaning a **vertical** linear gradient (§1) |
| `LinearGradient(gradient:startPoint:endPoint:)` and its `colors:` / `stops:` twins | same | ✓ identical |
| `EllipticalGradient(…startRadiusFraction:endRadiusFraction:)` | same | ✓ already unit-space — **shipped**, §12 |
| `AngularGradient(…startAngle:endAngle:)` / `(…angle:)` | same, `Angle` | ✓ — **shipped**, and the sweep's outside rule is not what anyone guesses: §12 |
| `RadialGradient(…startRadius:endRadius:)` | radii `Int` cells | deviation — see below — **shipped**, §12 |
| `AnyGradient`, `Color.gradient` | same | `AnyGradient` must be `Equatable` by value |
| `AnyShapeStyle(_:)` | same | required — it is *the* style-switching idiom |
| `HierarchicalShapeStyle` (`.secondary`…), `style.secondary` | same | maps to the palette's foreground tiers |
| `foregroundStyle(_:_:)` and `(_:_:_:)` | same | 2- and 3-arg forms |
| `backgroundStyle(_:)` | same | |
| every gradient type is also a `View` | same | `ZStack { LinearGradient(…) }` must work |
| `ShapeStyle.opacity(_:)`, `.in(_ rect:)` | same, `CellRect` | `.in(_:)` is the portable "fix the ramp's scale" |
| static members `.linearGradient(…)`, `.radialGradient(…)`, `.angularGradient(…)` | same | on `ShapeStyle where Self == …` |
| `Text.foregroundStyle<S>` returns **`Text`** | same | or `Text("a").foregroundStyle(g) + Text("b")` breaks |
| `Gradient.ColorSpace` (`.device` / `.perceptual`), `colorSpace(_:)` | **ship** | TUIkit already has an opinion — see §6 |
| `Color.mix(with:by:in:)` | **ship** | a two-stop `Gradient` evaluated at `by`; note its default space is `.perceptual` |
| `MeshGradient` | **decline, recorded** | "given a cell, what is t?" generalises to (u,v), so it is not impossible — it is simply not worth it at 80×24 |
| `Shader` | **decline, recorded** | genuinely impossible |

**`RadialGradient`'s radii.** Revision 2 claimed `Int` prevents a silent 10×
error. It does not: `startRadius: 5, endRadius: 200` — the overwhelmingly common
spelling — compiles unchanged under `Int` and silently means 200 *cells*. `Int`
only rejects the rare fractional literal. The honest argument for `Int` is
**consistency**: every other dimension in TUIkit is `Int` cells
([frame(width:height:)](Sources/TUIkit/Extensions/View+Layout.swift:232)), and a
`CGFloat` here would be the sole exception. That is a weaker argument than
revision 2 made, and it is the true one. Whichever is chosen, the spec hole must
be closed: **a radius is measured along the horizontal axis in cells, and the
vertical is derived through `imageCellAspect`** — otherwise a "circle" is an
ellipse and nothing says which.

---

## 4. The two extents

### Per-item is SwiftUI's, and is the default

> "every row's text is red on the left side and blue on the right side"

```swift
List(rows) { row in Text(row.title) }
    .foregroundStyle(LinearGradient(colors: [.red, .blue],
                                    startPoint: .leading, endPoint: .trailing))
```

Per-leaf resolution gives this directly. A leaf knows its own layout block, so
this needs **no buffer metadata, no region and no post-pass** — see §7.2.

### Across-a-set is ours

> "apply a gradient to a set of controls … in such a way that the gradient spans
> all of them"

Not expressible in SwiftUI (§1), so this is a TUI-specific addition, kept
**separate from** the SwiftUI spelling rather than changing its meaning:

```swift
List(rows) { row in Text(row.title) }
    .foregroundStyle(LinearGradient(colors: [.red, .blue],
                                    startPoint: .top, endPoint: .bottom))
    .gradientExtent(.subtree)          // TUI-specific; default is .leaf
```

### The mechanism: a propagated origin, not a post-pass

Revision 2 proposed painting the "holes" — cells that took the cascade and so
emitted no foreground SGR — in a walk over the assembled buffer. **That premise
is false and the walk is too expensive.**

*False:* no leaf emits ink with the foreground unset.
[Text.swift:717](Sources/TUIkit/Views/Text.swift:717) fills
`cascaded.foreground ?? environment.foregroundStyle ?? palette.foreground` and
`ANSIRenderer` emits codes whenever `foregroundColor != nil`. Counted across the
framework: **152 styled-emission sites in 41 files**, 31 of them reading
`palette.foreground` directly. And "bare" would not even mean what revision 2
needed: nothing supplies a default *foreground* anywhere — `RenderBackgroundCodes`
carries backgrounds only — so a bare cell renders in the terminal user's own
colour, and making bare mean `palette.foreground` needs a persistent-foreground
mechanism restating after every reset, i.e. *more* bytes per frame, not fewer.

*Too expensive:* measured in release at 120×40, a naive paint-the-holes walk
costs **~330 µs**, one `splicing` per line **~350 µs**, `ansiSGRStateAt` per line
**~326 µs** — against a whole `megalist` frame of **414 µs**. It roughly doubles
the frame, every frame, and loses to the manual N-modifier version (40 nodes ×
1.5–5 µs ≈ 60–200 µs) by 2–5×. That fails requirement (b) outright.

**The walk is avoidable.** [VStack.swift:265](Sources/TUIkit/Views/VStack.swift:265):

```
// === PASS 1: Measure every child's natural size ===
```

Every child is measured and its height distributed *before any child renders*.
So a container knows each child's offset in advance, and the origin can be
handed down instead of the colours being painted back on:

1. `.gradientExtent(.subtree)` measures its child once to learn the extent (the
   measure memo makes this near-free) and publishes `(origin: .zero, size:)`.
2. Containers that place children add each child's `(dx, dy)` to the origin as
   they render it — one environment write per child.
3. Leaves resolve exactly as in tier 1, against `(origin, extent)` instead of
   their own box.

One mechanism, two configurations; N dictionary writes instead of N line
rewrites. It also survives what a post-pass could not: opacity resolution
baking colours at intermediate composites, `OverlayLayer` content composited at
the root, and `AnimatedCellRun` frames spliced after the fact — none of which a
`lines`-only walk reaches (all three are the traps the backdrop work hit in
`dac23916`).

**Its own risk, stated:** container coverage. A container that does not propagate
gives its children a shared origin — a graceful degradation (the gradient
resolves as if that subtree were flat) rather than corruption, but a wrong-looking
one. The participating set is small — VStack, HStack, ZStack, List, Table, Grid,
ScrollView — and each is a few lines. **This is the gate for step 4** (§8), and it
must be measured against the manual alternative before it is built, not after.

And it answers §9's scroll question by construction rather than by taste:
whether `ScrollView` folds its scroll offset into the origin decides
content-pinned versus viewport-pinned. **Pin it to the viewport** — content-pinned
means every scroll step and every append in a log-tail recolours every visible
cell, forever.

> **Built content-pinned, not viewport-pinned — see §13.** The prediction above
> was overturned by the thing itself: `ScrollView` never folds an offset in
> because its content's coordinates ARE the content's, so the eager path came
> out content-pinned without anyone choosing it, and the recolouring cost the
> paragraph feared does not exist (a scroll moves every glyph on every row, so
> those cells repaint regardless of their colour).

---

## 5. Where a gradient cannot be painted

Revision 2 argued from `Resolved == Never` that "SwiftUI can flatten a colour
and cannot flatten a gradient". That is over-read: `Resolved == Never` means
*primitive — not decomposable through the public API*; SwiftUI flattens
internally via `_apply`. The claim is withdrawn. The TUIkit rule stands on its
own merits, which are sufficient:

> **A gradient is accepted where a colour is PAINTED. Where a colour is DERIVED
> FROM, it collapses to a stated representative — and the API says which one.**

TUIkit's chrome derives colours constantly —
`ensuringRenderedContrast(atLeast:against:)`, the button styles' face / border /
label chain, `ScrollbarColors`' separation and groove rules, the pulse ramps —
and each needs one colour to do arithmetic with. So:

- `Gradient.representative` — the colour at `t = 0.5`, for identity, cache keys
  and derivation.
- `Gradient.leastContrasting(against:)` — for contrast floors (§6).

`Palette` stays colour-only: its `accent` is read by a dozen derivations, and a
gradient there would collapse at each of them, differently.

**A one-cell view is not this case in principle but is in practice.** A `Toggle`'s
indicator has a position, so it *could* sample. But its colour is state-derived
(`palette.accent` when on, `foreground` when off, hovered variants —
[_ToggleCore.swift:144](Sources/TUIkit/Views/_ToggleCore.swift:144)), and a
derived colour must stay stated or the control loses its signalling. Under
`.subtree` such controls therefore keep their own colours and do **not**
participate. Revision 2 claimed the opposite; it was wrong, and the honest rule
is that `.subtree` tints what the cascade would have coloured and nothing else.

---

## 6. Contrast

**Revision 2's guarantee was false.** It claimed "interpolation between two
floored colours over one background cannot fall below both". Computed:

```
background #808080
  white end       contrast 3.95:1
  black end       contrast 5.32:1
  sRGB midpoint   contrast 1.00:1      ← worst point on the ramp
```

Both ends clear the floor comfortably and the middle is invisible. Flooring the
stops does nothing here, because relative luminance interpolates monotonically
between the endpoints and therefore **crosses the background's whenever the
endpoints straddle it**.

The rule that actually works:

1. Floor the stops (still necessary, and it composes with the quantiser).
2. **Detect straddling per segment** — endpoint luminances on opposite sides of
   the background's — which is two comparisons per segment.
3. Where a segment straddles, either insert a compensating stop at the crossing
   or floor that segment against the background directly. Both bend the ramp;
   bending it where it would otherwise be unreadable is the point.

Everything painted still goes through
`Color.quantisedRamp(_:count:depth:)` rather than per-cell
`downsampledToPalette256()` — per-cell quantisation is what produced the
out-of-place colours the monotonicity repair was written for, and the underlying
metric must not be retuned (three attempts, three reverts).

**`against` what?** Under `.subtree` one ramp can cross the content background, a
selection fill and a card surface. The surface is not knowable at the leaf. Name
it: floor against the **modifier's own resolved surface**, documented as an
approximation, and accept that a gradient crossing a selection highlight is the
caller's problem — the alternative is flooring at composite time, which puts this
back into the post-pass the whole design exists to avoid.

---

## 7. Performance

Two requirements, both explicit: **nothing when unused**, and **no worse than by
hand** when used.

### 7.1 Nothing when unused

`EnvironmentValues` is `[ObjectIdentifier: Any]`
([EnvironmentKey.swift:46](Sources/TUIkitCore/Environment/EnvironmentKey.swift:46)),
not a struct of fields — so revision 2's "one more field, one optional read" was
wrong twice over. The framework already hoisted `renderCache` and `stateStorage`
out of that dictionary into `RenderContext` because those getters measured
**4.5% and 5.2% of CPU**
([RenderContext.swift:42](Sources/TUIkitView/Rendering/RenderContext.swift:42)),
and the `.foregroundStyle` doc explicitly refuses a per-`Text` store lookup on
exactly that ground.

**Which is why the `Paint` enum of §2 is not merely a memo fix but the
performance answer.** It goes in the *existing* `foregroundStyle` slot:

- **zero additional dictionary probes** — `Text` already reads that key on the
  no-explicit-colour path;
- **no precedence ambiguity** — a second key would let an outer gradient and an
  inner colour both be set with nothing to order them, and clearing the other
  key would cost the plain-colour path a second write plus a second
  `noteAppliedEnvironment` slot;
- **`.gradientExtent` is read only after a gradient is found**, so it is never an
  unconditional second probe.

`EnvironmentValues.foregroundStyle` changes from `Color?` to `Paint?`. Pre-1.0,
no shims. (Note that TUIkit's `foregroundStyle(_ style: Color?)` is already
off-parity — SwiftUI's takes no Optional; only `tint` does. The new generic
overload must be non-optional or `.foregroundStyle(nil)` becomes ambiguous.)

Gates, on named scenarios rather than in the abstract: `ab_bench.py` on
`megalist`, `table` and `dashboard` (where leaf cost lives), plus the golden
snapshots as a hard gate that a gradient-free page is byte-identical. And the
measure pass must skip gradient work entirely (`context.isMeasuring`) or
`fanout`'s ~4 measures per render each pay for it.

### 7.2 Tier 1, and against doing it by hand

A leaf resolves its own ramp. The one real subtlety is that
`TextRunAttribution` splits on **source-run membership walking `Character`s**
([Text+Concatenation.swift:133](Sources/TUIkit/Views/Text+Concatenation.swift:133)),
while a gradient needs **display-cell-indexed** bands — character index ≠ cell
index for CJK and emoji, and a band boundary must not split a two-cell glyph.
Plus §1's finding that the extent is the whole text block: `t` comes from the
absolute cell position within the block, so a vertical gradient splits across
*rows* and a multi-line horizontal one does not restart per line. That is new
logic on the hottest leaf, and it is where tier 1's benchmark bites.

Measured run counts from the real `quantisedRamp` at `.palette256` — the number
that decides the byte cost, and it is bounded by cube crossings, not by width:

| ramp | 20 cells | 40 | 80 | 120 |
|---|---|---|---|---|
| red→blue (2 stops) | 11 | 11 | 11 | 11 |
| track default (3) | 8 | 9 | 9 | 9 |
| rainbow (6) | 18 | 22 | 23 | 24 |
| `Color.gradient`-style | 2 | 2 | 2 | 2 |

Revision 2's "~10 runs, not 40" holds for two and three stops and is ~2× off for
six. Truecolor is one run per cell: **760–960 bytes for a 40-cell line against
50 plain.** Two corrections to how that lands:

- **Intra-line diffing is shipped**, not absent
  (`Documentation/Intra-line output diffing.md`, and `FrameDiffWriter`'s
  `CellCache`), so a changed line is *not* rewritten whole. The performance
  review's conclusion here was wrong; the byte measurement stands, its
  consequence does not.
- **At any depth but `.palette256`, `quantisedRamp` returns raw interpolated
  RGB** ([Color+Downsampling.swift:118](Sources/TUIkitStyling/Color/Color+Downsampling.swift:118)),
  so every cell is a distinct `Color`. Run-grouping must happen on the
  **depth-resolved** colour or a 16-colour terminal emits one SGR per cell to
  paint runs that render identically.

Against the manual alternative:

| | manual | proposed |
|---|---|---|
| horizontal, within a row | the app does grapheme-accurate cell splitting itself | one ramp lookup; the leaf splits runs it already splits — **strictly better** |
| vertical, across N rows | N environment writes (60–200 µs at 40 rows) | N environment writes + one extra memoised measure — **comparable**, and it works in a scrolling `List` where the manual version cannot |

### 7.3 Two fixes to `quantisedRamp` this needs anyway

Both visible at [Color+Downsampling.swift:110](Sources/TUIkitStyling/Color/Color+Downsampling.swift:110):

- **It samples before it consults its cache** (`sampled` is built at :111–117,
  the lookup is at :122–125), so a cache *hit* still pays the whole
  interpolation — measured 0.42 µs, of which ~0.34 µs is the wasted pre-lookup
  work. Looking up first makes a hit ~0.09 µs. At one gradient per row on a
  40-row list that is 17 µs/frame — ~4% of a `megalist` frame — paid for work
  the memo exists to elide.
- **Eviction is `removeAll()` above 512 entries** (:145) — a cliff, not an LRU.
  Bounded per app today; a resize sweep across many widths crosses it and
  re-pays every cold ramp at once. Cold cost is 21.7 µs (2 stops, 40 cells) to
  47.7 µs (6 stops, 120), so the cliff is real.

Both are independently worth fixing and belong in step 1.

---

## 8. Order of work, and the branch

On a branch, merged only if the whole thing lands.

1. **`Gradient`, `Gradient.Stop`, `LinearGradient`, `Paint`, `representative`,
   `leastContrasting(against:)`**, plus the two `quantisedRamp` fixes (§7.3) and
   the stop-semantics tests (§1). Convert the four existing `[Color]` sites off
   `[Color]` — `TrackConfiguration`, `TrackStyle` (including
   `shadeRamp(gradient:)`, whose label keeps saying `gradient` for a `[Color]`),
   `IndeterminateStyle`, `SegmentColoring`. No behaviour change; golden
   snapshots must not move.
2. **The `ShapeStyle` protocol**, `AnyShapeStyle`, the hierarchical styles, the
   static members, the 2- and 3-arg `foregroundStyle`, `backgroundStyle`,
   gradient-as-`View`. Storage stays the concrete `Paint`.
3. **Per-leaf `foregroundStyle` on `Text`** — the cell-indexed banding of §7.2,
   with `Text.foregroundStyle` returning `Text`. Bench gates of §7.1.
4. **`.gradientExtent(.subtree)`** via the propagated origin, and the container
   survey it rests on. **Gated on measuring against the manual N-modifier
   version**, per requirement (b). ✅ — see §11.
5. **`background(_:)`**, `.in(_:)`, then `RadialGradient` / `AngularGradient` /
   `EllipticalGradient`. ✅ — see §12, including `ShapeStyle.opacity(_:)`.
6. **The panel.** Not one dialog, but one dialog with two floors:
   `ColorPickerPanel` keeps no gradient affordance because its callers include
   palette slots that cannot store one; `GradientEditorPanel` becomes the union
   surface by relaxing its floor to a single stop, where a Solid / Gradient
   switch is just collapsing to or expanding from one stop. The binding type is
   the discriminator, so the wrong call does not compile. **This step carries a
   persistence migration** that nothing else does: `GradientEditorPanel(stops:)`
   is public API taking `Binding<[Color]>` with an even-spacing assumption, and
   its `@AppStorage` recents format (`;`-separated hex, see
   `Sources/Example/Components/GradientStopsCodec.swift`) cannot represent
   `Gradient.Stop.location`. ✅ — and the migration needed no migration code:
   a stop written without a position reads as evenly spaced, which is exactly
   what the old format meant, so stored values convert by being read.

Steps 1–3 are each independently useful and revertible. Step 4 is the one that
can fail, and it fails early: the container survey and the bench tell you before
any of it is written.

**What is deliberately not built**, decided while step 5 was: the 2- and
3-argument `foregroundStyle` (the extra styles paint a symbol's extra LAYERS,
and a glyph in a cell has one), `Text.foregroundStyle<S>` returning `Text` (a ramp on
one FRAGMENT would need a paint per run, where a run stores a style; a ramp on
the whole concatenation bands across the fragments and always did have to —
see §15), and `HierarchicalShapeStyle` (its
four names are palette roles here, two of them already spelled on `Color`
where SwiftUI spells them, so a second type would only make `.secondary`
ambiguous). Each is recorded in `SwiftUI-compatibility.md` §3.

**Both remaining items shipped too**, and neither was a gradient problem.
`backgroundStyle(_:)` now has the zero-argument `background()` to read it, with
`BackgroundStyle` (`.background`) as the style itself. And a style used where a
VIEW goes fills the space it is offered — `Color: View` and the four gradient
types, which wanted one piece of machinery between them: a blank rectangle plus
`.background(style)`, so that "a style as a view" is literally the same painting
path as "a style as a background" and the two cannot disagree. The rectangle is
flexible in both axes with a minimum of zero, which is `Spacer`'s contract: it
claims slack and never demands any.

---

## 9. Open questions

- ~~**Container coverage for `.subtree`** (§4). How many containers must
  propagate the origin before the feature reads as correct rather than as
  approximately correct? This is the step-4 gate.~~ Answered by building it out:
  see §13.
- **`TrackGradientScaling` vs `GradientExtent`.** `TrackGradientScaling`
  (`.track` / `.fill`) is already an extent knob for gradients in one corner of
  the framework. Two vocabularies for "what does the ramp span" is one too many;
  `.in(_:)` may unify them.
- **What a real AppKit control does with `.tint(gradient)`** (§1). Blocks
  nothing — the §5 rule stands on TUIkit's own needs — but it would be good to
  know.

---

## 10. What the reviews overturned

Kept because the pattern is the lesson, not the list.

| Revision 2 claimed | Actually |
|---|---|
| `ShapeStyle` is not conformable outside SwiftUI | It is, via public `resolve(in:)` with public defaults for the underscored trio. **One `swiftc -typecheck` refutes it.** |
| A cell that took the cascade emits no foreground | No leaf does. 152 emission sites; `Text` always states one |
| "Bare" means the page's colour | It means the *terminal user's* colour; nothing supplies a default foreground |
| The `.subtree` walk is cheap | ~330 µs at 120×40 release, against a 414 µs `megalist` frame — 2–5× the manual version |
| One more `EnvironmentValues` field is ~free | It is a dictionary; the framework already hoisted two services out of it at 4.5% and 5.2% of CPU |
| Flooring the stops keeps the whole ramp readable | White→black over `#808080`: ends 3.95:1 and 5.32:1, midpoint **1.00:1** |
| `Resolved == Never` proves SwiftUI cannot flatten a gradient | It proves the *public* API cannot; `_apply` does internally |
| `Int` radii prevent a silent 10× error | `startRadius: 5` compiles either way. The real argument is consistency |
| The extent is the leaf's bounds | The leaf's **layout-block** bounds — a two-line `Text` shares one ramp |

The common thread: **revision 2's banner was "measured, not recalled", and every
one of these is something it recalled.** Where it measured, it was right.


---

## 11. What step 4 measured

The survey first, because it changed the mechanism. A container knows a child's
offset **along its own axis** before it renders it — `VStack` distributes
heights in PASS 1, `HStack` widths — and its **cross-axis** offset only
afterwards, because alignment needs the rendered sizes
([VStack.swift:297](../Sources/TUIkit/Views/VStack.swift:297) renders every
child before PASS 3 computes `alignmentWidth`). So the cross-axis offset is
predicted from the child's MEASURED size, which is exact wherever measure and
render agree and shifts a colour rather than a cell when they do not.

The extent has the same problem one level up, and the same answer. Measuring
for it at the modifier cost **96 µs of a 336 µs frame** on a forty-row list —
most of the gap to the manual version — so the modifier publishes the space it
was given as a stand-in and the first placing container settles it from PASS 1,
for nothing.

Release, 40 rows × 120 cells, per render:

| | µs |
|---|---|
| plain, no gradient | 218 |
| **manual: one `.foregroundStyle(colour)` per row** | **215** |
| `.gradientExtent(.subtree)`, vertical ramp | **226** |
| per-leaf gradient | 223 |
| `.subtree`, ramp along the row, 256 colours | 1700 |
| `.subtree`, ramp along the row, truecolor | 2570 |

**The asked-for case — a ramp down a list — is indistinguishable from doing it
by hand**, and from not doing it at all. Requirement (b) met.

A ramp that varies **along a row** is not, and the reason is not fixable by
tuning: it is one SGR run per cell whose colour differs from its neighbour's,
which over a full-screen subtree is 4 800 of them. At 256 colours the run count
collapses to the cube crossings and it is ~7× a plain frame; at truecolor every
cell is its own run and it is ~12×. A single label painted that way is ~62 µs
and entirely normal; a whole page is not. **Documented, not hidden.**

Three optimisations were built and reverted for measuring nothing:
hoisting the affine arithmetic out of the cell loop (3214 → 3214 µs), an
ASCII byte walk to skip grapheme breaking (2566 → 2549, inside noise), and
reserving the output for the worst case (2571 → 2517). What *did* pay, in
order: appending in place instead of `a + b + c` (3214 → 2570), caching the
sampled ramp at every depth rather than only at `.palette256` (a truecolor
subtree had been re-interpolating its whole ramp once per leaf), and — the one
that closed the gap — **not allocating the run table for a ramp that does not
vary along a row** (336 → 226 µs), which had been one array per leaf to hold a
single entry.

---

## 12. What step 5 measured

The other three geometries, pinned the same way §1 was: `ImageRenderer` over a
`41 × 41` (and `81 × 41`) frame, read back cell by cell. Three of the five
answers are not the obvious ones, and every one of them is now a test in
[GradientGeometryTests.swift](../Tests/TUIkitTests/GradientGeometryTests.swift).

**A radius is absolute, so a circle stays a circle.** `RadialGradient(…,
startRadius: 5, endRadius: 15)` gave the same colour at `d = 10` horizontally,
vertically and diagonally, in a square frame and in one twice as wide. That is
what forces the deviation: TUIkit's "pixels" are cells about twice as tall as
they are wide, so honouring the radius equally in both axes would draw an
ellipse. The radius is horizontal cells and the vertical is derived through
`imageCellAspect` — the divergence keeps the *appearance* SwiftUI has, which is
the parity that matters.

**`t` clamps at both ends.** Inside the start radius every cell is the first
stop; past the end radius every cell is the last. The ramp never repeats.

**An elliptical gradient's fractions are of the width and of the height
separately** — `dx / w` and `dy / h`, so the default `0 … 0.5` reaches the last
stop at the middle of every edge whatever shape the box is. Confirmed at
`0.2 … 0.4` too: `dx/w = 0.3` was exactly the ramp's midpoint. No cell-aspect
correction here, and that is the whole difference from the radial case.

**Angles start at the trailing edge and increase clockwise** (`0°` right, `90°`
down), because y grows downward. Aspect-corrected as radial is: a `dx = 40,
dy = 20` corner read `t = 0.0738`, which is `atan2(20, 40)` in true geometry
rather than the grid's.

**Outside an angular sweep, a cell takes the NEARER end — it does not wrap.**
A `0°…180°` red→blue sweep is blue from 180° round to *270°* and abruptly red
from there back to 0°; the seam sits at the midpoint of the arc the sweep does
not cover. A `90°…270°` sweep confirmed it from the other side, and a
`45°…45°` one shows the degenerate form: two half-planes, no ramp at all.

**The default `AngularGradient` sweep is that degenerate one.** `startAngle`
and `endAngle` both default to `.zero`, so the split is what you get;
`AngularGradient(gradient:center:angle:)` is the full turn, and it means
`startAngle: angle, endAngle: angle + 360°` (measured: `angle: 90°` put `t = 0`
just clockwise of 90° and `t = 1` at 90°). The earlier reading that a zero span
means a full turn was an overload-resolution artefact — `AngularGradient(colors:
center:)` selects the `angle:` initialiser, not the `startAngle:endAngle:` one.

Two degenerate inputs that must not trap, since both are a number a caller can
type: equal radii (SwiftUI draws a hard edge — the last stop inside it, the
first outside) and a zero sweep. The edge is reproduced with a slope steep
enough to saturate one cell either side rather than an infinity, because an
infinity makes a cell exactly ON the edge a NaN and NaN is the one value the
`Int` entry clamp cannot survive.

### What it cost

Nothing on the paths that existed. All four geometries reduce to one affine map
from `(column, row)` to the geometry's own coordinates plus a `Mapping` to `t`,
so the linear case still folds entirely into the offsets and its per-cell work
is the add, multiply and round it already was. The new geometries add a square
root (radial, elliptical) or an `atan2` (angular), and only they pay it.

The one new cost on an old path is the per-cell `switch` on the mapping.
Measured directly, 4800 cells: **10.4 µs through the sampler against 4.2 µs for
the same arithmetic with nothing to dispatch on** — about 1.3 ns a cell, or
0.3% of what painting that subtree costs. A vertical ramp does not pay even
that, because it asks once per row rather than once per cell.

Release, 40 rows × 120 cells, truecolor, per render — the same shape as §11 on
a warmer machine, so read the column against its own `plain`:

| | µs |
|---|---|
| plain, no gradient | 263 |
| manual: one `.foregroundStyle(colour)` per row | 261 |
| `.subtree` vertical linear | 252 |
| `.subtree` **elliptical** | 850 |
| `.subtree` **radial** | 897 |
| `.subtree` **angular** | 1669 |
| `.subtree` linear along the row | 1778 |

**Cost tracks colour CHANGES along a row, not the geometry's arithmetic.** The
two that look most expensive to compute are the two cheapest to draw: a radial
ramp of 60 entries spread over 120 columns repeats itself, so a row is a few
dozen SGR runs rather than 120. The angular case is dear for the opposite
reason — its ramp is sampled at one entry per cell of the longest arc it can
draw, which is 450 of them, so nearly every cell is its own run. That is the
same ceiling §11 documented, reached by a different road, and the same answer
applies: a label or a panel painted this way is normal, a whole page is not.

---

## 13. Container coverage, measured

§4 named the participating set from memory and §9 left "how many containers is
enough?" open. Both are now answered by probing what the built thing actually
does, one container at a time, reading the first ink of each row of a
four-row red→blue ramp under `.gradientExtent(.subtree)`.

| Container | Before | Note |
|---|---|---|
| `VStack`, `HStack` | ✅ ramps | Shipped in step 4 |
| `ZStack` | ✅ ramps | Inherits: its children all sit at its own origin |
| `ScrollView` | ✅ ramps | Inherits: it wraps one child and moves nothing |
| `Form` | ✅ ramps | Inherits, being a stack underneath |
| `LazyVStack`, `LazyHStack` | ❌ every row the ramp's first colour | Fixed |
| `List`, `OutlineGroup` | ❌ every row the ramp's first colour | Fixed — see below |
| `Grid`, `LazyVGrid`, `LazyHGrid`, `AnyLayout` | ❌ every row the ramp's first colour | Fixed in one place: every `Layout` places its subviews through `_LayoutCore`, which knows the bounds and each entry's exact position |
| `Table` | ❌ no `foregroundStyle` at all | **Not fixed, and not the same problem** — see below |

So the answer to "how many containers?" is: every one that places children,
and there are seven places that do it. The two calls each one makes —
`RenderContext.gradientContentFrame(width:height:)` then
`placingGradientChild(_:x:y:)` — are the whole of the participation.

Two corrections to the record while measuring this:

- **`List` was reported as ignoring `.foregroundStyle` entirely.** It does not
  — a plain colour reaches its rows. The probe that said otherwise read the
  first ink of each *line*, which for a bordered list is the border glyph, not
  the row's text. `List`'s real gap was the same one the lazy stacks had.
  **`Table` is the one that ignores it**, and for a reason no gradient work
  touches: a `TableColumn`'s content is a `(Value) -> String`, not a view, so
  the table paints its own cells and never consults
  `environment.foregroundStyle`. Measured: `.foregroundStyle(.red)` on a
  `Table` leaves its rows at the palette's foreground. That is a separate gap
  — "a table's cells take the styling around them" — and wants answering at the
  colour level before anyone reaches for a ramp.
- **The ramp is content-pinned, not viewport-pinned** (§4 predicted the
  opposite). An eager `ScrollView { VStack { ForEach(0..<40) } }` in a ten-row
  viewport shows `255;0;0 … 196;0;58` — the first quarter of the ramp, so a row
  keeps its colour as it scrolls. Nobody chose this: a `ScrollView` publishes a
  window, not a coordinate shift, so the content's own coordinates are what the
  frame is offset by. The lazy paths were built to match, because eager and
  lazy disagreeing about a colour is worse than either answer.

### What a windowed stack has to do that an eager one does not

An eager `VStack` measures every child in PASS 1, so it knows its own extent
and every child's place in it before it renders anything. A lazy stack renders
*as it walks*, and has four paths that do it differently:

| Path | Row's y | Extent |
|---|---|---|
| Append-while-it-fits (no scroll window) | Running total | Measure walk stopped at the fold |
| Exact slot walk (`renderViewportWindow`) | `slot.y` — exact | `walkedTotal` — exact |
| Uniform seek | `ordinal × pitch` — arithmetic | `count × pitch` — arithmetic |
| Anchored outward fill | Estimated from the anchor | Estimated from the running pitch average |

Only the first needed anything new: a measure walk up front, **taken only when
a ramp is actually in force, and stopped at the same fold the render walk stops
at** — a lazy stack must not measure past the fold, and this does not. The
other three already knew both numbers for their own placement.

The anchored path's ramp is therefore an estimate, like everything else on it
(`sliceTotalIsEstimate` is already set there for the same reason), and
converges as the walk learns the real pitch.

### And what a `List` has to do that neither of them does

A `List` renders a row **on demand and only once** — the box is memoised, so
there is no second render to correct a colour with. The row's place in the ramp
has to be right the first time, and the ramp's extent has to be known before
the first row renders. Neither is available: the extent is the total height of
rows that have not been rendered.

Three answers were tried against each other:

| | Verdict |
|---|---|
| Place by **row ordinal**, extent = row count | Wrong for any row taller than a line: the row's own content offsets *within* it by lines, so a two-line row's second line reads the next row's colour and the ramp runs out halfway down |
| Render the window, learn the heights, **render again** placed | Exact, and doubles every visible row's render — with its focus registration and lifecycle — for a colour |
| **Measure row 0, seed a pitch, place by ordinal × pitch** | Exact wherever the rows are one height, which is a list's ordinary shape; an estimate otherwise, and the same estimate the anchored stack window already makes |

The third is what shipped, which is also what `renderUniformSeekWindow` does
one layer down for exactly the same reason. Measuring is side-effect-free and
the memo answers the render that follows for nothing, so the seed costs a
measure and no row renders twice.

The eager list spellings — `List { Text(…); Text(…) }`, and a list whose whole
content is one view — do not defer anything, so they skip the hypothesis
entirely: they measure every row and place each one exactly.

Section headers and footers are rendered by the time the list sees them and
take no part in the ramp. They are chrome, and they already draw in their own
dimmed styling.

---

## 14. A toolchain bug the feature stepped on

`ZStack { Color.red; Text("hi").frame(width: 4) }` **segfaults in a debug
build** — Swift 6.2.4, before any TUIkit code runs. Not a layout bug and not a
rendering bug: it dies instantiating the metadata for the `@ViewBuilder` pack,
so it never reaches `_ZStackCore` (an `fputs` at the top of `renderToBuffer`
never fires, and neither does the first statement of the test that builds it).

Narrowed by measurement:

| | |
|---|---|
| `ZStack { Color.red; Text("hi") }` | fine — the second element is not generic |
| `ZStack { Color.red; Text("hi").frame(…) }` | **crash** |
| `ZStack { LinearGradient(…); Text("hi").frame(…) }` | fine |
| `ZStack { AnyView(Color.red); Text("hi").frame(…) }` | fine |
| `Pair<Color, FlexibleFrameView<Text>>` (a plain generic struct) | fine |
| release build, any of the above | fine |

Two properties, both required:

1. **A parameter pack.** The same two views in an ordinary two-parameter
   generic struct instantiate happily; only `TupleView<each V: View>` dies.
2. **A conformance declared in a module that owns neither the type nor the
   protocol.** `Color` is `TUIkitStyling`'s, `View` is `TUIkitView`'s, and
   `Color: View` is written in `TUIkit` — the only such conformance in the
   framework. Reproduced from scratch on unrelated types (`BorderStyle: View`,
   `ContentMode: View`, declared in the test module) with the same crash, and
   the shape of the `body` makes no difference — opaque, concrete or `Never`
   all crash.

### It is not incremental, and it is not fixed upstream

Reproduced after `rm -rf .build` — a from-scratch build of all 1,362 modules —
and in a plain executable target as well as under the test harness, so it is
neither a stale-build artefact nor something about `swift-testing`. Rebuilt with
the **Swift 6.5-dev snapshot of 2026-08-30** and it segfaults there too, in the
same two cases and no others.

(That snapshot cannot compile TUIkit as it stands, for an unrelated reason: a
`swift-frontend` crash in the `LoadableByAddress` SIL pass on
`MouseEventDispatcher.pendingHoverExit`, a tuple-in-an-`Optional` property.
Rewriting the tuple as a small struct gets past it, which is how the check above
was run.)

### The fix, and what it cost

Moving the conformance into `TUIkitView`, the module that owns `View`, makes it
go away — confirmed on both toolchains. That is what shipped, and it is not one
line:

| Moved | From → To | Why it had to |
|---|---|---|
| `Color.foregroundCodes` / `backgroundCodes` / `downsampled(to:)` / `backgroundEscape` | `ANSIRenderer` (`TUIkit`) → `Color+ANSICodes.swift` (`TUIkitStyling`) | The fill has to be painted from `TUIkitView`, which needs a colour's escape. They depend on nothing above `TUIkitStyling`, and reading `colour.backgroundCodes()` is better than `ANSIRenderer.backgroundCodes(for: colour)` anyway |
| `PaletteEnvironment.swift` | `TUIkit` → `TUIkitView` | A semantic colour is a palette reference; the fill must resolve it |
| `ColorAnimation.swift` | `TUIkit` → `TUIkitView` | So a `Color` used as a view still FADES under `withAnimation`. Everything it needs was already in `TUIkitCore`/`TUIkitView` |
| `_StyleFillBlock` + `extension Color: View` | `TUIkit` → `TUIkitView` | The conformance itself, and the body it returns |

`TUIkitView` gains a dependency on `TUIkitStyling` for this and nothing else.
The four gradient types are unaffected — they are `TUIkit`'s own, so their
conformances were already in the module that declares them, and they keep
`_StyleFillBlock().background(self)`.

The one real cost is that a flat `Color` is now painted in `TUIkitView` rather
than through `.background(_:)`, so there are two paths where there was one.
`StyleAsViewTests` pins them byte-identical over the same rectangle, semantic
colours included, so they cannot quietly drift apart.

**If the toolchain fixes this, all of it can move back and the dependency can
go.** The comment on `extension Color: View` says so, in the file.

---

## 15. Banding a concatenation

`Text("aaa") + Text("bbb")` under a horizontal ramp used to come out one flat
colour — the ramp's representative for the whole line — because the attributed
path and the ramp path were two separate branches and only one of them could
run. §11 recorded that as "its own piece of work"; this is that work.

What it needs is that the cell decides the colour and the fragment decides
everything else about it, which is one loop rather than two:

```
band(_ text:column:row:style:sampler:sequences:into:)
```

is now the only place the per-cell walk lives, and a plain line is one call to
it while an attributed line is one call per fragment. So the seam is invisible
by construction — `("aaa" + "bbb")` and `"aaabbb"` produce byte-identical ink,
which is a test rather than a claim — and a fragment cannot disagree with a
whole line about where a colour changes.

Three rules fall out of it, all tested:

- **A fragment that states its own colour keeps it.** An explicit colour beats
  an inherited style here as everywhere else, so
  `Text("aaa").foregroundStyle(.grey) + Text("bbb")` under a ramp is a grey
  "aaa" and a banded "bbb".
- **A fragment's other attributes survive.** The ramp supplies a foreground,
  not a style, so a bold fragment stays bold through it.
- **A vertical ramp still costs one run per line.** The fast path
  (`variesAcrossRow == false`) is inside `band`, so it applies per fragment
  too, and the cheap case a list actually uses stays cheap.

The SGR introducer cache is per fragment STYLE rather than per line: an
introducer is only reusable among fragments that agree about bold, underline
and the background. A concatenation is a handful of fragments, so the lookup is
a linear scan of an association list rather than a hash of a `TextStyle`.

### What sharing the loop cost, and what it did not

Release, 40 lines × 100 cells, per call, paired runs:

| | before | after |
|---|---|---|
| vertical ramp (one run per row) | 26.4, 27.7 µs | 26.3, 25.5 µs |
| horizontal ramp (a run per cell) | 418.5, 399.7 µs | 372.6, 374.7 µs |

The first draft of the shared loop was **4.5× slower on the vertical path**
(26 → 118 µs), and both causes are worth writing down because neither is
visible in the diff:

1. It reserved the varying case's worst case — 25 bytes per cell — on every
   row, including the rows that emit one run. A 40 × 100 block reserved 100 KB
   to hold about 4 KB.
2. It advanced the column cursor by walking every character for its width, on a
   path where nothing reads the cursor: a row of one colour cannot care where a
   later piece starts. That grapheme walk is the same one that measured 14.6%
   of a frame in the width scan.

Both are now inside the varying branch, where they belong. The horizontal path
came out ~7% faster than before, from the reservation counting what is already
in the buffer.

---

## 16. Animating a ramp

The question that kept this out of the original design was "which stops move,
and how does a two-stop ramp become a five-stop one?" — and it turns out not to
need an answer, because it rests on a false premise: that a gradient has to
animate as ONE value.

It does not. A gradient is a handful of independent numbers — each stop's
colour, each stop's location, and the geometry's four — and each of them
animates on **its own animation-store entry**, exactly as a colour does. That
is the whole of `PaintAnimation`, and everything falls out of it:

- **Different lengths are not a special case.** Growing a two-stop ramp into a
  five-stop one fades the two that were already there and shows the three that
  were not at their final colours, because the store's existing rule for a
  value it has never seen is that *an appearance is not a change*. Nothing had
  to be invented for it.
- **Semantic colours work**, because `ColorAnimation` already resolves against
  the palette at the moment it is asked — which is the reason colours do not go
  through `Animatable` in the first place.
- **A stop that slides, slides.** A location is a `Double`, and the store is
  generic over `VectorArithmetic`.
- **The geometry moves**, so a ramp can sweep across a view: a `startPoint`
  travelling from `.leading` to the centre is four numbers moving.

### What snaps, and the slot map that makes it snap

A change of KIND snaps — a colour becoming a ramp, a linear ramp becoming a
radial one. Every geometry happens to carry exactly four numbers, and that
coincidence is precisely what must *not* be relied on: a linear geometry's four
are two points and a radial's are a centre and two radii, so interpolating one
into the other moves a radius toward an ordinate. So each kind takes its own
slot range and the store sees the new one as something it has never seen.

| Quantity | Slot |
|---|---|
| A flat colour | `0` |
| Stop *i*'s colour | `1 + 2i` |
| Stop *i*'s location | `2 + 2i` |
| Geometry kind *k*, component *c* | `-1 - (4k + c)` |

Slot 0 is left to the flat colour on purpose: sharing it would half-fade a
ramp's first stop out of the colour that was there, which is a stranger picture
than a clean snap.

The extent named by `.in(_:)` snaps as well. It is a statement about what the
ramp is measured against rather than about the ramp.

### What it costs

Eight store lookups per animated gradient per frame (a two-stop ramp: two
colours, two locations, four geometry numbers) against one for a colour. Both
`_StyleEnvironmentView` and `BackgroundModifier` run **once per modifier per
frame**, not once per leaf, so this is eight dictionary probes for a whole
`.foregroundStyle(gradient)` subtree. A paint that is a plain colour still
costs exactly the one lookup it always did.
