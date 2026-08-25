# Opacity as composition, not as a blend

**Status: implemented in full as of 2026-08-24 — §9.5's staging, and then the
§10 refinements (continuous colours, the contested-only threshold, parallel
matched cells, linear-light arithmetic, displayed-colour reads, ink coverage,
wide-character footprints). Outstanding: `Color`-level alpha (`.clear` and the
`opacity:` initialisers), recorded in `Parity-decisions-pending.md`.**
Commissioned
to answer two questions before any of it is built — does it add complexity or
caveats, and does it cost performance — and to settle the two parity entries
that depend on it (`Color.clear`, and every initialiser taking `opacity:`).

---

## 1. What is wrong today, measured

`View.opacity(_:)` blends every colour the subtree draws toward **the palette
background**, at render time:

```swift
let surface = palette.background.resolve(with: palette)   // OpacityModifier.swift:89
```

That is a guess about what is behind the view, and its own documentation says
so: *"It cannot see what is behind the view … The two agree except over a
non-background fill."* They do not agree, and here is the difference. A `ZStack`
with a red field and a label over it, rendered three ways:

| | the label's foreground |
|---|---|
| `.opacity(1)` | `38;2;51;255;51` — green, as written |
| `.opacity(0.5)` | `38;2;28;132;28` — green faded toward BLACK, not toward red |
| `.opacity(0)` | `38;2;5;10;5` — **still drawn**, as near-black text |

The last row is the bug in its clearest form. `opacity(0)` is supposed to make
a view invisible while keeping its space; over a coloured sibling it instead
paints a dark smudge, and the red field it should be revealing stays hidden
behind glyphs nobody can see.

Two separate faults, worth naming apart because they have different fixes:

1. **The blend target is wrong** — it fades toward the palette background
   rather than toward what is actually there.
2. **The glyph is drawn regardless** — alpha never reaches the question of
   *whether* to draw, only what colour to draw in.

## 2. What "correct" can mean here, and what it cannot

A terminal cell holds **one character in one foreground colour on one
background colour**. There is no alpha channel to write, and no sub-pixel
coverage. So alpha can be honoured exactly for *colours* and only
approximately for *glyphs*:

- **Colours compose exactly.** `result = src·α + dst·(1−α)`, per channel, for
  both foreground and background. This is ordinary alpha compositing and a
  terminal can express every result of it.
- **Glyphs cannot.** Two characters cannot occupy one cell at 50% each. The
  cell shows one of them, so alpha becomes a *decision*: at what α does the
  source glyph stop being drawn and the destination's show through?

That decision is the one genuinely new caveat, and it has no answer that is
right everywhere. The candidates:

| rule | reads well | reads badly |
|---|---|---|
| α > 0 draws the source glyph | a fade-in appears immediately | `opacity(0.01)` hides what is behind it completely |
| α ≥ 0.5 draws the source glyph | a cross-fade swaps at the midpoint, like a dissolve | a fade-out "pops" at 0.5 rather than vanishing |
| α = 1 draws the source glyph | perfectly predictable | any fade at all shows the destination's text in the source's colour — nonsense |

**Recommendation: α ≥ 0.5, and below it draw nothing at all** — which
subsumes the α = 0 case rather than special-casing it, and is what §6a builds
on. The midpoint is what a dissolve does, and "below the midpoint, the layer is
not there" is one comparison.

A blank cell is not a glyph, and that matters more than it sounds: most of what
a faded subtree contributes is spaces, and a space should never hide what is
behind it. **A source cell whose character is a space composites its background
and lets the destination's glyph through.** Without that rule, fading a `VStack`
would blank the entire rectangle it occupies.

## 3. Where alpha would live

Three designs, and they are not alternatives — (a) is a subset of (b).

### (a) Alpha as a field of `Color.ColorValue`

`Color` gains `.opacity`, `Color.clear` is alpha 0, and the three
`opacity:`-taking initialisers become mechanical. Composition happens wherever
two colours meet.

**Against:** a colour cannot see what it is drawn over any more than a view can.
`Color.red.opacity(0.5)` still has to be resolved against *something*, and
resolving it at render time is exactly the guess we are trying to remove. This
buys the API surface without buying the correctness.

### (b) Alpha as a property of a LAYER — the recommendation

A subtree with opacity renders to its own `FrameBuffer` and carries α with it.
The blend happens in `composited(with:at:)`, where the destination is finally
known.

This is also SwiftUI's semantics, which is not a coincidence: `.opacity` there
is a layer operation, so two overlapping children inside one `.opacity(0.5)`
group blend once against what is behind the GROUP, not twice against each
other. A `FrameBuffer` is already exactly that layer, so the semantics come
free — today's render-time blend gets this wrong for overlapping children and
nobody has noticed because the blend target is constant.

**Nesting multiplies**: a 0.5 group inside a 0.5 group composites at 0.25, and
that falls out of compositing inner-to-outer without special handling.

### (c) Both

(a) rides on (b): once the compositor blends, a colour carrying alpha is just a
one-cell layer. Worth doing, and worth doing *second* — it is the API, and (b)
is the correctness.

## 4. What it would take

The pieces exist. This is assembly, not invention.

1. **`FrameBuffer.opacity: Double`** (default 1), carried through
   `replacingLines`, `shifted*`, and every combining operation — the same
   plumbing `animatedCells`, `hitTestRegions` and `overlays` already have.
2. **Blending in the compositor.** `composited(with:at:)` currently splices
   overlay text into base text by visible column (`insertOverlay`). For α < 1
   it must instead decompose BOTH sides into cells, blend, and re-emit.
   `ANSIRowCells(decomposing:width:)` already does the decomposition — it is
   what the frame diff uses — and `SGRColorRewrite` already does the re-emission
   for every colour effect in the framework.
3. **The glyph rule** from §2, one comparison per cell.
4. **`OpacityModifier` stops blending** and only sets the field. It keeps its
   animation machinery (below).
5. **`Color.opacity(_:)` stops mixing toward black.** It is currently a
   documented lie — `opacity(_:over:)` exists precisely because it is — and
   with (c) it becomes a real alpha.

## 5. Complexity and caveats — the first question

**New caveats, honestly:**

- **The glyph rule is a threshold**, and thresholds are visible. A cross-fade
  will swap characters at 0.5 rather than dissolving. There is no way around
  this in a cell grid; it should be documented at the modifier, not buried.
- **`opacity(0)` becomes genuinely invisible**, which is a behaviour change:
  today it paints a near-black rectangle, and some layout may be leaning on
  that rectangle hiding what is behind it. That is a bug being fixed, but it is
  a change.
- **A screen-level overlay cannot be composited into its parent** — it is
  hoisted to the root by definition — so an α applied above one either does not
  reach it or has to travel with it. `OpacityModifier` already has this
  distinction (`layer.isScreenLevel`), so the shape is known.

**Caveats that go away:**

- The "blends toward the palette background" note disappears from the modifier's
  documentation, along with the class of bug it warns about
  ([[opacity-dim-blend-class]] in the working notes: `Color.opacity` toward
  black, dark-on-dark controls under light palettes).
- Overlapping children inside one opacity group stop double-blending.
- `Color.clear` becomes expressible, and the parity entry for it closes.

**Complexity added:** one field, one branch in the compositor, one threshold.
The decomposition and re-emission are existing, tested code. This is genuinely
smaller than the render-time version it replaces.

## 6. Performance — the second question

Where the cost moves:

| | today | proposed |
|---|---|---|
| when | once per render of the faded subtree | once per COMPOSITE of the faded layer |
| what | rewrite the subtree's SGR colours | decompose source AND destination cells, blend, re-emit |
| scope | pays wherever `.opacity` appears | same — an α of 1 is the identity and takes an early return |

Two real risks, both measurable before committing to anything:

1. **Double decomposition.** Blending needs the destination's cells, which
   today's render-time fade never touches. Worst case is a large faded layer
   over a large destination, every frame.
2. **The pre-rendered animation cycle.** `OpacityModifier` has a fast path that
   renders a repeating fade ONCE and hands the run loop every phase as
   `AnimatedCellRun`s — which is what keeps a pulsing fade off the render path
   entirely. That path computes each phase at render time, and a
   composite-time blend does not know the destination then. **If this path is
   lost, a repeating fade costs a full render per frame again**, which is a far
   bigger regression than anything the blend itself costs.

   It is probably recoverable — the destination under a fading layer is usually
   static, so the phases could be composited once against it and re-composited
   only when the destination changes — but "probably" is why this is the first
   thing to measure.

**Measurement plan**, using the committed tools rather than a new one:

- `ab_bench.py` on `Stress` before and after, all scenarios, with a null run
  first to establish this machine's floor.
- A new stress scenario is needed: none of the seventeen currently uses
  `.opacity`, so the sweep would measure nothing. It should have a faded layer
  over a busy destination, which is the worst case.
- `Tools/Profiling/idle_cpu.py` on a page with a repeating fade, to catch the
  animation-cycle regression as a *byte rate* rather than as a profile.

## 6a. The stylised alternative, and why it wins

**The suggestion:** don't mimic a GUI compositor. Blend the faded layer's
foreground *and* background toward **the background colour of the layer below**,
and always draw the character.

That is a smaller idea than §3–5 and it fixes the fault that actually shows.
Recall §1 named two faults: the blend target is wrong, and the glyph is drawn
regardless. This fixes the first and leaves the second — which is exactly the
right trade if the second is not really a fault. Three candidates, then:

| | needs from the destination | glyph |
|---|---|---|
| **A. Full cell compositing** | background, foreground AND character | a threshold decides which character shows |
| **B. Blend to the surface** | background only | always the source's |
| **C. B, with the threshold** | background only | source's above ½; below ½, nothing is drawn at all |

**Where B alone breaks, and it is the case you named.** At `opacity(0)` the
cell becomes a solid block of the destination's background colour. Invisible
against that background, yes — but it has *erased the destination's character*.
A faded-out label over text leaves a correctly-coloured hole in the text. And
because the glyph never yields, that is true at every α, not only at 0: two
pieces of text can never show through one another.

**C is the two ideas combined, and it costs what B costs.** Below the
threshold the source cell is not drawn *at all* — not blended, skipped — so the
destination is simply left alone, character and colours. Above it, the source
draws its own character over a background blended toward the destination's.
Either way **the destination's character is never consulted**, only its
background colour: nothing has to decide *between* two characters, because the
threshold has already decided *whether* there is a source character to draw.

So C gets A's two headline behaviours — `opacity(0)` genuinely reveals what is
behind, and text can pass through text — at B's implementation cost, and
without the part of A that is hardest to justify in a cell grid (tinting the
destination's text with the source's colour, which is prettier in a GUI and
less legible here).

Two rules complete it, and both are small:

- **A source SPACE composites the background and keeps the destination's
  character.** Otherwise a faded `VStack` blanks its whole rectangle: most of
  what a layer contributes is spaces.
- **The destination's foreground is left alone.** A translucent pane over text
  would, in a GUI, tint that text. Here it does not — the text keeps its own
  colour and the surface behind it changes. That is the "stylised" part, and it
  is a deliberate simplification rather than an oversight.

**Recommendation: C.** It is what the two instructions converge on — keep it
simple and always draw the character, plus try the threshold at ½ — and it is
strictly less machinery than A.

## 6b. Performance: what "losing the pre-rendered fade" actually means

The note above said losing it would cost a full render per frame. That
overstates it, and the correction matters because it changes whether this is a
risk or a footnote.

The fast path renders the content once, computes every phase of a repeating
fade by re-colouring the finished lines, and hands the run loop the lot as
`AnimatedCellRun`s — after which the loop replays them and never renders again.
Under composite-time alpha the phases cannot be computed at RENDER time,
because the destination is unknown then. But they can be computed at
**composite** time, which is still inside the same frame. So:

- **A fading layer over a STILL destination keeps the fast path**, exactly as
  today. Composite each phase against the destination once, hand those over,
  and the loop replays them. This is the common case — a badge fading over a
  page that is not otherwise moving.
- **It is lost only when the destination CHANGES**, because the pre-composited
  phases are then stale. And on such a frame the destination was being
  re-rendered anyway, so the cost is not a render — it is **N composites of the
  faded layer instead of one**, where N is the phase count (16 for the current
  cycles).

So: never "always", and never a full extra render. The worst case is a fade
over something that moves every frame, which re-bakes the phases every frame.
Whether that matters depends entirely on the layer's area, which is why §6's
measurement plan wants a stress scenario with a faded layer over a busy
destination — that is the case, and nothing existing measures it.

### What a read of the fast path adds, and it is the binding constraint

Four facts, from mapping `_OpacityView.cycling` → `AnimatedBufferCycle.runs` →
`ReplayableFrame` → `replayAnimations`:

1. **A phase is a finished STRING**, not a colour and a rule. Colour
   resolution, contrast correction and 256-cube downsampling are all done at
   bake time and frozen into bytes. Up to 120 phases, one line-set each.
2. **It has to be**, and this is the constraint rather than a choice:
   `AnimatedCellRun` lives in `TUIkitCore`, which cannot see `Color` at all
   (`TUIkitCore` and `TUIkitStyling` are siblings with no dependency between
   them). A run cannot carry "this colour, faded by that much" because it
   cannot name a colour.
3. **`ReplayableFrame` keeps no way back.** It holds finished rows, run
   offsets and a frame index — no view tree, no palette, no link from a run to
   the buffer that produced it. The replay indexes an array and splices; it
   cannot recompute a frame.
4. **The frames are load-bearing for scheduling**, not only for painting:
   `timeUntilNextChange` derives the loop's sleep from string equality between
   consecutive frames, so a quantised fade whose phases render identically
   costs no wake-ups.

Two consequences for the implementation:

- **The bake must move to composite time, and it can**, because every one of
  the eight `composited` callers lives in the umbrella module where `Color` is
  visible. The bake costs the same as it does today — N phases × rows of string
  rewriting — it simply happens against a real destination instead of an
  assumed one. It is only *repeated* when the destination changes.
- **The replay needs nothing new.** `patchingAnimatedCells` already reads the
  destination's background at the run's column and re-states it around the
  frame; that a destination read exists there at all is what makes the
  splice-a-pre-baked-frame model survive this change.

So the fast path is keepable, and keeping it is a matter of moving one call
rather than redesigning the replay.

## 7. Staging, and whether it wants a branch

Four steps, each shippable and each verifiable on its own:

1. `FrameBuffer.opacity` plumbed through, unused. Behaviour-neutral; proves the
   plumbing without touching a pixel.
2. The compositor blends. `OpacityModifier` still does its render-time fade, so
   nothing changes yet — but the compositor can be tested directly.
3. `OpacityModifier` switches to setting the field. **This is the behaviour
   change**, and where the `ZStack` case above starts being right.
4. `Color` gains alpha; `.clear` and the `opacity:` initialisers follow.

Steps 1–2 are additive and safe on `main`. Step 3 is the one that changes
pictures, and the one whose performance needs the A/B — so **a branch earns its
keep from step 3 onward**, where "make it correct" and "make it cost nothing"
are separate commits and the second may need several attempts.

## 8. What this settles

- **`Color.clear`** — expressible as alpha 0 under (c). The parity entry says
  it waits on this decision, and this is the decision it was waiting for.
- **`Color.init(…opacity:)` × 3** — mechanical under (c).
- **`Color.opacity(_:)`** stops being a documented lie, and
  `opacity(_:over:)` becomes redundant rather than necessary.

---

## 9. What mapping the combining sites found (2026-08-24)

Every place a `FrameBuffer` is drawn onto another was read before writing the
consuming code. It changed the design, and it is recorded in full because most
of these fail SILENTLY — the picture is plausible and only slightly wrong.

### 9.1 The shape has to be regions, not a scalar

`appendVertically` does `storage.append(contentsOf: other.lines)` and discards
everything else about `other`. So a whole-buffer `opacity` dies at the first
stack:

```swift
ZStack {
    Color.red
    VStack { Text("x").opacity(0.5) }   // never reaches the composite carrying α
}
```

**Every `VStack`, `HStack`, `Grid` row, `TupleView` and `Group` is such a
barrier**, which is very nearly every faded view anyone will write. A scalar
therefore delivers the promise only when the faded view is composited
*directly*, and quietly gives today's answer otherwise — the worst kind of
partial fix, because the caveat is invisible at the call site.

So the payload is **a list of regions** — rect plus α — shaped exactly like
``FrameBuffer/animatedCells``: shifted by every combining operation, consumed
at the composite or at the root. That pattern is already load-bearing in this
codebase for runs, hit-test regions and overlay layers, and there is a standing
audit (`ContainerPayloadAudit`) that exists because each of those was dropped
by a container at least once. A fourth payload joins the audit rather than
inventing a mechanism.

The scalar committed as step 1 is superseded by this and must be replaced
before anything consumes it.

### 9.2 Both source channels blend; the destination's foreground does not

Worth pinning because the two rules read similarly. The **source's foreground
and background** both blend toward the destination's background. The
**destination's foreground** is left alone. Blending only the source's
background would leave green text on the plain app background completely
unfaded, which is not a fade at all.

### 9.3 The destination's background is usually not in the destination

**The hardest part, and it is not the blend.** The palette background is
injected LAST — by `FrameDiffWriter.buildLine`, and by
`ANSIRenderer.applyPersistentBackground` for a `.background(_:)` container. So
`line.ansiSGRStateAt(visibleColumn:).renderedBackground` — the only
destination read that exists today, the one `patchingAnimatedCells` uses —
returns `""` for the majority of cells.

"Blend toward the destination's background" therefore has a two-part answer:
the destination's **explicit** background where it painted one, and an
**ambient surface handed in from outside** where it did not. Every consuming
site needs that surface, and it is not the same colour everywhere: the content
area's is `palette.background`, the app header's is
`palette.appHeaderBackground`, the status bar's is
`palette.statusBarBackground`. `RenderBackgroundCodes` already keeps the three
apart for exactly this reason.

### 9.4 The leak paths, each of which fails silently

| | what leaks | what it needs |
|---|---|---|
| **L2** | `composited` builds its result with a bare `Self(lines:)` and drops the DESTINATION's own α | carry it onto the result |
| **L3** | 65 bare `FrameBuffer(lines:)` rebuilds, live ones in `DimmedModifier`, `DropdownMenuRenderer`, `AppHeader`, `Alert`, `ProgressView`, `NavigationSplitView`, `Color256Grid` | convert to `replacingLines`, and a test that α survives a `.padding`/`.border`/`.frame` wrap |
| **L4** | `.offset`/`.position` return a placeholder of empty lines with the real drawing in `overlays[…].content`, so α on the placeholder fades nothing | multiply into every non-screen-level layer's content, recursively — the recursion `cyclingOverlays`/`fadingOverlays` already perform |
| **L5** | the app header and status bar render real view trees and go straight to `buildOutputLines` | resolve against their OWN backgrounds, not `palette.background` |
| **L6** | runs emitted by other views inside a faded subtree — a pulsing button under `.opacity(0.5)` — carry unfaded frames and replay at full strength over a faded row | **CLOSED**: the resolution drops them. A missed saving rather than a frozen animation — `noteServedByRuns` is the only thing that stops the loop rendering for an animation and `.opacity` is its only caller, so every other producer keeps asking for frames and simply pays for them |
| **L7** | `FrameBuffer.==` excludes the new payload, and the render/measure memo keys on it — so an unfaded buffer is served where a faded one is wanted | include it in `==`; α is content, not a perf hint |
| **L8** | golden snapshots and interaction tests drive `renderToBuffer` / `compositingOverlays` directly, and nothing resolves α there — so every golden of a faded view records the UNRESOLVED buffer and passes while the app is wrong | a public `resolvingOpacity(over:)`, called by the snapshot harness |
| **L9** | `FrameBuffer.overlay(_:)` is public, unused, and a fourth combining semantics that would ignore α | delete it (pre-1.0, no shims) |

L8 is the one worth dwelling on: it is the "test passed while the app broke"
shape exactly, and it would have been introduced by this change rather than
found by it.

### 9.5 Revised staging

1. ~~**Payload as regions**, carried and shifted, consumed by nothing —
   including `==` (L7) and the `ContainerPayloadAudit` case.~~ **Done.**
2. ~~**L3 and L9**: convert the bare rebuilds, delete the dead
   `overlay(_:)`.~~ **Done** — five hand-assembly sites had three payloads of
   four, and `FrameBuffer.overlay(_:)` is gone.
3. ~~**The blend**, at the composite and at the three roots, with the ambient
   surface plumbed (9.3).~~ **Done**, as
   `FrameBuffer.resolvingOpacity(over:at:surface:palette:)`.
4. ~~**`OpacityModifier` sets regions instead of fading.**~~ **Done**, and the
   fast path moved with it rather than regressing: the modifier stamps the
   whole `OpacityCycle` on the region and the RESOLUTION bakes its phases,
   which is the "compute the phases at composite time" of §6b. Measured on the
   Example's Animation page with `idle_cpu.py`, twelve Tabs and a click to
   turn "Breathe" on — 512 B/s at 0.2–0.3% CPU before, **480 B/s at 0.2–0.3%
   after**, against 214 B/s for the same page with the fade off. So the
   never-ending fade still costs no render passes.
5. ~~**Restore the fast path**, the Example demo, the stress scenario, the
   A/B.~~ **Done.** The demo is the Example's Opacity page (`o`); the scenario
   is `translucent`, a large faded panel over a destination that redraws every
   frame, which is §6's named worst case and which nothing else measured.

   The A/B, `ab_bench.py` against the commit before the switch-over, both
   binaries carrying the same scenario:

   | | old µs | new µs | change | 95% CI | verdict |
   |---|---|---|---|---|---|
   | `translucent` | 684.1 | 680.5 | +0.0% | −2.5% … +0.9% | indistinguishable |

   And the seventeen-scenario default sweep, to catch a cost paid by trees that
   do not use opacity at all: every one indistinguishable, `dashboard` (−1.3%)
   and `kitchensink` (−0.4%) marginally faster. So the payload costs nothing
   where it is absent, and the blend costs nothing measurable where it is
   present.

6. **Outstanding**: `Color`-level alpha — `.clear` and the three `opacity:`
   initialisers (§8). See `Parity-decisions-pending.md` §1–2: the region is a
   claim about a whole CELL, a colour's alpha is a claim about one CHANNEL, and
   nothing knows which cells a colour painted.

### 9.6 What the implementation added to the design

- **L8 was real and was closed by a helper, not a note.** The test support
  gained `renderToScreen`, and `assertSnapshot` uses it: a golden recorded
  from `renderToBuffer` would capture the unresolved layer and agree with
  itself forever while the app drew something else.
- **A cycling region must survive its own opaque phases.** The resolution
  drops regions at α = 1 as the identity, which silently dropped every
  repeating fade whose current phase happened to be full — usually its first
  frame, so the fade never started.
- **The compositor is told "served by runs" BEFORE it bakes**, not after. The
  bake happens frames later in the same pass and out of the view's reach, and
  a cycle still marked "needs rendering" wakes the loop every tick whatever
  the compositor produced.
- **The page's own regions resolve at the top of `compositingOverlays`**,
  before any layer is drawn over it. Left pending, a region would go on naming
  cells a layer had since replaced, and the LAYER's cells would be faded at
  the root.
- **A baked run covers the whole ROW, not the region's columns.** That is what
  makes the frame the loop splices byte-identical to the line the render drew
  rather than merely equivalent to it — a narrower frame would be a SLICE of
  the line, and a slice re-establishes SGR state at its start, so the bytes
  part company even where the cells do not. The cost is that a narrow fade on a
  wide page bakes page-width rows: for the Example's breathing text, ~30
  columns on a 120-column page, four times the strings the old render-time bake
  built. Measured as immaterial (unchanged CPU, 480 vs 512 B/s), so it stands.
  If it ever matters, the fix is in `AnimatedBufferCycle`, not here: trim the
  common prefix and suffix across a row's frames and re-state the style at the
  trimmed start, which would narrow every cycle producer's runs and not just
  this one.

## 10. The refined blend (2026-08-24)

§6a chose the stylised model, and it shipped as described. Working with it on
screen surfaced refinements; this section is the current rule set, and §6a
stands as the record of why the family of models looks like this at all. The
organising principle the refinements converge on:

> **Colours blend at every alpha; only the choice of glyph needs a decision,
> and only where two glyphs genuinely contest the cell.**

The rules, updated as each lands:

1. **A source space composites its background at every alpha**, not only at or
   above the glyph threshold. The threshold exists because two characters
   cannot share a cell; a space is not a character contest, and gating its
   background on ½ made a translucent panel vanish whole at the midpoint
   instead of fading smoothly to nothing. (The panel-pop was the visible
   artefact of the first implementation: the ½ guard sat above the space rule
   and gated colours it had no business deciding.)

2. **The threshold applies only where two glyphs genuinely contest the cell.**
   Over a blank destination cell the source's character draws at any alpha,
   fading continuously toward what is behind it — there was never anything to
   reveal underneath, so gating it on ½ made text over a plain panel vanish at
   the midpoint of a fade for no one's benefit. The ½ decision now fires only
   where the destination has a character of its own, which is the case §6a's
   argument was actually about.

3. **A yielded glyph contest still composites the veil's background.** To the
   cell it lost, the source is a pane of background — exactly what it is to a
   space — so the destination keeps its character and its foreground, and its
   field carries the veil at the region's alpha. Without this a translucent
   panel over text tinted every blank cell and skipped every character-holding
   one, reading as a sieve rather than a veil; it also shrinks the visible step
   at the ½ crossing to the glyph swap alone, since the field no longer jumps
   from half-tinted to untouched. "The destination is UNTOUCHED below the
   threshold" (§6a) narrows to its foreground and character; exact untouched
   reveal still holds at 0, where the tint's weight is zero.

4. **Matching characters cross-fade in parallel.** Where both sides hold the
   same character there is no contest: the source's ink sits exactly where the
   destination's does, so foreground blends toward foreground and background
   toward background, continuously through every alpha with no threshold
   anywhere. A colour change on unchanged text is exact. (This generalises the
   space rule, which is the same statement for the character " ".) The one
   thing that cannot blend is weight — bold is on or off — so a matched cell's
   non-colour styling follows whichever side alpha favours.

5. **The blend happens in linear light.** `Color.opacity(_:over:)` (and
   `lerp`, underneath it) interpolates the ENCODED sRGB components. For style
   derivation that is right — every palette the framework derives was tuned by
   eye in encoded space, and re-deriving them through different arithmetic
   would re-tint the whole system, so those stay as they are. Simulating a
   translucent layer is a different question with a physical answer: light
   adds linearly, and mixing encoded bytes understates it (halfway between
   white and black lands at 22% of white's light rather than half), so an
   encoded-space fade spends most of its range darker than the light it
   stands for and pops at the end. The resolution — and the transition
   dissolve, which is the same operation against the palette background —
   now blends through `Color.compositing(_:over:)`: decode via the shared
   IEC 61966-2-1 helpers, mix, re-encode with rounding.

6. **The blend reads the colours a cell DISPLAYS, not the ones it stores.**
   Reverse video (SGR 7) makes the foreground the colour the cell is painted:
   a reversed space is a solid fill, not a blank, and the field behind a
   reversed cell is its foreground, not its background. The cell decomposition
   normalises this — colours exchanged, the attribute dropped, the unstated
   side resolving to the terminal's *other* default — so every rule downstream
   sees what the viewer sees. And "space" everywhere above means NO INK, which
   is more than the character: an underlined or struck-through blank draws a
   pattern in its foreground colour, so it fades as a glyph and is revealed as
   one. The definition is shared with `FrameDiffWriter` through
   `SGRState.reversesVideo` / `paintsInkOnBlankCell`, whose codes are
   `visibleOnBlankCell` minus 7 — one vocabulary for "what is observable on a
   blank cell", used by both consumers.

7. **"Behind" means the average colour a cell displays, estimated by ink
   coverage.** A drawn glyph covers the whole destination cell — ink included —
   so what it fades toward is the cell's field and its ink mixed by the ink's
   fraction of the cell (`Character.inkCoverage`): exact by construction for
   the geometric glyphs (blocks, halves, quadrants, eighths, shades, Braille —
   precisely the characters used AS solid colour), an estimate everywhere else
   (0.15 for text, 0.1 for box lines). One algorithm, varying confidence: an
   unrecognised character gets the text-shaped estimate, not a different
   blending cliff. The same number makes a yielded cell's veil honest — the
   source's paint is its background with its ink mixed in, and a source with
   ink but no background tints at alpha scaled by coverage. Emoji are a knowing
   omission: colour bitmaps ignore the foreground colour, so no arithmetic can
   fade them and the glyph threshold is the only lever a terminal offers.

8. **A revealed wide character must own every column it claims.** The span
   walk advances by what it emits, so a two-column 日 revealed by a one-column
   decision would swallow the next source column's own answer — a cell the
   region might not even cover. A destination character wider than the source
   character over it is therefore revealed whole only when the footprints
   match (wide over wide, aligned); anywhere else one column of the
   destination's field stands in, because half a glyph cannot be drawn. Two
   knowing approximations sit nearby: a region boundary slicing a wide SOURCE
   character fades it by the alpha at its start column, and a destination wide
   character whose start lies outside the resolved span reveals as its field —
   the terminal cannot draw half of it either.

Checked for §10 and found already handled, no change needed: quantisation can
make adjacent phases of a repeating fade byte-identical, and the replay
machinery already charges nothing for them — `timeUntilChange` scans past
identical frames when scheduling wakes, and the replay tick-skip compares
frame CONTENT, so a repeated frame costs neither a wake nor a write. Measured
unchanged either way: the Example's breathing fade replays at the same byte
rate and CPU before and after the refinements.
