# Opacity as composition, not as a blend

**Status: implemented in full as of 2026-08-24 — §9.5's staging, and then the
§10 refinements (continuous colours, the contested-only threshold, parallel
matched cells, linear-light arithmetic, displayed-colour reads, ink coverage,
wide-character footprints).**

**`Color`-level alpha followed on 2026-09-10** (branch `colour-alpha`), which
closes what this document listed as outstanding and retires
`Parity-decisions-pending.md` §1 and §2. Five commits, and the shape of it is
worth recording here because it is not what §1 predicted:

- **A layer's alpha and a colour's are different claims wearing one number.** A
  layer at 0.3 is 30% *present*, so its glyph competes with what is behind it and
  §10's ½ rule decides; ink at 0.3 is faint text that is definitely drawn. So
  `OpacityRegion` carries three channels — `opacity`, `inkOpacity`,
  `fieldOpacity` — and the ½ threshold reads the LAYER's alone. Folding them
  would make a translucent foreground vanish rather than fade.
- **They compose by sequence, not by multiplication** (corrected 2026-09-09; see
  §11). A colour's alpha resolves *within* its layer, against the field the glyph
  sits on; the layer's alpha then composites that result against the backdrop.
  The field channel is unaffected, because both of its backdrops are the
  destination's field and sequential blends against one backdrop multiply
  exactly. The ink channel's two backdrops differ, and multiplying them into one
  blend is what put a `Table` row's translucent text on the wrong colour.
- **`Color` stores a `UInt8` alpha**, not a `Double`: `viewValueHash` hashes the
  raw bytes of every view struct and a `Double` would introduce undefined padding,
  making the render memo's key non-deterministic. Every `Color` → `Color`
  derivation carries it, checked by a table test rather than one test per
  function.
- **Three sites write it**, and they are the three that know the rectangle they
  painted: a `Color` used as a view, `.background(_:)`, and `Text`'s own
  foreground and background. Each writes the colour's OPAQUE spelling into the
  bytes and sends the alpha up as a region, because a translucent colour has no
  SGR spelling — the terminal has no alpha channel, so the only honest answer is
  this document's: resolved at the composite against what is actually behind the
  cell. `Text` stamps one region per LINE, since a wrapped text is ragged.
- **§1's cost estimate was for the wrong mechanism.** It counted 169 colour→SGR
  emit sites and concluded that per-colour alpha needed column knowledge at each.
  It does not: the three sites above are where translucency is actually written,
  and they know their rectangles already. What the other 166 get is an
  `assert(isOpaque)` at the four emitters, so an unmigrated path is loud in a
  debug build and renders exactly as it does today otherwise.
- **It costs nothing when nothing is translucent.** `ab_bench.py`, 14 reps,
  `main` against the branch: `translucent` **+0.3%** [−0.5%, +1.5%],
  `kitchensink` **+0.3%** [−0.7%, +0.5%], `deep` **−0.1%** [−0.4%, +0.1%] — all
  three indistinguishable, RAM flat to 0.1 MB. Expected, and worth having
  measured rather than assumed: an opaque colour stamps no region, so the only
  per-frame addition on the common path is `OpacityRegion.isTranslucent` in the
  resolver's drop filter (over a list that is usually empty) and an `assert` that
  compiles out of a release build.
- **Not honoured yet**, each said at its own line: a translucent gradient (a ramp
  states a colour per cell, and a region carries one alpha for a rectangle — the
  one place a rectangle is genuinely the wrong shape), `Text`'s attributed-run
  path, `Table`/`PaintRenderer`/`DimmedModifier`, and `TUIkitImage`, which cannot
  see `OpacityRegion` at all.
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
| scope | pays wherever `.opacity` appears | same — an α of 1 over an empty destination takes an early return (see §9.7) |

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

> **SUPERSEDED 2026-09-01** — the destination's foreground blends too. See
> §10 rules 3 and 7. The rest of this section stands as the record of what the
> mapping found.

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

One row is excluded from the blend and from the backdrop dim outright, and
is not a leak: an **image placeholder row** (U+10EEEE cells), whose
foreground colour IS the Kitty image id — any pass that rewrites foregrounds
turns the picture into a lookup of an image nobody transmitted. Both
combining sites test for the codepoint and pass the row through unchanged
(`OpacityResolution`, `DimmedModifier`); the boundary is stated in
`Terminal graphics protocols.md`. It is the one layer the model cannot fade.

| | what leaks | what it needs |
|---|---|---|
| **L2** | `composited` builds its result with a bare `Self(lines:)` and drops the DESTINATION's own α | carry it onto the result |
| **L3** | 65 bare `FrameBuffer(lines:)` rebuilds, live ones in `DimmedModifier`, `DropdownMenuRenderer`, `AppHeader`, `Alert`, `ProgressView`, `NavigationSplitView`, `Color256Grid` | convert to `replacingLines`, and a test that α survives a `.padding`/`.border`/`.frame` wrap |
| **L4** | `.offset`/`.position` return a placeholder of empty lines with the real drawing in `overlays[…].content`, so α on the placeholder fades nothing | multiply into every non-screen-level layer's content, recursively — the recursion `fadingOverlays` already performs (its sibling `cyclingOverlays` went with 54af97be, the commit this section is the design for) |
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
  drops regions at α = 1 over an empty destination, which silently dropped
  every repeating fade whose current phase happened to be full — usually its
  first frame, so the fade never started.
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

**REVISED 2026-09-01**, and the revision is a simplification: rules 3 and 7
below were an over-thought answer to "what is behind a glyph", and are now one
rule — each channel blends with its own counterpart, read the same way on both
sides. Rule 4 stopped being a rule at all, because it is what the general one
says. What that supersedes, and why, is under rule 7.

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

3. **A yielded glyph contest still takes the veil — in both channels.**
   Losing the glyph does not exempt a cell from the fade: the destination keeps
   its character, and both of its colours move toward the source's by the
   region's alpha, under rule 7. Without this a translucent panel over text
   tinted every blank cell and skipped every character-holding one, reading as
   a sieve rather than a veil; it also shrinks the visible step at the ½
   crossing to the glyph swap alone, since neither channel jumps. "The
   destination is UNTOUCHED below the threshold" (§6a) narrows to its
   character; exact untouched reveal still holds at 0, where the weight is
   zero.

   **REVISED 2026-09-01.** This rule used to end "and its foreground", keeping
   the destination's ink untouched on the argument that tinting text reads
   prettily in a GUI and illegibly in a cell grid (§9.2). It reads worse: the
   field washes out while the text stands at full strength, which is not what
   a veil does to what is under it. A pane covers the ink it lies over exactly
   as much as the field around it, and now fades both by the same alpha.

4. **Matching characters cross-fade in parallel** — which since 2026-09-01 is
   not a rule of its own but an instance of rule 7, and the branch that used to
   implement it is gone. Where both sides hold the same character the ink
   channels are each other's counterparts by construction, so the cell
   cross-fades continuously through every alpha with no threshold anywhere and
   a colour change on unchanged text is exact. The one thing that cannot blend
   is weight — bold is on or off — so a cell's non-colour styling follows
   whichever side drew its glyph.

5. **The blend happens in ENCODED sRGB — reversed 2026-09-04, and this is why.**

   It used to happen in linear light, through `Color.compositing(_:over:)`,
   on an argument that is physically correct and turned out to answer the
   wrong question: light adds linearly, and mixing encoded bytes understates
   it (halfway between white and black carries 22% of white's light, not
   half), so a linear mix is what a translucent LAYER really does.

   A fade is not measured by a meter, it is watched by an eye, and perceived
   lightness goes roughly as the cube root of luminance. So under a linear
   mix `dL/d(alpha)` is **7.52 at alpha 0 and 0.25 at alpha 1** — a **22.2×**
   sensitivity ratio, with almost all of the visible change crammed into the
   first few percent. Encoded sRGB is already close to perceptually uniform,
   which is what makes it the space every 8-bit compositor mixes in; its
   ratio is **1.66×**.

   The bill arrived at a bouncy spring. A spring transition plays the same
   oscillation in both directions — insertion opacity is `fraction`, removal
   is `1 - fraction` — so its excursions are exactly symmetric in ALPHA. In
   linear light they were 2.94×, 4.78×, 7.08× and 10.52× apart in rendered
   lightness (`spring(duration: 0.6, bounce: 0.9)`, accent over the default
   palette's ground), which is why the fade-out visibly bounced and the
   fade-in barely did. At the shipped default bounce of 0.3 the fade-in
   excursion measured ΔL **0.0000** while the fade-out one was still a step.
   Encoded, the same four excursions are **1.20×, 1.33×, 1.42× and 1.49×**.

   And it is what SwiftUI does. Measured through `ImageRenderer` over
   `ZStack { Color(5,10,5); Color(102,255,102).opacity(a) }`, SwiftUI's
   composite matches an encoded-space lerp to the byte at every alpha tried
   (0.05 → `10,22,10`; 0.28 → `32,79,32`; 0.85 → `87,218,87`), and does NOT
   match the linear-light prediction at any of them.

   So the resolution and the transition dissolve blend through
   `Color.opacity(_:over:)` — the same encoded mix style derivation has
   always used, which also removes the split where one screen faded two ways.
   `Color.compositing(_:over:)` remains, correct and public, for the question
   it actually answers.

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

7. **Each channel blends with its own counterpart, and the two never mix.**
   A cell shows its ink where its glyph draws and its FIELD where none does,
   and that one reading is applied to both sides of the blend: the source's ink
   composites over the destination's ink, its background over the destination's
   background. Nothing estimates how much of a cell a glyph covers, because
   nothing needs to — the question the estimate answered ("what colour is
   behind this ink?") only arose from mixing the channels together in the first
   place.

   Three consequences are the point of it. A label thinning out over an empty
   page fades into that page, because a blank cell's ink channel is its field.
   Text fading over a `█`-drawn swatch moves toward the swatch's own colour,
   because a drawn cell's ink channel is its glyph's colour. And a space is not
   a case of its own anywhere in the blend — it is a cell whose ink colour
   happens to be its field.

   A channel the source states nothing in composites nothing, and the
   destination's stands. That is EMPTINESS rather than blankness: a layer with
   no background of its own tints no field (which is what keeps a faded
   `VStack`'s padding transparent instead of a rectangle punched through the
   page), and a blank cell with no background paints no ink either. A faded
   label's spaces therefore leave what is under them alone while its letters
   fade — honest, and the same answer a fully transparent layer gets.

   **This replaces `Character.inkCoverage`, deleted 2026-09-01**, and with it
   the model where a cell's "paint" was its background with its ink averaged in
   by that estimate. Two faults, one reported and one found looking for it.
   Reported: with neither layer painting a background, the cells holding
   letters picked up a tint the blank ones did not, because a letter
   contributed to the field and a space did not — visible as stripes, and now
   pinned by `blanksAndLettersAgreeOnTheField` (the old model painted `w r d`
   on `48;2;1;56;3` and `o l` on `48;2;1;2;3`). Found: a yielded glyph tinted
   the cell it lost, at alpha × coverage — 0.43 × 0.15 of a bright foreground
   is a 6.5% wash, which is why a ZStack layer with no background of its own
   drew a greenish field below ½ and none at or above it. The estimate was only
   ever load-bearing where a destination was PARTIALLY inked; for the solid
   glyphs it was exact for (blocks, halves, quadrants, eighths, shades) it
   agrees with the rule above exactly, which is why the swatch case reads the
   same before and after. Emoji remain a knowing omission either way: colour
   bitmaps ignore the foreground colour, so no arithmetic fades them and the
   glyph threshold is the only lever a terminal offers.

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

### 9.9 A change the cube cannot represent is not a change

1% opacity drew a visible band. The arithmetic was right: 1% of a bright colour
over a near-black page lands about three units per channel away from it. The
256-colour cube is what turned three units into ninety-five — it is sparse, and
the nearest entry to a faintly tinted near-black is a SATURATED one, so two
cells whose true colours differed by three units quantised to entries ninety-five
apart. It also produced the asymmetry reported alongside it: a space cell (whose
paint is the source's field) and a glyph cell (whose paint is that field with
the ink mixed in by its coverage) differ by a few units at any alpha, correctly,
and the cube separated them visibly at low ones.

The rule is **never round further from the truth than staying put would be**: if
a blended colour is nearer to what the destination already showed than to the
entry it would otherwise take, it keeps what was already there. That makes the
composite monotone in the only sense a cell grid can be — nothing changes until
the change is large enough to be represented — and it is why 1% now looks like
1%. Measured across the Layering page's fourth demo: 1% draws nothing, 5%
`005f00`, 10–15% `5f5f00`, 20–30% `5f8700`, 40% `87af00`.

"Already showed", not "already named": a cell with no background of its own is
not transparent to the terminal, it is the surface, which is the same reading
the arithmetic above it uses. Comparing against a `nil` background skipped
exactly the cells the fault was reported on.

Only where the display quantises. A truecolor terminal draws what it is given,
and rounding toward the backdrop there would be discarding a difference it could
have shown.

### 9.8 A composite may not say SGR 49

A blended span is spliced into a row that `FrameDiffWriter.buildLine` opened
with the PAGE's background. Inside that row, SGR 49 does not mean "the page's" —
it means the TERMINAL's, which on Apple Terminal's light profile is white.

The blend's arithmetic already reads a missing background as the surface: that
is exactly what `behind = destination?.background ?? surface` says. The ANSWER
has to say so too. It did not, and the cells it decided for reached the terminal
as `ESC[49m`. Captured on the Layering page with a faded label over a band drawn
in the accent and no background of its own:

```
ESC[45;20H ESC[38;5;83;48;5;22m ▒▒▒▒▒▒▒▒▒▒▒ ESC[49m ▒ ESC[48;5;22m ▒▒▒ ESC[49m ▒ …
```

Every `ESC[49m` there is a column where the label's SPACE yielded to the band —
the destination cell returned verbatim, background and all, and its background
was nothing. Now they read `ESC[48;5;16m`.

Scoped to columns a region actually covers. A span runs from the leftmost to the
rightmost covered column and may pass over uncovered ones on the way; those
belong to a row that was never taken apart, and they reach the terminal
unaltered.

## 9.7 α = 1 is not the identity, and treating it as one was visible

Three separate early returns took a fully opaque region to be a no-op: the
modifier declined to mark the region at all, the resolution filtered such
regions out, and the cell blend returned the source verbatim. Each was written
for the same reason — an untouched subtree should come out untouched — and
together they put the range's only discontinuity at its top.

What a fully opaque composite still does is the background rule: **a cell that
names no background has none to win with, so what is behind it shows.** That
holds at every alpha, 1 included, because a colour that is not there is nothing
to blend. The three returns skipped it, so the plain composite replaced those
cells and the destination's colour under them was gone. Reported from the
Example's Opacity page as text over a coloured field reading correctly at 99%
and gaining a black rectangle at 100% (white on a light terminal — the ambient
surface, which is exactly what the cells fell back to), and as a one-frame
flicker per cycle in a fade breathing between 0.5 and 1: the frame that landed
on the endpoint took the early return.

What DOES snap at 1 is the pane rule, and deliberately. Below 1 a source blank
carrying a background keeps the destination's character and tints only its
field — the veil tints the surface under text, never the text (§6a). An opaque
pane is not a veil, so at 1 it hides what is behind it. The discontinuity is in
the CHARACTER rather than the colour, which is where a cell grid puts every
other one it cannot avoid.

Three cases, one rule each, at α = 1:

| source cell | result |
|---|---|
| anything with a background of its own | the source, outright |
| ink with no background | the source's character and colour, on the destination's background |
| a blank with neither ink nor background | the destination, untouched |

The cost is kept off the common path by asking a better question than the alpha
alone: an opaque region is dropped when **there is nothing behind it**, which is
the case at a root and is where nearly every `.opacity(1)` in an app is
resolved. There the walk would arrive back at the same picture, and the layer is
better left byte-for-byte identical — re-emitting a row to reach the same cells
is repaint volume for nothing. Over a real destination — a `ZStack` sibling, an
`.overlay`, a list row's fill — the region is kept and the walk runs.


## 11. The ink channel's backdrop was the destination's ink (2026-09-09)

`blend` computed both channels as one multiplied blend against the destination:

```swift
let foreground = sourceInk.map { $0.opacity(alpha.layer * alpha.ink, over: destinationInk) }
let background = source.background.map { $0.opacity(alpha.layer * alpha.field, over: destinationField) }
```

The field line is right. The ink line is wrong twice over, and §10.2's reasoning
shows where it went: that section establishes — correctly — that a *layer's* ink
composites over the destination's ink, because a fade over text should read as a
dissolve between two glyphs. It then applied the same backdrop to the *colour's*
alpha, which is a different claim about a different thing.

**A translucent ink is paint on a surface, and the surface is the field.** The
glyph's own layer states one, or it inherits the one it will be drawn on. The
destination's ink is not a candidate: the source glyph won the cell, so the glyph
it displaced is not behind it — nothing is, except the field.

Two consequences, both reachable without any new API:

1. **A layer that paints its own background put its text on the wrong colour.** A
   `Table` row, a `.background()`, any filled panel: the field is right there in
   the same cell, and translucent ink over it faded toward whatever the page
   behind the panel was. Pinned by `inkFadesTowardItsOwnField`.
2. **The bottom of the range was visibly wrong**, which is what makes this a
   correctness fix rather than a preference. "Blend fully toward the destination's
   ink" at `inkOpacity: 0` means *draw an invisible glyph in the colour of the
   letters it hid* — a row of dots wearing the text they replaced. Blending toward
   the field instead lands exactly on the field, which is a terminal's spelling of
   an invisible glyph.

So the ink is resolved in two steps, in compositing's own order — resolve the
layer's pixels, then composite the layer:

```swift
let ownField = source.background ?? destinationField
let inkWithinLayer = sourceInk.map { $0.opacity(alpha.ink, over: ownField) }
let foreground = inkWithinLayer.map { $0.opacity(alpha.layer, over: destinationInk) }
```

Nothing moves where `inkOpacity == 1`, which is every cell in the framework that
does not carry a translucent foreground — so the change is narrow by
construction. Three tests on this branch had pinned the old answer and were
rewritten rather than adapted: they asserted the ink blending toward `.red`, the
displaced glyph, in the two places that most looked like the model working.


## 12. A transparent ink keeps its glyph (2026-09-09)

`sourcePaintsInk` was gated on `alpha.ink > 0`, so `inkOpacity: 0` removed the
source's glyph from the cell contest and the destination's character survived.
The project owner's argument overturns it, and it turns on what a cell is:

> painting with a 0% opacity foreground colour should still emit the actual
> character (if any) in the cell. That way copy-paste still works. If the goal
> were to *remove* the text from rendering, then its visibility should be
> disabled outright in any of numerous other ways — painting in a transparent
> colour is not the same thing.

A cell's character is the SELECTABLE text. Drop the glyph and the cell holds
whatever a sibling drew, so a transparent label is copied out of the terminal as
the text it covers — the one outcome nobody asked for. Three things make the new
rule the right one rather than merely the requested one:

1. **It is the same colour.** In a cell grid, ink at alpha 0 over a field is
   indistinguishable from ink painted in the field's exact colour, and nobody
   expects `.foregroundColor(.black)` on a black field to reveal text behind it.
   `clearInkIsTheFieldsColour` pins that: four different named inks at alpha 0
   all emit the field's own codes.
2. **It is continuous.** §11's blend lands exactly on the field as `inkOpacity`
   reaches 0, so nothing snaps at the end of the range. The old gate was a
   discontinuity — a glyph at 0.01 and no glyph at 0.
3. **The alternatives already exist and say what they mean.** `.hidden()`,
   `.opacity(0)` and not drawing the view remove it from the picture. A colour is
   a colour.

`.opacity(0)` on a VIEW is deliberately NOT the same, and the difference is the
½ rule rather than a special case: below ½ a layer already loses the glyph
contest, so a layer at 0 handing the cell to the destination is the continuous
answer *there*. The ink channel has no contest at all — it is one cell's own
glyph on its own field — so keeping the glyph is the continuous answer for it.
Two channels, two limits, one rule each.


## 13. First match wins dropped one of two claims (2026-09-09)

`resolvingOpacity`'s per-cell lookup was `covering.first { $0.contains(...) }`.
That is right for the LAYER channel and wrong for the other two, and the split is
not a compromise — the two kinds of claim arrive differently.

A layer's alpha **nests**, and `OpacityFade.fading` has already done that
arithmetic before the resolver ever sees it: it scales its factor into every
region it carries up, then appends its own rectangle, so the innermost region
covering a cell already holds the product of every `.opacity` outside it.
Multiplying those again at lookup would count each one twice. And it could not
move into the lookup even if that were free: a CYCLING region carries a list of
phases, and two cycles of different lengths have no common phase index to
multiply at. Pre-multiplying a scalar into the inner cycle is exactly what makes
"a breathing badge inside a fading panel" expressible at all.

A colour's alpha does not nest, and `fading` never touches it. So two independent
claims on one cell lost one of them, reachable in a single line:

```swift
Text("hi").foregroundStyle(.green.opacity(0.4)).background(.red.opacity(0.4))
```

`Text` stamps `(ink 0.4)` per line and `.background` appends `(field 0.4)` over
the same cells. The text's region came first and won, so the background rendered
at **full strength under the letters and correctly past the end of the line** —
which on ragged wrapped text is a visible two-tone block. Ink and field are now
multiplied across every covering region; the layer still takes the first.

### 13.1 …which then exposed the ink's backdrop being unresolved

With both claims applying, §11's `ownField` was wrong in a way that could not
occur while one of them was being dropped. It used the field **as painted** —
full red — so the glyph was drawn 40% of the way toward a colour its own cell
does not end up having, while sitting on a background that is 40% red.

The field is therefore resolved first, at its own alpha, and the ink blends over
*that*:

```swift
let fieldWithinLayer = source.background.map { $0.opacity(alpha.field, over: destinationField) }
let ownField         = fieldWithinLayer ?? destinationField
let inkWithinLayer   = sourceInk.map { $0.opacity(alpha.ink, over: ownField) }
```

The field's own output takes the second blend from the same value rather than
recomputing the product, which lands on precisely the number one multiplied blend
gave — the identity in §11 — while keeping one definition of "the surface this
layer's glyphs sit on". Two definitions of that is how the two channels drift.


## 14. An attributed run was rectangular all along (2026-09-09)

`Text.colourAlphaRegions` opened with `guard runs == nil, ramp == nil`, and the
comment gave one reason for both: "a CONCATENATION carries a style per fragment
and a RAMP a colour per cell, and both need a claim finer than a rectangle."

That is true of the ramp and false of the fragments. A fragment occupies a
**contiguous column range of one line**, so a height-1 rectangle per fragment
says exactly what is true. The two arms were declined together because they are
adjacent in the code, not because they share a difficulty.

The visible cost of the conflation: a concatenation whose fragments all take one
translucent colour is the uniform case the plain arm already handled, and was
refused anyway. So adding `+ Text("")` to a working translucent `Text` silently
made it opaque — pinned now by `uniformConcatenationIsNotRefused`.

Three things the implementation needed that the shape did not suggest:

- **Cells, not characters.** A fragment's start column accumulates
  `strippedLength`, not `count`. `Text("日本") + Text("ab").foregroundStyle(faint)`
  puts the claim at column 4; counting characters puts it at 2, which fades the
  wrong two cells and leaves the last one bright.
- **Rows come from the same interleave the lines do.** Line spacing is
  interleaved last, so claims are built in LINE indices and rowed through
  `LineSpacingRows.interleaved(_:spacing:blank: [])` — the same call the lines and
  the widths take. Three parallel arrays have to agree about which row is which,
  and the one derived a different way is the one that drifts.
- **Adjacent equal claims coalesce.** A concatenation is usually a handful of
  fragments differing in weight rather than in translucency, so the common case
  collapses back to one region per line. The resolver walks every region covering
  a row, per cell, so this is the difference between one region and one per
  fragment on ordinary text.

The ramp arm is still declined, and deliberately still **loud**: its run styles go
to `PaintRenderer` as they are rather than in their opaque spelling, so a
translucent colour there still trips the emitter's assertion. Spelling it opaque
would have quietly discarded the alpha, which is the failure mode the assertion
exists to prevent.


## 15. A translucent gradient, and the two thirds of one that is rectangular (2026-09-09)

The design records a ramp as "the one case where a rectangle is genuinely the
wrong shape". That is true of one geometry out of four, and stating it precisely
shrinks the problem by most of its size. Alpha at a cell is
`sampler.ramp[entry].alpha`, so:

| the ramp | its alpha | the claim |
|----------|-----------|-----------|
| all stops share one alpha | constant | ONE rectangle over the block |
| vertical linear (`variesAcrossRow == false`) | one per row | one rectangle per row |
| horizontal / radial / angular / elliptical, stops disagreeing | per cell | **not expressible** |

`RampSampler.alphaShape` returns which, and the two expressible shapes cover what
is actually asked for: an evenly faded ramp, and *a scrim* — a list fading out at
the bottom, which is a vertical linear ramp to `.clear`. `Color.lerp` interpolates
alpha as a fourth channel, so the uniform case falls out of equal endpoints
rather than needing to be special-cased.

### 15.1 The gap was distributed by terminal, which is worse than being large

`BackgroundModifier` has two ways to draw a ramp. On a terminal that draws
pictures it rasterises one; otherwise it paints cells. `GradientRaster.picture`
sends `rgbComponents` in an `.rgb` format — **there is no alpha in it** — so the
picture path rendered a translucent ramp at full strength with no diagnostic,
while the cell path trips the emitter's assertion for the same gradient.

So which failure a developer met depended on their terminal: quietly wrong on
kitty and Ghostty, loudly unsupported on Apple Terminal. Someone developing on
Ghostty could write `Gradient(colors: [.red, .clear])`, see a solid red-to-black
ramp, hit no assertion, and ship it.

A translucent ramp now declines the picture path outright (`Paint`
`.isOpaqueThroughout`, asked of the STOPS, before any sampling). Transmitting real
RGBA would not fix it even where the protocol allows: the terminal composites
against the cells' own background rather than against what TUIkit knows is behind
them, which is the guess this design exists to avoid. The cost is sub-cell
smoothness, for translucent ramps only.

### 15.2 Opaque only where the alpha is carried

The paint sites spell a colour `opaqueSpelling` **only** when a claim is being
emitted for it. Spelling it opaque everywhere would silence the assertion for the
`perCell` case — converting a loud gap into a discarded alpha, which is the one
failure mode the assertion exists to prevent. `Text`'s ramp arm is unchanged and
unhonoured for the same reason.

Still open: `perCell` ramps, which want the per-column payload sketched in §9.1's
successor discussion, and `Text`'s ramped ink.


## 16. What honours `Color` alpha, and what does not (2026-09-09)

### 16.1 A correction: "only three sites write translucency" was the wrong count

The summary above argues that §1's estimate — 169 emit sites needing column
knowledge — priced a mechanism nobody needed, because translucency is only
*written* at three sites, all of which already know their rectangle.

The premise is true and the conclusion does not follow. Translucency is
**authored** at a few sites; it is **carried by `Color`**, and a `Color` flows
wherever the environment and the palette take it. So the set of paths that must
*honour* alpha is not the set that authors it — it is every path that paints a
colour a user could have faded. A sweep of every `Color` → bytes conversion found
**twelve public entry points** one modifier away from an unhonoured path, none of
them among the three:

| entry point | reaches |
|---|---|
| `.border(.red.opacity(0.5))` | `BorderRenderer`, 15 emit sites — **fixed, §18** |
| `.foregroundStyle(…opacity(…))` on anything but a plain `Text` | `Divider` and `Spinner` — **fixed, §19**; `RadioButton` and `_ToggleCore`'s indicators — **fixed, §23**; `Table` and `_ListCore` — **fixed, §33**; `PaintRenderer`'s flat arm — **fixed, §34.1** |
| `.tint(…opacity(…))` | `TintedPalette.accent`, and from there dozens of controls — **fixed, §21**; it was inconsistent, `restingControlFace` consuming the alpha while `accentPulse` carried it |
| `String.styled(foreground:…)` | the documented escape hatch for a reader's own `Renderable` — **answered, §26.1** |
| `.listRowBackground(…)` | one site — **fixed, §22** |
| `Text` concatenation | **fixed, §14** |
| translucent gradient stops | **background fixed, §15**, and its horizontal case, misclassified as per-cell — **fixed, §34.2**; `Text`'s ramped ink — **fixed, §34.1**; the shape that varies in both directions, and `Text`'s concatenated arm under a ramp — **fixed, §36.2 and §36.5** |
| `TrackConfiguration(emptyColor:)` (now `backgroundColor:`), `SegmentColoring` | `TrackRenderer` — nineteen sites, not three — plus `Slider`, `Gauge` and `ProgressView`: **fixed, §31**; the indeterminate sweep — **fixed, §36.7** |
| `StatusBarState.highlightColor` / `.labelColor` | 2 sites — **fixed, §24** |
| `.style(.text) { $0.foreground = … }` | the cascade's six non-`Text` readers — **fixed, §30** |
| `.colorMultiply(…)` | a silent drop, not a trap — **fixed, §25** |
| `ColorPicker` with a translucent binding | the swatch was **already right, §26**; `supportsOpacity` — **built, §32** |

Plus a whole second tier: `Palette` is a public protocol of plain
`var …: Color { get }` members, and nothing normalises what a custom palette
returns. One `.clear` in a palette reaches everything. (§18 closes the `border`
role of it — every box the framework draws. §20 fixed the reason it reached
*nothing*: `resolve(with:)` was discarding a slot's alpha outright. §28 then sorted
every derived palette colour into the three things they were doing with a faded slot,
and fixed the one that was doing none of them.)

And one more entry point, found while finishing the track and added here so that
finishing `TrackRenderer` is not mistaken for finishing the control: the **circular
`Gauge`** paints its own cells and bypasses the track renderer entirely
(`renderCircularTiny`, `renderCircularDial`), so a translucent `.tint` reaches four
further emit sites. **Fixed, §36.6.**

**All thirteen are closed.** What remains unhonoured anywhere is the image glyph path
(§17), which is not one of these entry points but a module of its own, and the four
`Palette` surface derivations of §28.2 — a question rather than a gap (§37).

So §1's instinct about the *magnitude* was better than the summary's dismissal of
it. What the summary got right is the *shape*: none of this needs per-column alpha
in the general case, and a rectangle per drawn run is enough for almost all of it.
What it got wrong is how many places have to draw that rectangle.

### 16.2 The emitter's answer, now that it is a policy rather than a stopgap

`foregroundCodes` / `backgroundCodes` cannot composite — they have no backdrop —
so they answer in two ways rather than one:

- **alpha 0 → no SGR parameters at all.** An answer, not a degradation: the cell
  keeps the colour it had, which is what transparent means, near enough, for the
  one case where "near enough" exists without a backdrop. Checked *before* the
  assertion, because `.clear` is public API and a reader writing it deserves the
  sensible result on every path. Without it the answer was this colour at full
  strength — and `.clear`'s underlying value is black, so `.border(.clear)` drew a
  solid black box in a release build, where the assertion is compiled out.
- **partial alpha → full strength, and an assertion in debug.** There is no answer
  available, so this is a gap marker. It names the framework's own diagnosis and
  points here rather than naming a `package` function the reader cannot find.

### 16.3 Honoured as of this branch

`Color` as a view; `.background` with a flat colour; `.background` with a ramp
whose alpha is uniform or varies only down the page — **or, from §34.2, only along
one**; `Text`'s single-style arm;
`Text`'s attributed-run arm; `.opacity(_:)` on a view (all three channels);
`ShapeStyle.opacity(_:)` and `Color.opacity(_:)`, which now agree; `.border` and
every box the framework draws through `BorderRenderer` (§18); `Divider` and
`Spinner` (§19); a `Toggle`'s and `RadioButton`'s own indicator glyphs (§23);
`.listRowBackground` (§22); the status bar's two configurable colours (§24);
`.colorMultiply` (§25).

Plus, from 2026-09-10: the style cascade's six control readers (§30); `Table`'s and
`List`'s rows (§33); the whole determinate track family — `TrackConfiguration`,
`SegmentColoring`, `Slider`, `Gauge`, `ProgressView` (§31); `ColorPicker`'s fourth
channel (§32); `Text`'s ramped ink at every rectangular alpha shape, and a horizontal
ramp's `.background`, which had been misclassified as per-cell (§34).

And, from §36: a ramp whose alpha varies in BOTH directions — radial, angular,
elliptical, diagonal — as ink and as a fill; a `Table` under one; `Text`'s
concatenated-run arm under a ramp, and each fragment's own colour there; and a
one-stop gradient's representative.

Plus the circular `Gauge`'s four emit sites (§36.6).

Plus the indeterminate `ProgressView` sweep (§36.7), by declining the RUN rather
than the alpha.

Plus the image glyph path (§42), thought at the time to be the last of them (§70.2 found
the mono post-pass behind it), and the four `Palette`
surface derivations, which now carry (§39).

Plus the scrollbars: every host's track, thumb, arrows and corner, and the focused
bar's breath (§43–§45). Plus the navigation bar's crumbs, at rest and breathing (§47).
Plus a colour swatch's focused bullet, on any fill under any palette (§48). Plus a
hovered button's face under a fully faded tint (§49). Plus the text scroll indicators,
still and breathing, on every host that draws them (§53). Plus a `TabView`'s active chip,
breathing, in both strips (§55), and the bordered strip's own chrome — its tops, walls,
mouth, pads, fillers and rules (§56). Plus a focused `Toggle`'s bracketed mark and knob
(§57), and a focused switch's coloured track (§58). Plus an animated `.border` whose frames
share one alpha (§59). Plus a `TextEditor`'s rows, its blank rows and its caret's ink
(§61). Plus a resizable view's grips, at rest and breathing (§62). Plus a split view
divider's grip dots and pulsing field (§63). Plus a drop-down menu's breathing border
(§64). Plus a plain container's title and footer rule (§65).

Declined deliberately: `.opacity(_:)` on an `Image`'s PIXEL path (§17).

Still open: an animated `.border` whose frames are at several alphas, which drops its
alpha without a word (§59.2); and the field under a text caret, which both carets drop
while they blink over a faded well (§61.2).


## 17. Images: what is already right, and why the glyph path is a bigger piece (2026-09-09)

An image is the one thing here with **real per-pixel alpha** already, decoded and
carried. Straight (un-premultiplied) from `ImageLoader.straightAlphaPixels`, and
all three resamplers carry it. The two renderers then do opposite things with it.

**The pixel path is already correct.** Alpha survives the tone curve, sharpening,
Floyd–Steinberg, quantisation and the mono recolouring, and is transmitted as
`f=32` — real RGBA. Nothing to do.

**The glyph path composites over BLACK,** unconditionally, in
`flattenedOverBlack()`. With the default `.blocks(.fine)`, which paints a
background in every cell, a logo with a transparent surround renders as an explicit
black rectangle: invisible on a dark theme, glaring on a light one.

That is exactly the hack the project owner ruled out — "no hacks (assuming a black
background or any particular colour otherwise — use the *actual* colour behind the
cell at composition time)". So the obvious cheap fix, passing `palette.background`
instead of black, is **declined**: it is a different guess, not the removal of one.
It would be right for an image on the page's own background and wrong over a
`ZStack` sibling, which is where the current answer is already wrong.

Honouring it properly means per-cell alpha, and the shape is tractable — an image's
alpha is mostly large uniform areas, so run-length coalescing per row (the same
coalescing `Text`'s fragments use in §14) collapses a logo to two or three claims a
row. What makes it a bigger piece than the ramp work is what it drags with it:

1. **`ASCIIConverter.convert`'s return type is public API** in a public module, and
   it would have to carry an alpha map beside the lines.
2. **The half-block coalescing gains an alpha term.** Two same-coloured pixels with
   different alpha must stop collapsing to a space — and that optimisation is
   load-bearing for the Warp contrast-lift banding, so it cannot simply go.
3. **`boxReduced(by:)` averages straight-alpha colour and alpha independently, with
   no premultiply.** Benign today only because its one production caller runs it
   *after* the flatten. Stop flattening and every supersampled soft edge gains a
   halo of the transparent pixels' (0,0,0).
4. **Floyd–Steinberg diffuses RGB error out of fully transparent pixels**, whose
   straight colour is (0,0,0), into their visible neighbours. Alpha is preserved but
   the error is not alpha-weighted, so a hard alpha edge seeds a dark fringe.

(3) and (4) are pre-existing bugs that the flatten currently hides. They have to be
fixed *first*, and each is worth its own commit and its own test.

Meanwhile `.opacity(_:)` on an `Image` behaves differently per path — the glyph
path fades, the pixel path declines, because fading a real picture means
re-transmitting up to megabytes per phase. `OpacityResolution` declines it
deliberately and should keep declining it.

What this branch did do for the module: `ASCIIPalette.init` normalises its colours
to their opaque spelling in one place. The module spells SGR itself for a measured
reason, so the emitters' assertion does not cover it and a translucent palette
entry was being discarded with no diagnostic anywhere. Discarding it is right — a
palette entry is a candidate in a nearest-colour match and transparency is not an
axis of one — but it is now a line of code rather than an omission, and `colors`
and `entries` cannot disagree about it.


## 18. `.border`, and the boxes the framework draws (2026-09-09)

`.border(_:)` is the entry point with the most emit sites behind it, and the one
whose claim is not a rectangle. It is also the one that was *loudest* when wrong:
`.border(.clear)` drew a solid black box in a release build, because `.clear`'s
underlying value is black and the emitter's assertion compiles out. §16.2 fixed
the byte half of that. This is the other half.

### 18.1 A frame, not a rectangle

A box's translucency belongs to its **walls**. One region over the box's full
extent would fade the content the border was drawn around — which no colour asked
for, and which is visibly wrong the moment anything is inside it. So the claim is
the top band, the bottom row, and the two wall columns between:

```
╭──────────╮   ← claimed
│          │   ← claimed at columns 0 and 11 only
╰──────────╯   ← claimed
```

**Every cell is claimed exactly once**, and that is a correctness requirement
rather than an economy. Overlapping claims MULTIPLY at the resolver — that is what
`OpacityResolution`'s fold does, and it has to, because two independent fades over
one cell compose by multiplication. So a divider row taking the full width *on top
of* the wall columns would square the alpha at its two end cells: a pair of darker
pips down the side of the box, at exactly the rows a footer separator sits on. The
divider therefore claims only the columns between the walls. Likewise a box one
row or one column across, whose bands coincide, claims that row or column once.
`BorderAlphaTests.noDoubleClaims` sweeps the seven shapes that invite it.

### 18.2 The title and the focus dot are their own ink

They sit IN the band — an opaque border with an unpainted title cell reads as a
broken one — so their cells take the border's FIELD and their own INK. Emitting
them as their own spans is what makes both common shapes come out right, and
neither is the shape a single whole-row claim would give:

| border | title | what happens |
|---|---|---|
| faded | opaque | the band fades, the letters stay |
| opaque | faded | only the letters fade |
| faded | faded | each at its own alpha |

The title's span is computed from `BorderRenderer.fittedTitle`, which is the same
call the band draws through — extracted for exactly that reason. Computed from the
*untruncated* title instead, a narrow box's claim would fade cells the title never
reached, and run past the far corner into cells the box does not have.

### 18.3 Why the bytes are funnelled

`BorderRenderer.band` is now the only place this type emits an SGR run, and it
states the colour's `opaqueSpelling`. Thirteen sites had written
`colorize(_, foreground: color, background: fill(style, color))` by hand, and the
pairing — opaque bytes, alpha in a region — is a rule about the *type*, not about a
call site. A new drawing function reaching for `ANSIRenderer.colorize` directly
would hand the emitter a translucent colour and trip its assertion; going through
`band` it cannot.

The consequence is that every caller of `BorderRenderer` had to gain a claim in
the same commit, or its alpha would go from *loudly* dropped to *silently*
dropped. That is why this commit touches the tooltip panel, the status bar, the
app header and the drop-down menu as well: all four draw their chrome from
`palette.border`, so they are reachable by the second tier of §16.1 — a custom
`Palette` returning a faded colour.

### 18.4 What is still not honoured here

**An animating border colour.** `.border(emphasis.animatedColor(…))` repaints the
frame's cells from its own frames every tick, and a region carrying the phase drawn
*now* would resolve every later phase at the wrong alpha — where the phases differ in
alpha. The claim was therefore made only for a still colour, and the animating arm was
said to stay loud. It did not: §18.3 put every frame through `band` at its opaque
spelling, so the arm dropped the alpha in silence. Half closed in §59: a border whose frames
share one alpha claims it and keeps its runs; one whose frames do not is still unclaimed
(§59.2). The drop-down menu was in the same position, and its
border pair disagreed besides; both of its ends are spent since §64, so it claims in
either arm.

**`focusIndicatorPrefix`.** It draws a `●` outside any band, so it has no frame to
belong to and its caller (`ButtonStyle`) would have to claim the cell. Untouched
and still loud.

**The contrast floor asks the wrong question of a faded band.** `legible(_:on:_:)`
floors a title against the border colour, so that a title on an opaque band stays
readable against the band rather than against the page. On a *translucent* band the
thing the title is really read against is the blend, which is not known at emit
time — structurally the same gap the emitters have, and it resolves the same way or
not at all. Noted rather than fixed: the floor's answer is at worst conservative,
and a wrong floor is a legibility question rather than a wrong colour.


## 19. The leaves that paint their own glyph (2026-09-09)

`.foregroundStyle(_:)` is honoured on a `Text` (§14) and was honoured nowhere
else. The views that read `EnvironmentValues.foregroundStyle` directly and paint
with it — rather than handing it to a `Text` — are `Divider`, `Spinner` and
`Table`. The first two are here; `Table` is not, for the reason below.

Both are the simplest shape this design has: **one run of one colour**, so the
claim is one rectangle over exactly the cells just drawn. What is worth writing
down is the two places even that is not quite trivial.

**A spinner's label is a second claim.** It is drawn in `palette.foreground`, not
in the spinner's colour, so one region over the whole row would fade it at the
wrong alpha. Two paints, two rectangles.

**A spinner's claim has to hold for frames that are not on screen yet.** The glyph
is an `AnimatedCellRun`: the run loop splices later frames over these cells without
asking the view anything, so a region describing only the frame drawn *now* would
be wrong from the first tick. It is valid here because every frame of a cycle is
the *same colour* and only the glyph changes — which is exactly why `.bouncing` is
excluded. Its trail lerps a different colour into every cell of every frame, so no
rectangle can say what is true.

It used to stay unhonoured **and loud**, on the argument that the emitter's assertion
firing beats a wrong colour appearing silently. It fired — on the example's own page,
under a faded palette (§68.6) — so it SPENDS instead: both ends of the ramp are
composited against the page before the lerp, which is §29's remedy for a pair that
cannot agree about alpha, and is what the track colour beside it was already doing.
Per-cell claims stay declined; spending is what replaced the trap, not them.
`ForegroundStyleAlphaTests.bouncingSpinnerSpends` pins the colour.

### 19.1 Why `Table` is not here

Not for want of a rectangle — a table row's cells are one colour per row, which is
the same shape `Divider` has. It is the plumbing:

1. `RenderedRow` carries `lines` and `pulseFrames` and no side payload at all, so
   the claim needs a new field threaded through three row renderers plus the
   header and footer.
2. **A pulsing cursor row replaces its own lines per step**, exactly like the
   animating border of §18.4 and the bouncing spinner above — so the row that is
   most likely to be looked at is the one arm a rectangle cannot describe.
3. `PaintRenderer.band`'s per-cell arm is the `perCell` ramp case that is still
   declined framework-wide, and a table with a horizontal ramp goes through it.

(1) is mechanical, (2) wants the phase-indexed alpha `OpacityCycle` already
provides for layer fades, and (3) is the open item from §15. They are one commit
each, and the honest order is (2) first: without it, a translucent
`.foregroundStyle` on a table would be right on every row except the selected one.


## 20. A theme's own translucency was discarded on the way out (2026-09-09)

§16.1's second tier turned out to have a bug under it rather than merely a gap.
`Color.resolve(with:)` ended every arm with `carryingAlpha(of: self)` — the
*reference's* alpha, substituted for whatever the palette slot had. So a theme
whose `accent` was `.cyan.opacity(0.5)` resolved to cyan at **full strength**: the
translucency was not unhonoured, it was deleted, and the assertion that would have
reported it never fired because an opaque colour is a perfectly legal thing to
emit.

### 20.1 Substituting versus composing

`carryingAlpha(of:)` is right for a **re-spelling** — a downsample, a contrast
floor, a monotonicity repair. There the result is the same colour written
differently, only ever one alpha is in play, and composing would fade a colour
twice for having been quantised.

Resolving a semantic colour is not a re-spelling. `.palette.accent` and the theme's
`accent` slot are two *different colours*, each entitled to its own alpha, and the
paint is subject to both. So `composingAlpha(of:)` — the multiplying sibling, and
the same rule `Color.opacity(_:)` follows for the same reason:

```
.palette.accent                  on accent = cyan@0.5  →  0.5
.palette.accent.opacity(0.5)     on accent = cyan@0.5  →  0.25
```

Composed at **every hop**, because a slot may itself hold a semantic reference (a
palette editor setting `accent` to `.semantic(.success)`), so a chain through two
faded slots fades twice. The accumulator is `resolved` itself, which starts as
`self` — that way the reference's own alpha is in it from the outset and the exits
need no further arithmetic. The first version of this fix composed `self` again at
the exit, which ran for the *non-semantic* case too and **squared** it: 128 became
64 for a colour that had never been near a palette. `concreteIsUntouched` is that
bug's test.

The cyclic-reference fallback keeps the accumulated alpha rather than dropping it,
so a faded cyclic reference stays faded instead of turning solid.

The integer arithmetic has to round: 255 × 128 / 255 must give 128 back, or every
hop through an *opaque* slot would fade a colour slightly, and the framework
resolves semantic colours several times per frame. `opaqueSlotIsExact` pins it.

### 20.2 What this changes for an app

Nothing, for any app whose palette is opaque — which is every palette that ships,
and why the suite is unchanged at 6,469 passing. For an app that *does* fade a
slot, a silent drop becomes a loud one on the paths that have not been migrated:
the colour now arrives at the emitter with its alpha intact and trips the assertion
in `Color+ANSICodes.swift`. That is the intended direction. A theme cannot be
partly honoured quietly.


## 21. `.tint`, and the two answers one derivation gave (2026-09-09)

`.tint(_:)` writes `TintedPalette.accent`, and the accent fans out to dozens of
controls. §16.1 recorded the fan-out as *inconsistent* rather than merely
unhonoured, and that is the interesting part: two derivations of the same accent
disagreed about what a translucent one meant.

```swift
// before
restingControlFace  →  accent.opacity(focusBorderDim, over: background)   // opaque
accentPulse().dim   →  accent.opacity(focusPulseMin,  over: ground)       // opaque
accentPulse().bright →  accent                                            // translucent
```

So a focused control breathing between those two ends was honoured for half its
cycle and a debug trap for the other half — and `restingControlFace` was the
*silent* half of the same bug: `opacity(_:over:)` read only its parameter and
ignored the source's own alpha, then stamped the result opaque. A faded tint gave
the identical face an opaque one gave, with no diagnostic anywhere, because an
opaque colour is a legal thing to emit.

### 21.1 Consuming an alpha is right *here*

`opacity(_:over:)` composites over a surface the caller has **stated**, so it has
the one thing an emitter lacks: something to blend against. It is therefore
allowed to spend the alpha completely and answer with a concrete colour. That is
not the forbidden "assume a particular colour" hack — the surface is a parameter,
and `accentPulse(over:)` exists precisely so a mark drawn on a filled row names
the row rather than the page.

What it was doing wrong was spending only *part* of it. The source's own alpha is
part of the coverage, not something separate from it, so:

```
coverage = self.alpha/255 × opacity
```

Exact for the overwhelming case, an opaque source multiplying by 1.

### 21.2 The opaque accent keeps its *spelling*, not just its colour

`accentPulse().bright` is now `accent.isOpaque ? accent : accent.opacity(1, over:)`,
and the guard is load-bearing rather than an economy. `opacity(_:over:)` goes
through `lerp`, and a lerp re-spells `.red` — `ANSIColor.red`, SGR 31, *the
terminal's own red* — as `rgb(205, 0, 0)`, SGR 38;2;205;0;0. The same colour by
arithmetic and a different colour on any terminal whose palette is not the default,
which is most of them (see `Documentation/Terminal-compatibility.md` and the
"bold is a colour" findings). This is the bright end of every focus pulse on every
palette that ships, so compositing it unconditionally would have changed what
sixteen themes actually look like in order to fix a case none of them have.

`opaqueTintUnchanged` asserts the *spelling*, not the colour, for that reason.


## 22. `.listRowBackground`: a fill that is not a backdrop yet (2026-09-09)

One site, and the only entry point so far whose fix changed *when* something
resolves rather than merely adding a claim.

`_ListRowColorView` painted the row and then called `compositedResolvingOpacity`,
which resolves the content's own opacity regions **against the fill**. For an
opaque fill that is exactly right, and it is the point: `Text("x").opacity(0.5)` in
a red row must fade toward the red, not toward the page. A fill is a backdrop, so
the fade is spent there and nothing travels further.

A **translucent** fill is not a backdrop. Resolving the content against it would
blend the text toward the fill's `opaqueSpelling` — the colour the fill is written
in, not the colour it is going to *be* once it has itself resolved against whatever
is behind the row. So the two branches now differ:

| fill | content's fade |
|---|---|
| opaque | spent against the fill, here |
| translucent | carried up, to resolve alongside the fill's own claim |

Carrying both is not a compromise; it is the arithmetic the blend already
implements. `OpacityBlend` takes a cell's FIELD first, within its own layer, and
then its INK against that field — which is precisely a field claim and an ink claim
stacked on one cell. Two channels, folded separately, in the right order.

### 22.1 The claim goes on *after* the composite

`composited(with:at:)` punches the destination's regions by the overlay's
footprint, and it must: a claim over cells the overlay *replaced* would fade content
that was never under the fade. But a row's text is not a replacement — it sits ON
the fill, and those cells still show it, because a cell that states no background of
its own inherits the one beneath.

So a claim added before the composite comes back with a hole in it exactly the width
of the words: the row would render **opaque under its own text and faded either side
of it**. Appending after the composite is what avoids that, and
`claimSurvivesTheComposite` is the test that would catch it being moved.


## 23. A control's own indicator, and four sites that took half an answer (2026-09-09)

A checkbox's mark, a switch's knob, a radio button's dot: glyphs a control paints
for itself, from the *palette* rather than from `.foregroundStyle`. So what reaches
them is a faded `.tint`, and §21's fix is what lets it arrive at all.

### 23.1 Half a pulse, spelled four times

`accentPulse()` and `accentFillPulse()` each return a **pair**. Four sites took the
`dim` of one and then wrote their own bright end:

```swift
// MenuItemButtonStyle, DropdownMenuRenderer
dim:    palette.accentPulse().dim
bright: palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background)
        // …which is exactly accentFillPulse().bright

// RadioButton, _ToggleCore
dim:    palette.accentPulse().dim
bright: palette.accent
        // …which is exactly what §21 had just stopped being right
```

Both hand-rolled pairs are the existing functions written out, so this is a
consolidation that happens to fix a bug: written apart, the two ends disagreed about
a translucent accent — the dim end spent its alpha and the bright end carried it.
The `_ToggleCore` and `RadioButton` pairs were the *same* inconsistency §21 removed
from `accentPulse`, reintroduced locally, which is what a pair-returning function
exists to prevent.

The distinction between the two functions is real and worth keeping straight: a
**fill** with a label on it stops at `focusPulseMax` so the content stays readable,
while a **mark** drawn in the accent has nothing on top of it and can go all the
way. The menu bar and the drop-down highlight are fills; a checkbox's brackets are a
mark.

### 23.2 Describing the runs once

An indicator is two or three differently-coloured runs on one row, and the strings
were built by concatenating `colorize` calls. That is fine for bytes and useless for
a claim, which needs a **column** — and the column cannot be hardcoded: a `⬛︎` is two
cells wide, a `[` is one, so an offset guessed at is wrong under two
`ToggleCharacterSet`s out of three.

So `IndicatorRun` — `(text, ink, field)` — and one function per style that describes
the runs at a given colour. `painted(_:)` makes the bytes (stating each colour's
opaque spelling) and `claims(_:)` walks the same list accumulating `strippedLength`.
Two consumers, one description; they cannot drift.

The blank half of a switch's ASCII track is described as a run even though it is a
space. No ink lands on a space, so its claim changes nothing — but *omitting* it
would put the closing bracket's claim one cell to the left.

A pulsing indicator claims too: a bracketed one since §57, a coloured switch track since
§58. Only the breathing colour moves, between two spent ends, so the claim taken at the
drawn phase is every frame's.


## 24. The status bar's two colours, and the sink that was already right (2026-09-09)

`StatusBarState.highlightColor` and `.labelColor` are public `var`s an app sets, and
each paints a *different run of every item*: the shortcut key and the label. So one
claim over the bar's row would fade one of them at the other's alpha. Two runs per
item, claimed separately.

Per **item**, not per bar, because the alignment spreads them: `.justified` puts the
system items at the far end. The columns come from the same `placedColumns` the hit
regions use, and for the same reason — only the alignment knows where an item ended
up, and a claim derived from the item widths alone is wrong the moment the bar is not
left-packed.

The two runs are adjacent and disjoint by construction: the shortcut is
`shortcut.strippedLength` cells and the label takes the rest of `visibleWidth`,
*including the separating space*. Splitting it any other way leaves a cell belonging
to nobody, or — worse — to both, which would resolve it at the product of the two
alphas.

All three bar styles now go through one `finished(buffer:…)` rather than each calling
`applyHitTestRegions` directly. Not tidiness: a style added later must not be able to
remember the hit regions and forget the claims. That exact omission happened twice to
the app header's side payloads. The tooltip row the bar grew later is claimed there too,
for the same reason — but only since §73.

### 24.1 The sink was built before there was anything to put in it

`RenderLoop` already resolved the status bar buffer against
`palette.statusBarBackground` rather than `palette.background`, with a comment saying
a faded item in the bar must fade toward *the bar*. It was written before anything
emitted a region there — "it is the sink being put in place first". It was right, and
this is the first thing to use it. The comment now says so.


## 25. `.colorMultiply`, where the alpha is a *layer* (2026-09-09)

`colorMultiply` multiplies **RGBA**, in SwiftUI and here, so a tint's own alpha is
not decoration on the operation — it halves the alpha of everything under the
modifier. §16.1 called this "a silent drop, not a trap", and it was: the arithmetic
rebuilt every colour as `Color.rgb(...)`, so the tint's alpha simply never appeared
anywhere.

The RGB half is arithmetic on the escapes. The alpha half cannot be, because a
colour's alpha is not *in* the escapes — so it becomes a region, and specifically a
**layer** region:

- The layer channel says how *present* the subtree is, so a cell at 0.4 hands its
  glyph to whatever is behind it by the ½ rule, and `.colorMultiply(.clear)` hides
  the subtree rather than painting it in the page's colour.
- On ink and field instead, a fully transparent multiply would still draw its
  glyphs — and `.opacity(x)` would mean something different from
  `.colorMultiply(.white.opacity(x))`, which in SwiftUI it does not.

### 25.1 `.white` is the identity by spelling, not by arithmetic

Worth knowing before touching this. `Color.white` is **ANSI white — 229, not 255** —
so putting it through the multiply darkens everything by 229/255. What makes
`.colorMultiply(.white)` mean what it says is the `isIdentity` shortcut, which
compares the colour and skips the pass entirely.

A faded white slipped past that check (`.white.opacity(0.5) != .white`), so it took
the arithmetic path and **darkened the subtree as a side effect of fading it**. The
check now asks `color.opaqueSpelling == .white`, and the two halves are separated: the
line rewrite runs only when the hues actually change, the layer fade is appended
independently, and either can happen without the other.

That is also why the test asserts the *bytes* are byte-identical to an unmultiplied
render. It is how the bug was found rather than a restatement of the fix.

### 25.2 A tint nests, and that is a question of order (2026-09-12)

The tint's layer region was appended bare, after whatever the content had already
claimed. The resolution takes the LAYER from the **first** region covering a cell and
multiplies only ink and field across the rest (`foldedAlphas`) — which is right only
because `.opacity(_:)` scales every inner region by its own factor *before* stamping its
rectangle last, so the inner region already holds the product. The tint did the stamping
and not the scaling, so any inner region won the layer and the tint's alpha went nowhere:

- `Text("hi").opacity(0.5).colorMultiply(.white.opacity(0.5))` resolved at the inner
  0.5 rather than a quarter — the difference between winning and losing the ½ contest
  against a sibling behind it;
- `Text("hi").foregroundStyle(.red.opacity(0.5)).colorMultiply(.clear)` needed no
  `.opacity(_:)` at all: a translucent foreground claims its ink at layer 1, that claim
  came first, and the text §25 promises to hide was drawn.

The tint now goes through `_OpacityView.fading`, the same scale-then-stamp with inner
cycles scaled alongside, so `.opacity(x)` and `.colorMultiply(.white.opacity(x))` nest
identically in either order.

### 25.3 Displaced drawing: §9.4's L4, in the colour effects (2026-09-12)

All seven colour effects opened with `guard !buffer.isEmpty`, and `isEmpty` asks about
the LINES. `.offset`, `.position` and a moving transition's slot draw nothing in flow and
put the drawing in an anchored overlay, so over a wholly displaced subtree every effect
was a complete no-op. Over a mixed one it was half applied, because the rewrite walked
`lines` and never `overlays`: `VStack { a; b.offset(x: 1) }.grayscale(1)` drew `a` grey
and `b` in colour, and `.colorMultiply(.clear)` left an offset child fully visible.
`.opacity(_:)` had exactly this shape fixed in d4399a9d (".opacity() over an offset child
did nothing at all"); its twin in the next file was never touched.

The effects now take both of `_OpacityView`'s halves: the guard asks about overlays too,
and the rewrite and the tint's layer fade recurse into every layer that is not
`isScreenLevel`. A presented `.sheet` or `.alert` is still left alone, as it is by
`.opacity(_:)`, `.hidden()` and `.allowsHitTesting(false)`. A placeholder's empty lines
are not rebuilt, since rebuilding re-measures them at zero and loses the width the slot
declares. And a rewritten buffer now keeps its declared width rather than re-measuring,
because a rewrite changes escapes and never a visible character.


## 26. `ColorPicker`: the swatch was already right, and a refusal expired (2026-09-09)

Row 12 turned out to be two unrelated things.

**The swatch needed nothing.** `_ColorSwatchButtonStyle` draws
`Text("█").foregroundStyle(fill).background(fill)`, and both of those were migrated
in §14 and the flat `.background` arm. A picker bound to a translucent colour
renders it faithfully. That is the composition working as intended — but it is two
features deep, so `ColorPickerAlphaTests.swatchFades` asserts it rather than leaving
it to be assumed and quietly broken later.

**`supportsOpacity` was a real parity gap.** It was omitted deliberately, with a
stated reason: *"There is no opacity channel — terminal colours have no alpha — so
`supportsOpacity` is omitted."* `Color` gained one on 2026-09-08, so the reason was
simply gone, and what was left is worse than a plain omission: the control
**displayed** an alpha it gave no way to **edit**. Built in §32.

`Documentation/SwiftUI-semantic-audit-2026-08.md` listed this among "the refusals that
pass the test". It has been moved out. The audit's own tally is worth updating with
it: five out of five refusals examined across audits have now turned out to be wrong
or to expire.

### 26.1 `String.styled`, and why the claim helper is public

Row 4 is the documented escape hatch for a reader writing their own `Renderable`, and
it is answered rather than migrated: there is nothing inside `String.styled` to fix,
because the caller owns both halves. What was missing was any way for that caller to
make the claim the framework's own paint sites make.

`OpacityRegion.claim(offsetX:offsetY:width:height:ink:field:)` is public for exactly
that. The pattern a reader needs is the one every migrated site in §18–§25 follows:

```swift
let line = ANSIRenderer.colorize(
    glyphs, foreground: ink.opaqueSpelling, background: field?.opaqueSpelling)
var buffer = FrameBuffer(lines: [line], width: width, lineWidths: [width])
buffer.opacityRegions += OpacityRegion.claim(
    width: width, height: 1, ink: ink, field: field).map { [$0] } ?? []
```

State the opaque spelling in the bytes, because an emitter has no backdrop; put the
alpha in a region, because only a composite knows what is behind. Skipping the second
half leaves the colour at full strength and trips the emitter's assertion in a debug
build, which is the intended way to find out.


## 27. Two claims on one cell, and the path that only took the first (2026-09-10)

§13 records a bug and its fix: `.foregroundStyle(.green.opacity(0.4))
.background(.red.opacity(0.4))` stamps two independent regions over the same cells —
one carrying ink 0.4, one carrying field 0.4 — and a resolver that took the *first*
match dropped one of them. The fix was to multiply ink and field across every
covering region while still taking the layer from the first, because a layer's alpha
has already been nested by `OpacityFade.fading` and a colour's has not.

**That fix reached the line walk and not the run walk.** `resolvingOpacity` blends an
`AnimatedCellRun`'s frames as well as the lines — it has to, or a run built inside a
fade would replay unfaded over the faded picture — and its per-column closure still
read `covering.first`.

So the same cell resolved two ways depending on *when* you looked at it. The frame
the render drew came out faded on both channels; the frame the replay spliced a tick
later had the background back at full strength, and every tick after that repainted
it. A `Spinner` inside those two modifiers is the whole repro. It could not be found
by looking at a rendered buffer, because the bug is not in the buffer — it is in the
frames travelling beside it.

Both walks now call one `foldedAlpha(of:atColumn:row:substituting:)`, which is where
the asymmetry between the layer channel and the other two is explained. The
`substituting:` closure is what lets the cycling-run path substitute a phase for the
layer while the ink and field ride along, so the three callers share the fold without
sharing the phase.

`runFramesFoldEveryClaim` asserts the frames against the line rather than against a
constant: whatever the line did with two claims, the frame spliced at the tick just
drawn has to do too. That is the property, and stating it that way is what makes the
test outlive the arithmetic.


## 28. A hover lift half-restored a faded colour, and the two other things a palette does with alpha (2026-09-10)

§20 fixed `resolve(with:)` discarding a palette slot's alpha. That was the way *in*;
this is what happens once it is there. `Palette` is a public protocol of plain
`var …: Color { get }` members, nothing normalises a custom one, and the derived
colours — every surface, every pulse end, every hover lift — turned out to do **three
different things** with a faded slot, only two of them decided by anyone.

| | what it is | the alpha | why |
|---|---|---|---|
| **carries** | a re-*spelling* | travels | the same ink written differently; only a composite knows the real backdrop |
| **spends** | a *composite* over a ground the palette states | consumed, result opaque | `opacity(_:over:)`; §21's rule for pulse pairs |
| **drops** | a lightness step through `Color.rgb(…)` | gone | `scaled(_:by:)` rebuilds from `rgbComponents` and cannot carry what it never reads |

`FadedPaletteDerivationTests` pins all three, one test per category, because the
third was invisible: an opaque colour never trips the emitter's assertion, so the
only symptom was a faded theme rendering solid.

### 28.1 `hoveredForeground` was in none of the three

It came back at **alpha 184** from a slot at 128. That number is the whole diagnosis:
neither carried (128) nor spent (255), so it was not a decision at all. Both arms
leak, differently — `stepped(toward:)` builds candidates with `Color.lerp`, which
interpolates alpha as a fourth channel toward an opaque extreme (correctly: that is
what makes `withAnimation` fade a colour's own opacity), and its `best == nil`
fallback returns the opaque target outright.

So the mere presence of the pointer half-restored a translucent `.tint`, and then the
control that drew the label tripped the assertion two frames later. It is a live
defect in already-migrated territory: `hoveredForeground` is on the plain-button path
*and* on `_ToggleCore`'s and `RadioButton`'s indicator path, which §23 closed.

`derivationsCarryAlpha` could not see it. Its `lerp` row is
`Color.lerp(faded, faded, phase: 0.5)` — two equally-faded ends, the one input to a
four-channel interpolation that cannot drift.

It now ends in `carryingAlpha(of: resolved)`. Carried and not composited on purpose: a
composite here would spend the alpha against a ground this function would have to
*guess*, where carrying leaves it for the one that knows.

### 28.2 The surface steps are left as they are, and said so

`fieldBackground`, `fieldBackground(on:)`, `liftedBackground` and `lifted(from:)` drop
it. Not fixed, and the test that pins them says why rather than implying they are
right: a well stepped off a half-transparent page could reasonably be equally
transparent (one wash all the way down) or deliberately solid (a field you can read
in), and choosing changes the chrome depth of every faded theme. No paint site
migrated so far reaches them, so nothing is silently wrong *today* — what was missing
was any statement that the question is open. This is the project owner's call.


## 29. Four copies of one pulse pair, three of them wrong (2026-09-10)

§21 fixed `accentPulse`: a focus breath's two ends must **both** spend a translucent
tint's alpha against the same stated ground, or the run's frames have an alpha that
genuinely differs per phase and no static claim can describe it.

It fixed one copy. There were four.

| | dim end | bright end |
|---|---|---|
| `Palette.accentPulse` | `accent.opacity(min, over: ground)` | `accent` — **fixed in §21** |
| `BorderRenderer.breathEnds` | `resting.opacity(focusBorderDim, over: surface)` | `resting` |
| `AnimatedColor.activeSection` | `accent.opacity(focusBorderDim, over: surface)` | `accent` |
| `ButtonCapCycle` | the button's own face | `accent` |

(`ButtonCapCycle`'s dim end was only ever as opaque as the button's face, and one exit of
the hovered face returned the raw accent — §49.)

The first three are the *same expression*, written out three times with different
constants; the fourth shares only its bright half, because a cap recedes to the
button's face rather than to a dimmed accent. Every one of them consumed the alpha at
the quiet end and carried it at the loud one — so a focused `Link`, a focus section's
●, a bordered box's ● and a standard button's caps all breathed between an opaque
colour and a translucent one under `.tint(.red.opacity(0.5))`.

`Color.breathEnds(dimmedTo:over:)` is now the one place the rule lives, with
`spendingAlpha(over:)` as its bright half for the fourth caller. Four copies of an
expression that had already drifted three ways is the shape `CONTRIBUTING`'s reuse
rule exists for, and the fix is cheaper than the fourth copy would have been.

### 29.1 Why the bright end is a guard and not a composite

`spendingAlpha(over:)` returns an opaque colour **untouched** instead of compositing
it at 1. That is not an economy. `opacity(_:over:)` goes through `lerp`, and a lerp
re-spells `.red` — SGR 31, the terminal's *own* red — as `rgb(205, 0, 0)`. The same
colour arithmetically; a different colour on any terminal whose palette is not the
default. This is the bright end of every focus pulse in all sixteen shipped palettes,
so `opaqueEndKeepsItsSpelling` asserts the **bytes**, not the value.

### 29.3 A fifth copy, in the caret

Found by the migration in §30 walking into it: `TextFieldContentRenderer.caretState`
builds the same pair a third way — `dim = baseColor.opacity(focusPulseMin, over:)`
lerped toward a bare `baseColor`. `palette.cursorColor` defaults to the accent, so a
custom palette (or a palette bound to a live colour editor) gave a caret whose alpha
swept **128 → 250 across fifteen of sixteen ticks**, and a block caret puts that
straight into `backgroundCodes`.

Worth recording as a lesson about the test rather than the fix. A two-end assertion
would have missed it: tick 0 *is* the opaque dim end. The invariant is that a run's
frames all answer to one static claim, so `caretPulseIsOpaqueAtEveryTick` asserts over
every tick of every animation — and it is the tick *list* in the failure message that
makes the interpolation legible.

### 29.2 What this unblocks, which is more than it fixes

§18.4, §19.1 and §23 all record the same decline: *an animating colour cannot carry a
claim, because the run repaints its cells per tick and one region would resolve every
phase at the alpha drawn now.* That is **too strong**, and the pulse asymmetry above
is most of why it looked true.

`resolvingOpacity` already re-blends every frame of every covered run
(§27's neighbourhood, `OpacityResolution` lines 238–279): each frame passes through
`blendedSpan` against the real destination at the region's alpha. So a run under a
**static** claim replays correctly — the frames come back at *different* faded
colours, each blended from its own phase. Verified directly: two frames at
`rgb(200,40,40)` and `rgb(255,90,90)` under one `inkOpacity: 0.5` claim over a blue
backdrop resolve to `rgb(100,20,139)` and `rgb(128,45,164)`.

What actually blocks a claim is narrower, and there are only two cases:

> **Case 2 is no longer a block** — see §69. A run can carry an alpha per FRAME
> (`AnimatedRunAlpha`), so phases that disagree are stated rather than declined. What
> follows is the reasoning as it stood, and it is still why case 1 blocks.

1. **A `cycle`-bearing region** — a repeating `.opacity` fade. Those runs are dropped
   (`covering.allSatisfy { $0.cycle == nil }`), because the fade's phases and the
   run's frames tick independently and their product is not one run.
2. **A pulse whose phases have different alphas** — which was this bug, in four
   places, and is now none. (Five, with the caret in §29.3; six, with the scrollbar's
   lift, which was not migrated until §43 and so could not be tested — §44; seven, with
   a navigation crumb's breath under a faded tint — §47; eight, with a colour swatch's
   bullet under a faded palette — §48; nine, with the text scroll indicators' breath
   under a faded tint — §53; ten, with a tab chip's breath under a faded tint — §55;
   eleven, with a switch track's under a faded tint or foreground — §58; twelve, with a
   split view divider's grip dot on hover — §63; thirteen, with a drop-down menu's
   breathing border — §64.)

A caller's own `AnimatedColor` is outside all of that: nothing normalises its frames, and
the type's documented example breathes between two palette slots that a faded tint sets
at different alphas. A border handed one whose frames disagree still cannot claim
(§59.2).

So the declines that named the pulse as their reason are stale. Their real remaining
obstacle is per-*cell* alpha (`Table`'s banded arm, `Text`'s ramped ink), which is a
different problem with a different answer — §15.


## 30. The six controls that read the style cascade (2026-09-10)

Row 10 of §16.1: `.style(.text) { $0.foreground = … }` and its six per-control
spellings — `.buttonTextStyle`, `.textFieldTextStyle`, `.secureFieldTextStyle`,
`.sliderTextStyle`, `.stepperTextStyle`. `Text` honoured a faded cascade colour from
§14. The controls that read the *same* cascade entry spent it on the escape.

Every one of them knew its rectangle already, which is why this is a migration and
not a design:

| site | the rectangle |
|---|---|
| standard `Button`, string label | one cell in, the label's width — the caps are their own colour and their own runs |
| plain `Button`, string label | past `BorderRenderer.focusIndicatorWidth`, which the prefix always reserves |
| `TextField` / `SecureField`, unfocused | the whole content field, which the padding guarantees is exactly `width` |
| `TextField` / `SecureField`, focused | one claim per coalesced run |
| `Slider` read-out | `5 + drawnTrackWidth`, the digits only |
| `Stepper` read-out | past the left arrow, *measured* — `◀` is East Asian Ambiguous |

The `@ViewBuilder` label path needed nothing: its colour leaves as
`labelView.foregroundStyle(labelFg)` and the `Text` inside claims it. Asserted rather
than assumed, because "already correct by composition" is exactly the kind of thing
that stops being true.

### 30.1 A focused field claims per run, not per field

One rectangle for the content would have been simpler and wrong. A focused field's
cells genuinely differ: the selection's field is opaque by construction
(`selectionColors` goes through `opacity(_:over:)`), its text is `readableText(on:)` — a
palette slot, floored, carrying that slot's alpha (§60) — and the entered text's are the
cascade's. One rectangle fades the highlight along with the text.

The run boundaries *are* the colour boundaries — that is what the coalescing exists
for — so a claim per flushed run costs only remembering the column each run opened
at. `RunAccumulator` now owns the bytes and the claim together, which is what keeps
the opaque spelling and the real alpha from drifting apart.

### 30.2 The caret is the one place that must spend rather than claim

A caret's frames disagree about alpha *by construction*: the blink-OFF frame draws
the underlying character in the text colour, which the cascade may have faded, and
the blink-ON frame draws the caret's own colour, which is opaque. One static region
over those cells would fade the caret glyph along with the character. This is §29.2's
remaining case — a per-cell animation over app-coloured text — and the field is the
one control that reaches it.

So the caret's cells **spend** the ink's alpha, `Color.spendingAlpha(over:)`, the way
§29 settles a breathing label. Unlike that case it is not a guess: a styled field
*paints its own surface*, so `background` is literally what is behind this ink and
compositing over it gives the same answer the resolver would have given a claim. Only
`.plain` — which emits no background at all — falls back to the page, on the caret's
cells, while the caret is visible.

### 30.3 Two arms answered by §29 rather than migrated

- **A breathing label.** A `Link`, and anything `indicatesFocusInLabel`, breathes the
  label itself. Both ends now spend their alpha against the enclosing surface, so
  there is nothing left to claim — `breathingLabelSpends` records that as the
  expected answer rather than leaving a future reader to find a missing claim.
- **The focus ●.** §18.4 left this open. `focusIndicatorEnds` goes through
  `Color.breathEnds`, so the bullet is opaque at every phase including the still one
  under `.selectionIndicatorStyle(.none)`. A claim there would in fact be *harmful*
  when the button is unfocused: the prefix is then two bare spaces, and an ink claim
  on a cell with no ink of its own lets what is behind it through.

### 30.4 Two things these controls still drop, and neither is about alpha

Found while reading, recorded because a test could otherwise pass for the wrong
reason:

- **None of the six reads `cascaded.background`.** Only `Text` does. `.style(.text)
  { $0.background = … }` is silently dropped by all six, translucent or not.
- **`Button` never publishes `\.controlKind`**, unlike `Picker`, `Slider`, `Stepper`,
  `Toggle` and `RadioButton`. So a `@ViewBuilder` label's `Text` never resolves
  `.control(.button)`; `_ButtonStyleBody` compensates for the foreground alone, and
  `cascaded.bold` / `.italic` / `.underline` / `.strikethrough` / `.textCase` are
  read and then never applied to a view label at all.


## 31. The track: nineteen emit sites that all knew their columns (2026-09-10)

Row 8 of §16.1 — `TrackConfiguration(emptyColor:)` (now `backgroundColor:`) and `SegmentColoring` — said "3+
sites". It is **nineteen `ANSIRenderer.colorize` calls across six functions**, and the
count is the least interesting thing about them: every one already tracked cells,
because a track's whole job is to fill exactly `width` of them. What none of them did
was *say* where a run started.

The structural blocker was the return type. `TrackRenderer.render` returned a bare
`String`, so there was nowhere for a claim to travel. It now returns `DrawnTrack` —
text, claims, and how many cells were actually drawn — and every arm goes through one
`append(_:cells:ink:field:)`, which states the opaque spelling and derives the claim
in the same statement. Nineteen hand-written `opaqueSpelling`s would have been
nineteen chances to forget, and a twentieth drawing arm added later would have
reintroduced the trap silently. Same reason `BorderRenderer.band` exists (§18.3).

`cells` is not a convenience. The coarse path permanently shrinks a track to a whole
multiple of its quantum, so a claim derived from the *requested* width would sit past
the end of what was drawn — the lesson `Slider`'s right-arrow run had already learned,
and `drawnTrackWidth` now comes from `DrawnTrack.cells` rather than a
`strippedLength` recount.

### 31.1 The one cell whose two channels come from different colours

`.blockFine`'s fractional boundary cell takes its **ink** from the fill and its
**field** from the empty colour: the ramp glyph covers the filled fraction, and the
unfilled colour shows through the rest of the cell. An opaque `█` fill with a
translucent `TrackConfiguration.emptyColor` (now `backgroundColor`) must resolve `inkOpacity == 1,
fieldOpacity < 1` — solid glyph, faded remainder.

This is the cell that proves the two channels earn their keep. A single alpha per cell
gets it wrong in *both* directions, and `boundaryCellSplitsItsChannels` pins it.

### 31.2 A track's per-cell gradient is honourable, unlike a page's

§15 declines `perCell` ramps because a 2-D ramp needs a region per cell and the
resolver's fold is a linear scan per column. A track is **one row**, so per-cell alpha
is a run of one-cell rectangles rather than a grid — 10 to 40 of them, not 80 × the
height. So `.threeSegment(coloring: .gradient(…))` with translucent stops is fully
honoured, and so is a per-cell `emptyGradient` (now `backgroundGradient`). A narrower result than §15's, and the
narrowness is the point.

### 31.3 A disabled slider spends where an enabled one claims

`_SliderCore.forState` composites every track colour through
`opacity(_:over: palette.background)` when the slider is disabled, which consumes the
alpha and stamps the result opaque. So a disabled slider's translucent tint resolves
against the *palette's* background and an enabled one's against the real backdrop: one
colour, two answers, decided by `isEnabled`.

Left as it is — `disabledSliderClaimsNothing` records it — because it is the same
substitute-versus-compose choice §21.1 makes everywhere else, and a disabled control's
whole job is to recede against the page it sits on.

### 31.4 What still does not claim, and why each is a decline

- **The picture path.** `.block` — `ProgressView`'s default — becomes Kitty
  placeholder cells on a terminal that draws pictures, and `GradientRaster.Picture
  .format` is hardcoded `.rgb`. Even with an alpha channel it would be the *terminal*
  compositing against its own background, not against what TUIkit drew behind the
  cell. So a translucent track now **declines** the picture and takes the cell path,
  which claims correctly. Without the decline the gap would be
  terminal-distributed — right on Apple Terminal, wrong on kitty and Ghostty — which
  is the failure §15.1 refuses.
- **The indeterminate sweep.** Its whole row is one `AnimatedCellRun`, and a sweep
  *moves*: a given column is lit in some frames and unlit in others. The resolver
  re-blends a run's frames at one alpha per column for all frames, so a static region
  is right only if every colour any frame can paint shares one alpha — which
  `emptyColor` (now `backgroundColor`) and `accentColor` do not. Still loud.
- **Pre-styled segment strings.** `.automatic` / `.solid` / `.perSegment` accept
  segments carrying the caller's own ANSI. Where they do, some cells' effective ink is
  not the colour the claim is about. The run *was* painted at that alpha, so the claim
  is approximate rather than wrong, and there is no way to ask a pre-styled string
  what it will look like.
- **The circular gauge**, found in passing and NOT part of row 8: `renderCircularTiny`
  and `renderCircularDial` paint their own cells and bypass `TrackRenderer` entirely.
  A translucent `.tint` reaches all four of their emit sites. Added to §16.1 as its
  own line so finishing the track is not mistaken for finishing the `Gauge`.


## 32. `ColorPicker.supportsOpacity`, and what a terminal swatch shows (2026-09-10)

The last row of §16.1, and the only one that was a feature rather than a migration.
`supportsOpacity` now exists on both inits with SwiftUI's own default of `true`, adds
a fourth `A` channel to the inline row, and an **Opacity** row to `ColorPickerPanel`.

### 32.1 The hard question turns out to be already answered

*What does a half-transparent swatch show against?* SwiftUI draws a checkerboard,
because it has to invent a backdrop. A terminal does not: the swatch states its
colour's opaque spelling and claims an `OpacityRegion` over its own cells, so the
alpha resolves against **whatever is actually behind the swatch on the page** — the
dialog, the row, the list, whatever the composite finds. That is this branch's whole
thesis arriving where it is most visible, and it needed no code: §26 verified the
swatch was already right, and `swatchFades` had already pinned it.

So: no checkerboard, and no assumed backdrop. The alpha's *value* is legible from the
read-outs, which is what a terminal has instead of a texture.

### 32.2 The opacity row is outside the tabs, because alpha is in no colour model

RGB, HSL, HSB and CMYK each describe a colour; none of them describes how much of it
there is. A fifth entry in `Mode.channels` would have put a *different* opacity slider
on four tabs, each with its own `@State`, and made the value appear to change when you
switched tab.

It needs no held state either, unlike the model channels: alpha is the one channel
here that is not over-determined, so reading it back out of the colour is exact and
there is nothing to re-canonicalise. `_ChannelRow` was extracted so the opacity row is
the *same control* as an R/G/B row rather than a second one that looks like it.

### 32.3 The bug the fourth channel exposed, which was there all along

Every write path in the picker rewrote the colour as an opaque spelling — `.rgb(…)`,
`.hsl(…)`, a swatch grid's entry, a parsed hex, a semantic role's snapshot. So a
picker bound to a translucent colour **deleted its alpha on the first arrow press**: a
control that could not edit opacity destroyed it instead.

Fixed once, at the top, with a `colorOnly` binding that carries the existing alpha
onto every write — one transform rather than a repair at each of six sites, which is
also the only shape in which a seventh cannot be forgotten. It states the division of
labour the panel now has: **the model tabs edit the colour, the opacity row edits the
opacity.** That is why the semantic tab snapshots a palette role's RGB and leaves your
alpha alone even when the role itself is translucent — picking a hue is not a
statement about transparency.

Two consequences worth naming:

- `_ChannelEditor` re-seeds on an external change, and an alpha edit is external to
  it. Compared by `opaqueSpelling` now, so dragging the opacity slider does not
  re-canonicalise an over-determined model — CMYK's C/M/Y snapping away under a raised
  K, a desaturated colour losing its hue — which is precisely what the held channels
  exist to prevent.
- It records `lastProduced` by reading the binding **back** rather than by remembering
  what it sent, because what lands is no longer what was written.

### 32.4 `supportsOpacity: false` withholds the editor, never the value

The channel goes, and the swatch draws opaque — a control that offers no opacity
should not display one, or the single state you cannot reach is the one you can see.
But the **binding keeps its alpha**: editing R, G or B carries it through on every
path whatever the flag says. The flag governs what the control *offers*, not what the
app's value *is*.

## 33. `Table` and `List`: three paints per row, and a decline that was stale (2026-09-10)

Row 2 of §16.1 for `Table`, and its `_ListCore` twin in the same commit — because
`RowSelectionIndicator` and `RowBackground` live in one file for exactly the reason
the two have drifted apart before, and "which cells of a row owe a blend" is one more
rule that must not be written twice. `SelectableRowClaims.claims` is now there with
them.

A selectable row paints three things of its own, and they claim **three rectangles**
that must not be merged:

- the **cells' ink** — `.foregroundStyle(.red.opacity(0.5))` on a `Table`, or a theme
  whose `foreground` slot is faded;
- the **selection mark**, in `palette.accent` and so one `.tint` away;
- the **still background**, `palette.focusBackground`, which a theme may fade.

The mark and the cells are different colours, so a merged ink rectangle would resolve
the ● at the text's alpha — §23.2's mistake in another shape. The fill is a different
*channel*, so its rectangle overlaps both, and that is correct: the resolver
multiplies ink and field across every region covering a cell (§27). The gap cell
between mark and text carries the **fill** claim only — it is a bare space with no ink
of its own, and an ink claim there lets what is behind it through where the row drew a
pad.

### 33.1 §19.1's reason for declining was stale

§19.1 declined `Table` because *the cursor row pulses, so no static claim can describe
it*, and said the fix wanted phase-indexed alpha. Both halves turn out to be wrong:

1. **The pulse repaints the FIELD, not the ink.** `renderRow` builds the line once
   with its ink SGR already in it and then applies the background to the finished line
   per step. So every frame states the *same* ink at the *same* alpha.
2. **The fill's own alpha is already spent.** `accentFillPulse` returns both ends
   through `Color.opacity(_:over:)`, which stamps them opaque (§21, §29). There is
   nothing left for a fill claim to carry, which is also what lets the pulse be a run
   at all.

So a static INK claim is true of every phase, and `resolvingOpacity` re-blends a
covered run's frames through it (§29.2). The migration is honest on all twenty rows
*including* the selected one, which is exactly the thing §19.1 doubted.

### 33.2 A banded table claims all its rows or none

A `Table` under a horizontal, radial or angular gradient paints cell by cell through
`PaintRenderer.band` — §15's `perCell` decline. That arm stays loud, with its bytes
*unspelled* so the emitter's assertion still fires: spelling them opaque would turn a
loud gap into a silently discarded alpha, which is the one failure mode §18.3 names.

It is not a partial-migration hazard, and the reason is worth stating: `bandsAcrossRow`
comes from ONE sampler built per frame, so every row of a given table takes the same
arm. Never right on nineteen rows and wrong on the twentieth.

### 33.3 A gap this leaves in the tests, said plainly

Every translucent thing a **`List`** can paint requires the list to hold the focus:
the unfocused mark and the unfocused selected background both spend their alpha
through `opacity(_:over:)`. Focusing a `List` from a headless `renderToBuffer` did not
work — two full render passes with `beginRenderPass`/`endRenderPass` around each, then
`focusNext()`, then `focus(id:)` against an explicit `.focusID`, all left the rows
unfocused.

So `_ListCore`'s arm was tested at the **seam** — the shape the shared derivation
produces for a list row, which paints no cells of its own — and its focused end-to-end
path had no assertion. `Table`'s equivalent needs no focus (its ink comes from
`.foregroundStyle`) and is tested end to end. That was recorded as a real hole rather
than papered over with an unfocused render that would have passed for the wrong
reason.

**Closed in §36.8, and it was two mistakes rather than a limitation.**


## 34. The ramp cases: one was two, and the other is a cost (2026-09-10)

§16.3's last two unhonoured entries were "`Text`'s ramped ink" and "per-cell ramps".
Both descriptions turn out to be wrong, in opposite directions.

### 34.1 `Text`'s ramped ink was unhonoured for all four shapes, not one

§15 taught `.background` to read a ramp's `AlphaShape` and claim `uniform` and
`perRow`. Nothing taught `Text`. `PaintRenderer.styled` returned `[String]` and had no
channel for a claim, so an ink ramp was unhonoured **whatever** its alpha shape — an
evenly-faded ramp on text, a vertical scrim on text, and a one-stop translucent
gradient (which `RampSampler.init?` refuses, so it fell through the flat arm and
rendered at full strength) were all silently solid.

`styled` now returns `(lines:claims:)` and takes `lineWidths`, because a text block is
**ragged** and a claim must not outrun the line it is about. Nothing else at the call
site changed: `Text` already pads and rows `perLineClaims` through
`LineSpacingRows.interleaved`, so line spacing was handled before this arrived.

`band` gained a `carriesAlpha` flag rather than an unconditional `opaqueSpelling`. That
distinction is the whole discipline: the shape that is *not* claimed keeps its raw
colours in the bytes, so the emitter's assertion still names it. Spelling it opaque
without the claim turns a loud gap into a discarded alpha, which §18.3 records as the
one failure worse than the gap.

### 34.2 A horizontal ramp is `perColumn`, and was declined for a cost it does not have

The classifier asked one question — does the colour vary *across* a row? — and treated
"yes" as per-cell. For a **horizontal** linear ramp the answer is yes and the
conclusion is wrong: the colour is identical all the way *down* each column, so its
alpha is one full-height rectangle per column. The mirror of `perRow`, and every bit as
cheap.

That is the commonest ramp anyone writes — a fade along a header, a bar, a title — and
it was being refused. `variesDownColumn` is the fact that was missing, derived beside
its twin from `axisY != 0`, which is exactly what makes `rowTerm(row)` zero for every
row.

`alphaRuns(row:cells:)` is the coalescer these claims need. `runs(row:cells:)` breaks at
every change of ramp **entry**, which is right for emitting colour and wrong for a
claim: adjacent entries usually share an alpha, so one claim per colour run
over-splits — a `uniform` ramp comes back as eighty width-1 rectangles instead of one.

### 34.3 Genuine `perCell` stays declined, and the reason is arithmetic

What is left is radial, angular, elliptical, and *diagonal* linear — a ramp whose alpha
varies in both directions. It is **expressible**: `blendedSpan` already takes a
per-column alpha closure. It is not affordable, and two costs say so:

1. **The resolver's fold is linear per column.** `foldedAlpha` walks every region
   covering the row, once per column. An 80-column row with 80 width-1 claims is 6,400
   containment tests; over a 24-row block, ~154,000 per resolve per frame.
2. **`opacityRegionsPunched` fragments.** It runs at every `composited(with:at:)`
   between the leaf and the root, and `subtracting` returns up to four pieces — so
   1,920 claims do not stay 1,920, they multiply with composite depth.

And nothing coalesces them: a full-range alpha fade over 80 steps moves 3.2 per step,
so every value is distinct and there is genuinely nothing to merge.

The prerequisite is known and is not part of this pass: build the row's answer **once**
per row into a `[CellAlpha?]` indexed by column, rather than once per column across the
regions — O(Σ widths + width) instead of O(width × regions). That is a change to the
resolver's hot path and wants its own commit and its own A/B.

So the decline stands, and it is now narrow: not "ramps on ink", not "ramps whose alpha
varies along a row", but *ramps whose alpha varies in both directions at once*.

### 34.4 The field is not part of that question, and folding it in broke both ends

A ramped `Text` can also carry a flat background from the style cascade
(`.style(.text) { $0.background = … }`), and that is one rectangle per line whatever
the ramp over it does. The first version of this asked
`paint.isOpaqueThroughout && fieldAlpha == .max ? .opaque : sampler.alphaShape` — one
question for two independent things — and got both ends wrong:

- an **opaque** ramp over a faded background reported `.opaque` and claimed nothing;
- a **per-cell** ramp left the background's own bytes translucent while claiming it —
  a double fade in release and an assertion in debug, on a path that *is* honoured.

The field is now always claimed and always spelled opaque; `carriesAlpha` governs the
ramp's colours alone, and `band`'s parameter documentation says so, because it is the
kind of flag a later reader would reasonably assume covers everything in the style.
`opaqueRampStillClaimsItsField` pins both halves.


## 35. What the whole pass cost (2026-09-10)

`ab_bench.py`, cpu-per-frame, paired, order randomised per rep, against `33e7aab2` —
the tip before this pass. 20 reps over all nineteen scenarios, then 60 reps on the
ones that flagged.

**Eighteen of nineteen indistinguishable.** The residual is on the two scenarios built
out of the thing that gained the most per-row work:

| scenario | change | 95% CI | reps |
|---|---|---|---|
| `table` | **+0.4%** | [+0.1, +0.7] | 60 |
| `tables-scroll` | **+0.5%** | [+0.2, +0.8] | 60 |
| everything else | indistinguishable | | 20 |

RAM flat everywhere (±0.2 MB).

That is the price of a `Table`'s rows carrying claims for their ink, their selection
mark and their still background: one extra tuple member and one guarded `+=` per drawn
row. It is the same shape and the same size as the residual §18–§26 left on
`framedcolumns` (+0.5%), for the same reason — the scenario made of the thing that
changed pays, and nothing else does.

### 35.1 Three regressions that were one mistake

The first run flagged `gradients` +2.5% [+0.4, +3.0], `megalist` +1.0% [+0.6, +1.7] and
`table` +0.7% [+0.4, +1.0]. All three were a claim derivation doing work *before*
asking whether there was anything to claim — and in these scenarios nearly every row
and every painted block is fully opaque:

- `PaintRenderer.styled` grew an outer array to `lines.count` empties per ramped block.
- `_ListCore`'s `claims(over:)` ran a `flatMap` before consulting the alphas.
- `Table.renderMultiLineRow` evaluated `RowBackground.claimableFill` twice per line.

`gradients` went **+2.5% → −0.1%** from one guard, which is what makes the diagnosis
confirmed rather than merely consistent. `megalist` went to −0.0% [−0.9, +0.8].

The pattern to copy is already in the tree: `Text.uniformAlphaClaims` answers `[]`
rather than a list of empties, and says so at the line. Every new derivation should.

### 35.2 A note on the measurements themselves

The first run was taken at load 3.84 with `XprotectService` at 36.6%, which
`ab_bench` reports in its own header. `megalist` read +1.1% there and −0.0% at load
1.50; `table` read +1.2% [+0.1, +2.1] at 20 reps on a busy box and +0.4% [+0.1, +0.7]
at 60. The paired design absorbs preemption but not cache contention.

So: the allocations were real and worth fixing, and every *width* in the first run was
wrong. Re-measure a flagged scenario on a quiet box before believing its size, and
before deciding whether it is worth chasing.


## 36. The per-cell ramp: the prerequisite, then the shape (2026-09-10)

§34.3 declined a ramp whose alpha varies in BOTH directions on cost, and named the
prerequisite: *build the row's answer once per row into a `[CellAlpha?]` indexed by
column, rather than once per column across the regions.* This is that, and then the
decline it existed to lift.

### 36.1 The resolver answers a row at a time

`foldedAlpha(of:atColumn:row:)` was asked once per column and walked every region
covering the row each time — O(width × regions), each region costing a containment
test of four comparisons plus a call through the `substituting` closure. Fine at one
or two claims a row, which is every shape §34 honoured. Not fine at eighty: an
80-column row with 80 width-1 claims is 6,400 containment tests, ~154,000 over a
24-row block, per resolve per frame.

`foldedAlphas(of:over:row:)` inverts the loops. Walk each region once and fill the
cells it covers: O(Σ widths + width), which for the same eighty claims is eighty
stores. Three things fall out of the inversion rather than being optimised:

1. **The containment test disappears.** A region's rows are already known — the
   caller asks `spans(row:)` first — and its columns become the bounds of the fill
   loop rather than a predicate evaluated per cell.
2. **`substituting` is called once per region** instead of once per region per
   column. For a cycling region that closure walks a phase array and compares
   clocks, so this is the larger of the two savings on a fading panel.
3. **A run's frames share one fold.** The run walk was folding per column *per
   frame*; every frame of a run occupies the same cells, so the answer cannot differ
   between them. An eight-frame spinner was computing it eight times.

The cost is one array per covered row, where the walk allocated nothing. Measured
against `172599ec`, 24 reps, load 2.63:

| scenario | change | 95% CI |
|---|---|---|
| `translucent` | −0.1% | [−1.0, +0.3] |
| `gradients` | −0.9% | [−1.8, +0.1] |
| `table`, `megalist`, `tables-scroll`, `deep`, `dashboard`, `menus`, `kitchensink` | indistinguishable | |

`translucent` is the scenario built for this path — a large faded panel over a
destination that redraws every frame, half its rows nested — and it is the one that
would have shown the allocation. It does not. RAM flat everywhere.

So the prerequisite is free at today's shapes and asymptotically better at the shape
it was for, which is the whole of the case for making it first and separately.

### 36.2 The shape itself, and what it cost

With the fold inverted, `perCell` becomes `perColumn`'s walk asked once per row.
Nothing else about it is new: `RampSampler.alphaRuns` already coalesced on the ALPHA
rather than on the ramp entry, so a run of cells that agree is one rectangle, and the
two shapes are one `case` in `PaintRenderer.claims`. `BackgroundModifier` keeps them
apart, because there a `perColumn` claim really is one full-height strip and a
`perCell` one cannot be.

`RampSampler.alphaClaims(row:line:columns:)` is the one derivation, and it takes a
column RANGE rather than a cell count so a `Table` can claim the span its cells
actually occupy — its cells start past the selection gutter, and a run derived from
column zero would state each cell's alpha two columns to the left of the cell it was
painted for.

**Measured, and it is not free.** `ab_bench.py` against the same tree with the claims
removed, 24 reps, load 1.73:

| scenario | change | 95% CI | RAM |
|---|---|---|---|
| `alpharamp` | **+14.9%** | [+13.6, +16.2] | 11.4 → 12.7 MB |
| `gradients` | −0.7% | [−1.2, +0.4] | flat |
| `table`, `tables-scroll`, `translucent`, `megalist`, `textwall`, `kitchensink` | indistinguishable | | flat |

So: **fifteen percent on a page that is nothing but translucent ramps, and nothing
anywhere else.** That is the right shape — the feature is paid for by the pages that
ask for it — and it is a price, not a rounding error, so it is written here rather
than implied.

Where it goes is the region COUNT. A 120-column diagonal band claims a rectangle per
run of equal alpha per row, and a smooth full-range fade over 120 columns moves ~2 per
step, so almost every run is one cell: ~120 regions a row, ~3,000 for a band. Each is
72 bytes, each is copied by `shifted(byX:y:)` at every composite between the leaf and
the root, and that is both the +14.9% and the +1.3 MB.

**The next step, if it ever matters**, is to stop making the count grow with the area:
let one region carry a per-column alpha (`[UInt8]` across its width) so a row is ONE
region whatever its ramp does. `clipped` and `subtracting` would slice the array, and
`foldedAlphas` — which already walks a region's columns — would sample it. That turns
~3,000 regions into 24. It is not done here because +14.9% on a synthetic worst case
and 0% everywhere else does not justify a new field on a public type carried through
every composite; it is written down so the measurement that would justify it is
already on record.

### 36.3 A new scenario, because nothing measured this at all

`alpharamp` is 22nd in `Stress`. Every ramp in `gradients` is opaque, so §34's whole
subject — a ramp's alpha travelling beside its bytes — was invisible to `ab_bench.py`,
and §34.3 declined the per-cell shape on an *estimate*. That is the same hole
`gradients` itself was written to fill one layer up, and its own doc comment makes the
argument.

It also proves the gap was real rather than theoretical. Built against the previous
commit, in debug:

```
TUIkitStyling/Color+ANSICodes.swift:70: Assertion failed: a translucent colour
reached the ANSI emitter (alpha 45): the view that painted it does not carry alpha
to the compositor, so it renders opaque.
```

With the claims, all 22 scenarios render clean under `--selfcheck`.

### 36.4 `Table`'s decline was two declines, one of them stale

A `Table` gated its claim on `ramp.variesAcrossRow` — "does the colour change along
the row" — and dropped the ink claim wholesale when it did. That is broader than
`perCell`: a HORIZONTAL ramp varies along a row too, and §34.2 had already made that
shape honourable everywhere else. So half the decline was a cost decline and half was
exactly the kind of stale one §33.1 caught §19.1 being.

Both arms now claim, through the same `alphaClaims` the text path uses, and
`bandsAcrossRow` governs only the PAINTING — whether the row gets one SGR introducer
or one per cell, which is what it was always about.

### 36.5 `Text`'s concatenated arm dropped two things, not one

`PaintRenderer.styled(pieces:)` returned `[String]`. The same structural blocker as
`TrackRenderer.render` (§31) and for the same reason, and it cost two different claims:

- **the ramp's alpha** over the fragments it painted — the case §16.3 listed;
- **each fragment's OWN colour**, which is the stranger half. The very same colour on
  an *unramped* concatenation was claimed by `Text.fragmentAlphaClaims` two branches
  up. Putting a gradient on a concatenated `Text` silently discarded the alpha of a
  fragment that had nothing to do with the gradient.

The one-stop-gradient arm is in the same position and now claims too: `RampSampler`
refuses a single stop, so `Gradient(colors: [.red.opacity(0.5)])` fell through to the
flat fallback and rendered at full strength.

With that, `band`'s `carriesAlpha: Bool` has one value everywhere and is gone. It
existed for the arm that dropped its alpha rather than claiming it — bytes in raw so
the emitter stays loud — and a flag with one value is a place for the next caller to
guess wrong.

### 36.6 The circular `Gauge`, and a fourth copy of one accumulator

The four emit sites §31.4 found bypassing `TrackRenderer` entirely: the tiny pie dial's
glyph, and the ring dial's rim, walls and value. A translucent `.tint` reached all four.

They are the same job `DrawnTrack` was doing for a track — bytes and claim flushed
together, so the two halves of a translucent paint cannot drift — so `DrawnTrack` moved
out of `TrackRenderer.swift` and became `ClaimingRow`. It gained one thing in the move:
the claim is merged into the previous one where the two are adjacent and owe the same
alpha, because a rim drawn a cell at a time is one colour for most of its length and
twenty rectangles where two will do is twenty the resolver walks per row.

The merge rule itself is now in one place (`Array.appendCoalescing`), which three
callers share: `ClaimingRow`, `Text.fragmentAlphaClaims`, and the pieces arm above.

**It also invalidated three assertions, and that is worth recording.** `TrackAlphaTests`
pinned claim COUNTS — "one per cell", `count == 2`, `width == 2` — and every one of
them changed while nothing about the alpha did. The number of rectangles a row needs is
an implementation detail; what a row owes is an alpha per column. The three now read
that instead: the covered columns, the monotonic run of alphas, six cells for three
double-width glyphs. Better tests, arrived at by breaking worse ones.

### 36.7 The indeterminate bar: decline the RUN, not the alpha

§31.4 declined the sweep because "its whole row is one `AnimatedCellRun`, and a sweep
*moves*: a given column is lit in some frames and unlit in others". True, and it stops
one step short of the answer. The thing that cannot carry the alpha is the run — so
the run is what goes.

A pre-rendered cycle is an OPTIMISATION. These bars used to ask the run loop to
re-render them thirty times a second, and `AnimatedCellRun` took that off the render
path. A translucent bar gives it back: one frame per render, each with its own exact
claim, at the cycle's own sampling rate. `Spinner` already does precisely this for a
cycle whose frames are not all one width — the run cannot express it, so the run is
not used — and the precedent was in the tree the whole time.

The condition is asked of the INPUTS, not of a built frame: a frame paints only the
colours it reached and the next one may reach another. `isOpaqueThroughout` reads the
three palette colours and the style's own gradient stops, which makes it conservative
in one direction only — a translucent colour that is never actually painted costs the
bar its pre-rendered cycle, and nothing else.

Two things fall out of routing the frames through `ClaimingRow`:

- `IndeterminateRenderer.laid` was already the single funnel every motion's cells pass
  through — five motions, one place that turns a colour into bytes — so there was
  exactly one line to change.
- The claim is a run per equal alpha, which is the shape a moving ramp actually has:
  `.sweep`'s trail ramps from the control's opaque empty colour to a faded accent, so
  the alphas descend across the row and the tint's own alpha is the floor.

What drives the declined bar is the scheduler, so its frame comes from the frame clock.
Until §66 it came from the cursor timer, which nothing kept running on such a page, and
the bar did not move.

### 36.8 §33.3's hole was two mistakes, not a limitation

`_ListCore`'s focused path is testable headlessly. Both reasons the earlier attempt
failed are ordinary:

1. **The focus manager was never in the environment.** The context came from
   `RenderContext(availableWidth:availableHeight:tuiContext:)`, which leaves
   `environment.focusManager` nil — so the rows registered with nothing and no number
   of render passes or `focus(id:)` calls could focus one. It has to be put there the
   way the render loop does, which `WindowedFocusReachTests.renderFrame` had already
   shown three files away. Two passes are still needed: the first is what registers,
   and a row cannot be focused before it has said it exists.
2. **The selected row was not the cursor row.** `_ListCore` computes a row's
   `isFocused` as `handler.isCursorRow(rowIndex) && listHasFocus`, so the raw-accent
   branch of `RowSelectionIndicator.forRow` needs the selection to be ON the keyboard
   cursor. Selecting row 1 while the cursor sat on row 0 rendered the *unfocused* mark
   — which is a composite through `opacity(_:over:)`, therefore opaque and correctly
   unclaimed.

The second is the one worth remembering. The first is a wiring mistake that a failing
test reports honestly; the second produces a *passing-looking* render whose every
visible feature — a `●`, a highlighted row — says "focused". §33.3 was right to refuse
it as an assertion and wrong about why it could not get one.

Three assertions, and the third is what makes the pair mean anything: the claim, the
mark's bytes at their opaque spelling, and the same focused render with an OPAQUE tint
claiming nothing. Without the third a broken claim derivation would still pass; without
the first two a broken focus would.


## 37. The four surface derivations, and the defect underneath them (2026-09-10)

§28.2 recorded that `fieldBackground`, `fieldBackground(on:)`, `liftedBackground` and
`lifted(from:)` drop a faded slot's alpha, and left the question open. This is the
detail of *why* they drop it, what the four actually return, and the separate defect
that turned up when the question was asked properly.

### 37.1 The alpha is not decided away, it is structurally absent

All four end in `Palette.surface(steppedFrom:separation:)` → `surfaceWalk` →
`scaled(_:by:)`, and `scaled` rebuilds the colour from **`base.rgbComponents`, which is
a three-tuple**. There is no fourth element to read and `Color.rgb(_:_:_:)` is opaque
by construction, so the alpha is not weighed and discarded — it never enters the
arithmetic. That is the whole mechanism, and it is why this is a different kind of
"drop" from a composite's: `opacity(_:over:)` **spends** an alpha against a stated
ground and the opaque result is the answer; a lightness step simply cannot carry what it
never reads.

`scaled` has four exits, and measured against a page at `.rgb(0, 0, 0).opacity(0.5)`:

| exit | when | alpha |
|---|---|---|
| `Color.rgb(channel×3)` | the ordinary step | gone (opaque by construction) |
| `lerp(channels(fits), white)` | brightening would clip a channel | gone (both operands opaque) |
| `lerp(base, white/black)` | a page with nothing to scale | **partial** — `lerp` carries alpha as a fourth channel, so 128 → somewhere between |
| `return base` | a semantic colour (cannot happen; these are resolved) | carried |

So "the four drop it" was true of every reachable path *and* the fourth exit would have
interpolated it to a value that is neither carried nor spent — the same shape as
§28.1's alpha-184 hover lift. That exit is now spelled opaque explicitly, so the four
derivations give ONE answer. **Whether that answer is right is still the project
owner's call**; that they must agree is not.

### 37.2 The defect: a black page got no surface at all

The exit that has to mix detected its own case with `scaled == base`. `Color` is
`Hashable` over its value **and** its alpha, so that comparison answers "different" for
two colours that are the same colour, and the branch was unreachable for two pages:

- **`.rgb(0, 0, 0).opacity(0.5)`** — the rebuilt colour is opaque, so 255 ≠ 128.
- **`Color.black`** — that is `.standard(.black)` and the rebuilt one is `.rgb`, so the
  CASE differs *at full opacity*. This half was never about alpha at all, and
  `var background: Color { .black }` is the obvious thing for a custom palette to write.

Measured, before:

| page | `fieldBackground` | `liftedBackground` |
|---|---|---|
| `.rgb(0,0,0)` | `rgb(31,31,31)` | `rgb(20,20,20)` |
| `.rgb(0,0,0).opacity(0.5)` | **`rgb(0,0,0)`** | **`rgb(0,0,0)`** |
| `Color.black` | **`rgb(0,0,0)`** | **`rgb(0,0,0)`** |

Every surface equal to the page — a field, a tab body and a well all invisible, which
`surface(steppedFrom:separation:)`'s own note calls "the same as drawing none" — and
arrived at through **three `surfaceWalk`s of up to 175 steps each**, since a candidate
that never changes never separates and pure black never saturates at white.

Asked of the CHANNELS instead, both step. No built-in palette is affected: all sixteen
state `.rgb` backgrounds, and the two pure-black ones (Homebrew, Pro) were already
reaching the mix. What is fixed is every custom palette that wrote `.black`, or faded
its page.

### 37.3 What is still open, stated as a choice

A well stepped off a half-transparent page could reasonably be:

- **equally transparent** — one wash all the way down, so the terminal's own background
  shows through the whole theme evenly; or
- **deliberately solid** — a field you can read in, which is what a well is *for*.

It changes the chrome depth of every faded theme, and it is a design decision rather
than a derivation. No paint site migrated in §16–§36 reaches these four, so nothing is
silently wrong today. `FadedPaletteDerivationTests.surfaceStepsDropIt` pins the current
answer and says in its own doc comment what to do if it changes: delete it and move its
rows into `respellingsCarry`.

Worth noting that §32's `supportsOpacity` makes the question more reachable than it
was: a palette editor bound to `background` can now author a translucent page with two
keystrokes.


## 38. What the second pass cost, end to end (2026-09-10)

`ab_bench.py`, `172599ec` → `1158a96d`, the full sweep plus `translucent`, 20 reps,
load 1.29 on an otherwise quiet box:

| | scenarios |
|---|---|
| **faster** | `deep` −0.7%, `fanout` −0.8%, `anyview` −0.7%, `modifiers` −0.4% |
| **slower** | `customlayout` +1.9% [+1.2, +2.4], `churn` +0.2% [+0.0, +0.5] |
| indistinguishable | the other fourteen |

RAM flat everywhere (±0.1 MB). The four faster ones are `foldedAlphas` calling
`substituting` once per region instead of once per region per column, which is what
`.opacity` on a subtree pays for.

Re-measured at 60 reps, per §35.2's own rule about believing a flagged width:

| scenario | 20 reps | 60 reps |
|---|---|---|
| `customlayout` | +1.9% [+1.2, +2.4] | **+0.7% [+0.3, +1.3]** |
| `churn` | +0.2% [+0.0, +0.5] | indistinguishable |

So `churn` was measurement and `customlayout` is two-thirds measurement with a
residual. **The residual has no path in it.** `customlayout` renders two `Text`s and
a custom layout: no gradient, no table, no indeterminate bar, no dial, no palette
surface, and no `opacityRegions` at all — so every function this pass changed is
either not called or returns at its first guard. That is the signature of codegen
layout rather than of work, which this project has seen before and mistaken for a
regression once already (see `Documentation/Performance-profile-2026-08.md` on the
"3% regression" that was `_MemoizedRow`'s stored-property order).

Left as measured rather than chased: +0.7% on one scenario with no changed path in
it, against −0.4% to −0.8% on four with one, is not a cost to optimise — it is a
number to write down so the next person who sees it does not go looking twice.

The `alpharamp` figure (§36.2, **+14.9%**) is the one real price, and it is charged
only to pages that ask for translucent ramps.


## 39. A surface stepped off a faded page is faded (2026-09-10)

§28.2 and §37 left one question open and it is now answered: **carry it.** A user who
fades the page has said what they want, and both other answers override it — a solid
well or a composited one substitutes the framework's judgement for the theme's.

The change is one exit. `Palette.scaled(_:by:)` is split so that the arithmetic works
on the three channels that exist (`stepping(_:by:)`) and the one caller re-attaches the
alpha:

```swift
private static func scaled(_ base: Color, by factor: Double) -> Color {
    stepping(base, by: factor).carryingAlpha(of: base)
}
```

One exit rather than four, because the four disagreed by construction and one of them
— the `lerp` that mixes a page with nothing to scale — carries alpha as a fourth
channel and would have interpolated 128 toward 255. That is §28.1's alpha-184 hover
lift, and it is the second time the same shape has appeared at a `lerp`.

`quietest`'s synthesised grey needed the same treatment: it is a stand-in for the page,
walked the same way, so it is built `carryingAlpha(of: base)`. Built opaque, the neutral
branch handed back an opaque surface where the hued branch carried one — the two
answers to one question disagreeing about a third thing.

`FadedPaletteDerivationTests.surfaceStepsDropIt` is deleted and its four rows moved into
`respellingsCarry`, which is exactly what its own doc comment said to do if this was
ever answered this way.

### 39.1 Two paint sites the answer broke, and what they were

The argument for leaving the surfaces dropping had been "no migrated paint site reaches
them, so nothing is silently wrong today" — an argument from inspection. Carrying tests
it, and two sites paint a derived surface without claiming:

- **`FieldChrome`'s caps.** The `▐`/`▌` half-blocks are painted in the field surface
  (or the surface lerped toward the accent while hovered), and `FieldChrome` held them
  as finished strings with nowhere to say what they owed. It now keeps `capColor` beside
  the bytes and answers `claims(lineWidth:)`, because the TRAILING cap's column is
  `lineWidth - trailingCells` and this is the type that knows what that is —
  `TextField` and `SecureField` would each have re-derived it, which is how those two
  drift. The combo box's `▾` goes through `ClaimingRow` in the same commit: its ink is
  `foregroundSecondary` and its field is the same surface.
- **A compact `TabView`'s panel.** `surfFill` pads each content row out to the panel
  width in the surface colour, and fills whole rows below short content. The pads are
  claimed SEPARATELY from the content between them rather than as one rectangle per
  line: the content was rendered `.background(surface)`, which already claims, and
  overlapping claims multiply — one rectangle across the line would fade the panel
  twice. A filler row, having no content, takes one claim.

The chips went through `ClaimingRow` for the reason §36.6 introduced it: a chip is
three runs (an ink-only cap, an ink-on-field body, an ink-only cap), so it owes three
claims, and the row that emits them is the thing that knows where each begins.


## 40. The second tier, asserted rather than inspected (2026-09-10)

§16.1 named a whole second tier beside its thirteen entry points: `Palette` is a public
protocol of plain `var …: Color { get }` members, nothing normalises what a custom one
returns, and one faded slot reaches every derived colour in the theme. §18 closed the
`border` role of it and §20 fixed the reason it reached nothing at all. The rest of it
had never been *rendered*: `FadedEverythingPalette` exercises the derivations
arithmetically, in the styling module, where there are no cells.

`FadedPaletteRenderTests` renders pages under a palette whose every slot is at alpha
128. It asserts by **not trapping** — a translucent colour reaching `ANSIRenderer` trips
a debug assertion, which is a trap and not a throw, so an unmigrated paint site takes
the suite down with a message naming the alpha. There is nothing to `#expect` and no
need for one: the run either completes or it does not.

It found six sites on its first run. Two were §39's own doing (`FieldChrome`'s caps and
a compact `TabView`'s panel fill — both consumers of a derived surface, which had just
started carrying). Four were **already there**, and had been since the second tier was
named:

| site | colour | why it carried |
|---|---|---|
| `_TableCore.renderHeader` | `foregroundSecondary` | a re-spelling of `foreground` |
| `_PickerMenuCore.collapsedLine` | the label, through `ensuringRenderedContrast` | a re-spelling, floored against the face |
| `ScrollbarRenderer.styledCell` | `ScrollbarColors.track(in:)` | derived from `foregroundQuaternary` |
| `_ListCore`'s empty bar cell | the same track colour | the same |

### 40.1 Two of the four, and what shape they took

`renderHeader` returned a `String` — the same structural blocker as `TrackRenderer` and
`PaintRenderer.styled(pieces:)` — and now returns a `ClaimingRow`, which is also what
gets the gutter and the inter-column spacing right without a second piece of
arithmetic: `skip(cells:)` for what the header does not paint, `append` for what it
does, and adjacent cells owing one alpha coalesce to a single rectangle across the
titles. `_TableHeaderView` gains a `claims` parameter, the twin of the one
`_TableContentView` got in §33.

The analytic MEASURE path passes `claims: []` deliberately: it reports a size and draws
nothing, and a claim describes cells that were never on screen.

`_PickerMenuCore.collapsedLine` goes through `ClaimingRow` too, which puts the label's
claim past the opening cap without arithmetic. Only the label can be translucent there —
`buttonBg` and the caps are composites that spend their alpha (§29), and the label ends
in `ensuringRenderedContrast`, which is a re-spelling that carries it.

### 40.2 The scrollbars are open, and this is the shape of the work

A bar is `[String]` — one styled single-cell string per line — built by
`ScrollbarRenderer.verticalScrollbar` / `horizontalScrollbar` and handed to **nine call
sites** that each place it at a column of their own. `styledCell` is the one place a
bar cell becomes bytes, so it is the one place the claim belongs; but a claim in
bar-local coordinates has to be shifted by each caller, which means the bar becoming a
claim-bearing type rather than an array of strings — exactly the conversion
`TrackRenderer.render` made in §31 when it stopped returning a bare `String`.

That is its own commit, with its own nine call sites and their tests, and it is not
folded in here. The test hides the scrollbars with `.scrollIndicators(.hidden)` and says
so at the line, which is the difference between a gap that is recorded and one that is
papered over.

**Closed in §43**, which found the shape right and the count low: seven hosts drawing a
bar, but also four padding cells that were emitted every frame whether or not any line
used them — and would have kept trapping with every bar converted.

### 40.3 What the test does and does not prove

It renders a spread — fields, a tab view, a toggle, a slider, a list, a table, a box, two
progress bars, two gauges and a picker — and a spread is not a proof. A faded palette
reaches every chrome-painting view in the framework, and the ones not on that page are
untested rather than known-good. What the suite now has is a **place to add the next
one**, and a failure mode that is a stack trace rather than a wrong colour on somebody's
screen.


## 41. The image glyph path, part one: the two bugs the flatten was hiding (2026-09-10)

§17 named four things the glyph path drags with it, and said two of them are
**pre-existing bugs that the unconditional `flattenedOverBlack()` currently hides**.
Each has to be fixed before the flatten can go, and each is its own commit, because
each is wrong on its own terms and testable on its own.

### 41.1 `boxReduced(by:)` averaged straight colour and alpha independently

`scaledBilinear(to:_:)` premultiplies, and its own loop says exactly why: a transparent
pixel's colour is meaningless, the decoder writes every fully transparent pixel BLACK,
and giving it full weight pulls its opaque neighbours toward black — a dark fringe one
pixel wide around every PNG with a transparent surround.

`boxReduced` is the third resampler and had the same hole. Half a block of white at
coverage 255 and half at coverage 0 came out **grey at coverage 127**, where the answer
is **white at coverage 127**. The colour is now averaged premultiplied and divided back
out by the total coverage, which is the alpha-weighted mean `Σ(cᵢ·aᵢ) / Σaᵢ`; a block
with no coverage at all has no colour to recover and stays fully transparent.

**Byte-identical on the opaque path, and written to be.** With every coverage equal the
weights cancel — `255·Σrᵢ / (255·count)` floors to exactly what `Σrᵢ / count` did — so
no rounding term was added, deliberately, and `opaqueBoxReductionIsUnchanged` pins it.
That matters because every image reaching this function today has been flattened first:
the fix cannot move a single pixel of anything currently on screen, which is what makes
it safe to land ahead of the change that will actually exercise it.

### 41.2 The dither carried a transparent pixel's error at full strength

Floyd–Steinberg ignored coverage entirely: a pixel at alpha 0 pushed its neighbours
exactly as hard as one at alpha 255. The carry is now scaled by `a / 255` — full
coverage carries all of its error as it always did, and no coverage carries none.
The OKLab carry takes the same factor, as a `Double`, at the one line that computes it.

Measured on one mis-quantised pixel and its neighbour, a flat grey whose own
quantisation is exact so that everything it moves by came from the carry:

| coverage | neighbour before | after |
|---|---|---|
| 255 | 148 | 148 |
| 192 | 148 | 138 |
| 128 | 148 | 135 |
| 0 | 148 | **128** — its own colour, untouched |

Byte-identical at full coverage by construction (the weight is returned unchanged
rather than multiplied and divided), which is what lets this land ahead of the flatten's
removal without moving any image on screen today.

**§17's "dark fringe" is smaller than it claims, and the correction belongs here.** The
stated mechanism was a transparent pixel diffusing its own error outward. A test for
that could not be made to fail on the unfixed code at either palette, and the reason is
worth keeping: a transparent pixel's colour is BLACK, black is in every palette, so its
own quantisation error is ~0. What it re-emits is the carry it just RECEIVED from a
visible neighbour, attenuated by 7/16 and then 3/16 — about 13% of an error that error
diffusion is already dissipating. The visible artefact came from the resamplers
(§41.1); this one is real, principled, and small.

Worth knowing about the symptom too: `.ansi16` absorbs the whole carry into one entry,
so a test written against it passes whatever the arithmetic does. The finer the
palette, the more of this leaks — which is the opposite of the intuition that a coarse
palette is where dithering artefacts live.


## 42. The image glyph path carries alpha (2026-09-10)

§17's last open item, and the only entry point of §16.1 that was still unhonoured.
`ASCIIConverter` called `flattenedOverBlack()` on every image before converting it, so
every renderer saw an opaque picture and a logo with a transparent surround came out as
an explicit black rectangle: invisible on a dark theme, glaring on a light one. The
flatten is gone.

### 42.1 `convert` returns a picture, not lines

`convert(_:width:height:) -> [String]` was the structural blocker, the third time in
this document that a `String`-returning function has been one (`BorderRenderer` §18.3,
`TrackRenderer` §31, `PaintRenderer.styled(pieces:)` §36.5). A cell's colours are chosen
from pixels that may be partly or wholly transparent, and a string has nowhere to say so.

`ASCIIArt` carries the lines and the coverage: **runs**, not cells, because an image's
alpha is mostly large uniform areas — a logo's transparent surround is one run per line,
and a photograph is none at all. `[]` for a fully opaque picture, the same contract
`Text.uniformAlphaClaims` states and for the same reason. `CoverageMap` coalesces as the
cells are emitted, and drops fully opaque ones rather than recording them, which is what
keeps an opaque picture's list empty without any caller testing for it.

`_ImageCore` turns those into `OpacityRegion`s through `ASCIIArt.claims`.

### 42.2 The two things §17 said this would drag, and a third

**The half-block coalescing gained an alpha term**, as predicted. Two pixels of one
colour are emitted as a SPACE with only a background — 86.5% of a photograph's cells at
sixteen colours, and load-bearing for the Warp contrast-lift banding — but two pixels of
one colour at DIFFERENT coverages are not one field: collapsed to a single background the
cell would resolve at one of the two and the other half would be wrong. So the test is
`background == below && upper.a == lower.a`, and the optimisation stays.

**The two pre-existing resampler bugs** were fixed first, in their own commits (§41).

The third was not predicted: **a half-block cell paints its two halves from different
pixels, so one can be there and the other not.** The renderer only ever had
`▄`-over-a-background because the flatten meant every cell had both halves. It now has
four cases:

| upper | lower | cell |
|---|---|---|
| absent | absent | a space stating NO colour — the surround that was a black rectangle |
| absent | there | `▄` in the lower colour, no background |
| there | absent | **`▀`** in the upper colour, no background — the glyph flips |
| there | there | as before: a space on a background when they agree, `▄` over it when they do not |

The mono variant has had all four glyphs since it was written. The colour one needed only
two, and that was the flatten's doing.

### 42.3 Coverage is not colourlessness, and conflating them blanked everything

`CellColours.color(for:)` is documented as "the one place the question is answered", so
it was the obvious place to return `nil` for a transparent pixel — and that is right. What
was wrong was then testing `color(for:) == nil` to decide whether to draw a GLYPH:
`nil` also means "this MODE paints no colour", which is `.mono` and every no-colour
terminal. Every mono and colourless render came out blank, across eleven test files.

The glyph decision asks the pixel's coverage directly; the colour question stays with
`colours`. Two questions, two tests, and the failure was loud and immediate — which is
the argument for having had those eleven files' worth of assertions in the first place.

### 42.4 Where coverage decides a glyph rather than a colour

§6a's rule is that alpha is honoured exactly for COLOURS and becomes a decision for
glyphs, at the ½ threshold. Four renderers make glyph decisions and all four now ask it:

- **braille** lights a dot only at coverage ≥ ½ (a transparent dot used to light itself
  from whatever colour the encoder left in it);
- **mono** — `isMonoInk` — the same, and it is the *only* glyph gate coverage reaches in mono (the split that gate compares against
  read no coverage at all until §72.2), which
  paints no colours at all and therefore has no claim to make (true of the CONVERTER, and
  read for two months as though it were true of mono as a whole: `_ImageCore.inked` stamps
  mono's ink and paper over the converter's output afterwards (the view's `.foregroundStyle`
  and `.backgroundStyle`, the theme's two colours where unstated), and had a claim to make.
  See §70.2 — and over the cells nothing of the picture reaches, it had paper to
  withhold: §70.5);
- **the ramp charsets** draw a space in no colour where there is no coverage, rather than
  whichever glyph the straight colour's luminance names;
- **the shape matcher** weights its darkness samples by coverage: an uncovered sample is
  not dark, it is absent.

Braille and the shape matcher also average their cells' colours **premultiplied**, for
the reason §41.1 gives — eight dots is a small enough neighbourhood that one transparent
corner visibly darkened a whole cell.

### 42.5 `flattenedOverBlack()` is deleted

Its documentation named exactly one purpose — "for the glyph renderers, which read a
pixel's colour and never its alpha… this is that accident made deliberate" — and that
purpose is gone. A public function whose only stated rationale no longer holds is worse
than no function: the next reader would assume it is load-bearing. Pre-1.0, per
`CONTRIBUTING`, the old spelling goes rather than lingering as a shim.

### 42.6 What this does NOT do

`.opacity(_:)` on an `Image` still behaves differently per path — the glyph path fades,
the pixel path declines, because fading a real picture means re-transmitting up to
megabytes per phase. `OpacityResolution` declines it deliberately and should keep
declining it.

And the **pixel** path was already correct (§17): alpha survives the tone curve,
sharpening, dithering, quantisation and the mono recolouring, and is transmitted as
`f=32`. Nothing there changed. (True of alpha SURVIVING that path; not of what the path
measures from the picture on the way through, which did not read it — §72.)

With this, **§16.1's ledger has no open entry points at all.**

### 42.7 What it cost, measured

`ImageHarness`, 120 × 50 cells, best of nine, against `23b321e9` — the commit before
this one, so the two resampler fixes are already in the baseline:

| path | before | after | |
|---|---|---|---|
| glyph, `ansi256` | 0.484 ms | 0.485 ms | +0.2% |
| glyph, `truecolor` | 0.497 ms | 0.510 ms | +2.6% |
| glyph, `grayscale` | 0.226 ms | 0.232 ms | +2.7% |
| glyph, `mono` | 0.148 ms | 0.161 ms | **+8.8%** |
| pixel | 4.313 ms | 4.289 ms | −0.6% |
| recolour | 2.463 ms | 2.440 ms | −0.9% |

**The checksums are identical in every glyph mode**, which is the assertion that an
opaque picture's output — lines and empty coverage both — did not move.

`mono` is the largest because it is the cheapest: 25 ns a cell, and `isMonoInk` gained
one compare per PIXEL (two per cell for half-blocks). There is no way to know whether a
pixel is there without asking. The others pay for two coverage tests and a `switch` where
there used to be a straight line.

`CoverageMap.note` is `@inline(__always)`, and that was worth 3.7 points on `ansi256`
alone: unannotated it was a non-inlined call per cell whose whole body, for an opaque
picture, is its first `guard`. This module counts retain/release pairs in its inner loops;
a call that does nothing is not free here.

None of it is per-frame. `_ImageCore` keeps an `ImageRenderCache` keyed on the source, the
size and every conversion parameter, so a picture is converted when something about it
changes and served from the cache otherwise.


## 43. The scrollbars claim (2026-09-10)

§40.2 left the scrollbars open and said what the work was: a bar had to stop being
`[String]`. That was right, and it was not all of it.

### 43.1 A bar is a column, so its type is the row transposed

`verticalScrollbar` returns a `ClaimingColumn`: one finished single-cell string per line,
and the claims in the bar's own coordinates — column 0, row N for line N. It is built
*out of* `ClaimingRow`: every cell goes through `ClaimingRow.append`, so the opaque
spelling and the claim are still derived in one statement, in one place.
`horizontalScrollbar` returns a `ClaimingRow` outright, because a horizontal bar is a row.

`styledCell` was the one place a bar cell became bytes, which made it the one place the
claim belonged and the one place with nowhere to put it. It is now
`paint(of:thumb:track:)`, which returns the glyph and its two colours rather than bytes —
and the two colours are the point: a fractional end cell draws its glyph in one of thumb
and track and its field in the other, which way round depending on the edge it is
anchored to. `.blockFine`'s boundary cell (§31.1) again.

Two pieces of the shared machinery grew:

- **`appendCoalescing` merges downward as well as across.** A bar is drawn a line at a
  time, one cell per line, so its track is one rectangle only if a merge can stack.
  Without it a bar as tall as the page states a region per row, and the resolver's fold
  (§36.1) scans every region for every row — quadratic in the bar's height. The
  row-at-a-time callers (`ClaimingRow`, `Text.fragmentAlphaClaims`,
  `PaintRenderer.styled(pieces:)`) state every claim on one row, where two claims can
  never be stacked, so it changes nothing for them.
- **`ClaimingColumn.fit(toCount:field:)`.** Every host pairs the bar with lines of its
  own, one for one, and the two counts are not always equal. It pads with blank cells in
  whatever the host used to pad with — plain track for `List` and `Table`, an unpainted
  space for the popup and the editor — and it *cuts* the claims with the lines they were
  for: a popup showing fewer rows than its bar is tall must not leave a claim over its
  bottom border.

### 43.2 The trap that was not in the bar

`Table` (twice), `_ListCore` and `ScrollView` each built an `emptyCell` —
`ANSIRenderer.colorize(" ", background: track)` — eagerly, every frame, to pad any line
past the bar's end. There is essentially never such a line: each host clips or pads its
lines to the bar's height first, and in `ScrollView` it cannot happen at all. But
`colorize` ran regardless, so under a faded palette the emitter's assertion fired from a
cell nobody drew, and **converting the bar alone would have left all four trapping**.
They are gone; `fit` pads — claims and all — only when there is something to pad.

### 43.3 Seven hosts, and where each one's claim goes

| host | column | row | |
|---|---|---|---|
| `ScrollView`, vertical | `contentWidth` | 0 | the memo keeps the column, claims included |
| `ScrollView`, horizontal | 0 | the appended last row | the corner is appended to the same row: a field and no ink |
| `TextEditor` | `contentWidth` | 0 | its first claims of any kind; its rows' came in §61 |
| `List` | `contentRowWidth` | 0 | not slid |
| `Table`, single-line | `contentInnerWidth` | 0 | not slid |
| `Table`, multi-line | `contentWidth` | 0 | not slid |
| drop-down popup | past the wall and the fitted content | 1 | in both arms |

Two of those notes are the ones that could have gone wrong quietly:

- **The rows' claims slide; the bar's do not.** `List` and `Table` move their rows under
  overscroll (§1.5 of the anchoring spec) and slide the rows' claims with them, while the
  bar stays exactly where it is. The bar's claims are added after the slide, not fed
  through it. (For a `List` that held of the claims the list paints itself. Its rows'
  content claims ride the row ranges, and a push past the bottom paired those with the
  wrong rows until §51.)
- **The popup claims its bar in the breathing arm too.** That arm states none of its
  border's claims, because the border's alpha moves with the breath and a claim is one
  alpha for every frame the line runs replay. The bar does not breathe — its colours are
  the same in every frame — so its claim is true of all of them. Left inside the same
  gate, it would have gone missing whenever an open menu's highlight pulsed.

### 43.4 The focused bar keeps its runs, and says what that assumes

A focused bar breathes through `AnimatedCellRun`s: the whole bar rendered once per frame
of the cycle, and the rows that differ kept as runs. A run replays BYTES — opaque
spellings now — and the claim under it is the drawn bar's, applied to every frame at one
alpha per cell (§29.2). So the runs are right only if every frame owes exactly the
claims the drawn bar does.

That is written down as `assertFramesOweOneClaim`, a debug assertion over every frame's claims.
The drawn bar is one of the frames — its colour is `colorNow`, which indexes the same
cycle `ScrollbarPulse.frames` maps — so the check is exact, not a sample.

It did not hold on every palette, and the assertion is how that was found: §44.

### 43.5 What the test asserts

`FadedPaletteRenderTests` draws every host's bar, no longer hiding them, and asserts more
than that somebody claimed. A bar's arrows say exactly where it is, so each arrow's cell
is checked for owing the arrow colour's alpha as ink and the track's as field — the fold
the resolver makes for that one cell. The corner is checked for owing a field and no
ink; the editor, which draws no arrows, for claiming nothing off the bar's column.

The popup's breathing arm and the editor are asserted under a palette that fades ONLY
the track. A breathing popup border under a faded accent was a gap of its own — silent,
not loud as this once said, since its frames go through `band` at their opaque spelling —
and its ends are spent since §64; an editor's well was another, claimed since §61.


## 44. The scrollbar's breath: a sixth copy of the pulse pair (2026-09-10)

§43.4's assertion tripped on its first render under a wholly faded palette: a focused
`ScrollView`'s pulse frames owed different claims. The bar was right. The breath was not.

A focused bar breathes between two colours: the accent, `separated` from its track, and
`pulseLift` — the accent *lifted* one visible step away from the page. Both are
re-spellings of one colour, and `separated` and `hoveredForeground` both end in
`carryingAlpha`. `pulseLift` has three exits. The first returns the hovered-foreground
lift, and carries. The loop and the fallback, taken when that lift is too close to the
resting accent to be seen, step toward an extreme through `compositing(_:over:)` — and
**`compositing` drops the colour's alpha**: only its `opacity` parameter enters the mix,
and it returns a fresh `.rgb` at 255.

The loop is not the edge case its comments make it look. They name Ocean and Man Page,
as the reason it exists. Measured, under a half-faded tint, **eight of the sixteen
shipped palettes take it** — Green, Amber, White, Grass, Homebrew, Pro, Red Sands and
Silver Aerogel — and so does a wholly faded palette. Ocean and Man Page do not: the
comments are the history of why the floor was added, not a list of who reaches it now.

So a faded accent breathed from 128 to 255, and the cycle between them interpolated
alpha as a fourth channel. §29's bug exactly, arriving by another route — not a
composite at the quiet end and a bare colour at the loud one, but a lift that was
written as a composite. Before §43 its bytes reached the emitter translucent and
trapped. Had the bar been converted without `assertFramesOweOneClaim`, the bytes would have been
opaque at every phase, and every frame but one blended at the wrong alpha in silence.

The candidate is a lift, so it carries: `resting.compositing(…, over: extreme)
.carryingAlpha(of: resting)`, at both exits. The extreme is a *direction*, not a
backdrop — nothing is drawn behind the bar in white — which is why the fix is at the
call site and not in `compositing`.

### 44.1 `compositing(_:over:)` ignores its own alpha, and nothing reaches that

Its two callers are these two lines. A translucent colour composited through it is
composited as if it were opaque, where `opacity(_:over:)` folds the colour's alpha into
the coverage. With both callers now carrying, nothing reaches the difference. It is
recorded rather than changed: changing it is a decision about a public primitive's
contract, with no caller to test the decision against.

### 44.2 §29.2's count was low

§29.2 said the pulse whose phases have different alphas had been "in four places, and
is now none". §29.3 found a fifth, in the caret. This is a sixth, missed because the
scrollbar had not been migrated then and so could not be tested.

`ScrollbarBreathAlphaTests` sweeps every shipped palette under a half-faded tint, and a
wholly faded palette, asserting that every phase of the breath — the thumb, the arrows
and the hovered arrow — carries the accent's alpha, for a pulse and for a blink. It also
asserts that some palette in the sweep takes the loop: a sweep that only ever exercised
the first exit could not fail. And the render that trapped is a test of its own.


## 45. A scroll track's alpha moved with its colour (2026-09-10)

`ScrollbarColors.resolvedTrack` is the palette's quietest rung, moved along a line until
it can be told from both the accent drawn on it and the page it sits on — toward the
page first, toward the ink when that runs out. It moves through `Color.lerp`, and `lerp`
interpolates alpha as a fourth channel. So a faded rung walked toward an opaque page
came back part-way opaque — 139, 149, … 255 across the twelve steps — and an opaque rung
walked toward a faded page came back part-way faded. The groove's alpha was a function
of how far it had to move, which is not something anybody asked for.

The moved rung re-spells the rung — the track's own documentation says the requirement
is met "here rather than in the derivation" — so it carries the rung's alpha:
`.carryingAlpha(of: base)` on each candidate, the answer §37 gave the surface
derivations for the same four-channel lerp. The floors are measured on the channels
alone, so this changes which colour comes back and never which step is chosen.

Only a custom palette reaches it. Every shipped palette is opaque in all four inputs, and
`.tint` changes only the accent, which decides *whether* the rung moves and never the
alpha it moves with. The bar's claims (§43) were already exact for whatever alpha the
track had; this changes what that alpha is, not whether it is claimed.

`ScrollbarTrackAlphaTests` walks a faded rung one shade off the accent over three pages
— opaque, faded, and light, so the walk runs both ways — asserting that each really
moved, since an unmoved rung proves nothing, and that each kept its 128. And it walks an
opaque rung toward a faded page, which must stay opaque.


## 46. What the scrollbar work cost, measured (2026-09-10)

`ab_bench.py`, CPU time per frame, 15 paired reps, release builds of `77f1b443` (before
§43) and `99d9bdfb` (after §45), over every scenario that draws a scrollbar. The change
column is the median of the paired ratios, not the ratio of the two medians, which is
why `table` reads +1.6% beside medians 0.6% apart.

| scenario | before | after | change | 95% CI | |
|---|---|---|---|---|---|
| `scrollfollow` | 779.0 µs | 787.4 µs | −0.0% | −1.0% … +2.4% | indistinguishable |
| `table` | 447.4 µs | 450.3 µs | +1.6% | −1.9% … +2.5% | indistinguishable |
| `table-multiline` | 367.0 µs | 372.8 µs | +2.0% | −1.2% … +2.5% | indistinguishable |
| `tables-scroll` | 1773.9 µs | 1763.2 µs | −0.1% | −1.8% … +1.9% | indistinguishable |
| `framedcolumns` | 583.4 µs | 585.9 µs | −0.1% | −2.1% … +2.4% | indistinguishable |
| `menus` | 2137.0 µs | 2127.3 µs | −0.5% | −1.5% … +0.5% | indistinguishable |
| `kitchensink` | 488.3 µs | 486.6 µs | −1.0% | −1.8% … +1.4% | indistinguishable |
| `megalist` | 420.7 µs | 421.8 µs | −0.0% | −0.8% … +0.5% | indistinguishable |
| `tables-vstack` | 725.6 µs | 721.1 µs | −0.2% | −1.1% … +0.3% | indistinguishable |

Peak RAM moved by at most 0.2 MB either way. The load average was 1.5 during the run,
which the harness flags: CPU time absorbs preemption, not cache contention.

On an opaque palette the conversion adds, for every cell of a vertical bar, a
`ClaimingRow` whose claim comes back `nil`, and per frame a `fit` that pads nothing; the
pulse's frames each build a column where they built an array, and `assertFramesOweOneClaim` is a
debug check. None of it resolves above this machine's floor. `table` and
`table-multiline` lean positive, with intervals that include zero and sit inside the
±1.7% `table` null-tests at.

What is NOT measured is a bar under a faded palette. No scenario renders one, so the
cost of the claims themselves — a handful of stacked rectangles per bar, which is what
the downward merge in §43.1 exists to keep a handful — is argued, not timed.


## 47. The navigation bar's crumbs: one paint site, three arms (2026-09-10)

`NavigationStack(path: [1])` under a wholly faded palette trapped. Of everything in the
bar, one paint was raw: `_NavigationCrumbLabel`'s `drawn`, which handed
`palette.foregroundSecondary` to `ANSIRenderer.render` as it came. The rest was already
honoured — the separator and the current screen are `Text` (§16.3), the rule is a
`Divider` (§19), and the Back button is the plain style, whose label claims and whose ●
spends.

### 47.1 At rest, the crumb claims

A still crumb is drawn once and nothing replays it, so its colour carries its alpha: the
bytes state the opaque spelling and one claim covers exactly the crumb's cells, its lead
blank included, as `Text` claims its own blanks. The pointer's lift carries its base's
alpha (§28.1) and is claimed the same way. A disabled crumb is unchanged — it was already
a composite over the page (§31.3), opaque, and claims nothing.

### 47.2 Focused, both ends spend

The breath ran between the resting rung and the accent: two slots, each with an alpha of
its own. Under a wholly faded palette every frame was translucent and building the run
trapped. Under a faded `.tint` alone the resting end was opaque and the accent was not, so
the frames' alphas moved with the phase — §29's pair, a seventh time.

Both ends now SPEND against the surface the crumb is drawn on (`enclosingSurface`):
`spendingAlpha` on each, which is `ButtonCapCycle`'s shape. Not
`BorderRenderer.breathEnds(from:on:)`, which breathes one colour against a dimmed copy of
itself and would lose the accent. Every frame is opaque and the run owes nothing.

A still focus (`.selectionIndicatorStyle(.none)`) is drawn spent too, as the plain
button's ● is (§30.3). That is the one place this departs from "a still paint claims",
and it is deliberate: focus then shows one bright colour whether it animates or not.

### 47.3 One breath, not two ramps

The crumb had its own copy of the focused arm — `colorNow` for the colour drawn now and
`run(dim:bright:)` for the frames — which built the identical pulse ramp twice. It now goes
through `BreathingLabel.draw`, the breath a `Link` and a plain-style button already used,
lifted out of the private button-style body that kept it from anyone else.

### 47.4 What focus changes about the blend

At rest the crumb resolves against the real backdrop at composite time; focused, its ends
are spent over `enclosingSurface`. The two agree unless something other than that surface
is behind the bar — a `ZStack` sibling, or a surface that is itself translucent, whose
colour the spend uses as though it were opaque. Every §29 spend site makes the same
approximation. `Link` spends even at rest, to guarantee continuity (§30.3); the crumb takes
the other side of that trade, so that a still crumb honours what is really behind it.

### 47.5 The tests

The bar is checked cell by cell under a palette whose rungs fade by DIFFERENT amounts:
under a wholly faded palette every slot owes 128, and a claim taken from the wrong slot
would pass. The breath is checked by its bytes — spent over the page under a faded palette
and under a faded tint, and over a set surface rather than the page. The disabled test
passes before and after the fix, and says so: it guards §31.3's choice rather than
covering this one.


## 48. A swatch's breath, and the field its frames stated (2026-09-10)

A focused colour swatch marks itself with a bullet in its centre cell, breathing between
two readable colours: `readableText(on: fill)`, and that colour dimmed over the fill. Two
faults, one in each half of the run.

### 48.1 The ends disagreed about alpha

`readableText(on:)` picks the palette's foreground or background and floors it for
contrast, which carries that slot's alpha; the dim end was `opacity(_:over:)`, which
spends it. Under a faded palette the breath ran from an opaque colour to a translucent
one — §29's pair, an eighth time, and reachable only through the palette, which is why
every `.tint` sweep missed it: `readableText` never reads the accent. Both ends now go
through `breathEnds(dimmedTo:over: fill)`, the helper §29 made for exactly this; the fill
is the cell the bullet is drawn on.

### 48.2 The frames stated the fill as their field

Each frame was `colorize("●", foreground: colour, background: fill)`. With a translucent
fill that put the fill's alpha into the emitter on every tick, whatever the palette. §26's
"the swatch needed nothing" was true only of the still paint: `swatchFades` renders with
no focus manager, and so never built the run.

The fix is NOT the fill's opaque spelling. `.background` paints nothing at alpha 0, so an
opaque-spelled `.clear` would have painted black behind the bullet on every tick, with no
claim to catch it. The frame now states no field at all: a spliced frame is painted over
the background the line already has, and the resolver takes a run frame's field from the
line it replaces — so the frame gets exactly what `.background(fill)` drew, the same in
every frame, or nothing.

### 48.3 What stays approximate

On a translucent fill under a faded palette, the focused bullet is spent over the fill's
opaque RGB, while the selected — still — bullet carries and claims, so the two can differ
slightly. They agree whenever the fill is opaque. Every §29 spend site makes this trade.


## 49. A hovered face that did not composite (2026-09-10)

A standard button rests on `restingControlFace` and, under the pointer, on
`hoveredControlFace` — a tint that walks toward the accent until the colour cube can show
the step. Every exit of either face composited over the page, and so was opaque, except
one: when no tint cleared the cube, the fallback returned the RAW accent. At
`.tint(.clear)` every candidate composites to the page, so that fallback is certain there,
and the caps — drawn with no claim, on the strength of being "opaque by construction" —
put a transparent colour into the emitter on hover alone. Focus was not needed: an
unfocused cap is drawn in the face itself.

The fallback now spends the accent over the page, the ground the resting face uses. An
opaque accent comes back untouched, so no shipped palette's bytes move.

The comment that called the caps opaque by construction was true of the resting face
only. It is true of both faces now, and `ButtonCapCycle` asserts it, because without the
check the caps' two label paths fail differently: loudly on the string path, and on the
view path — where the caps are `Text` — as a silent claim at ink 0.

This is not another copy of §29's pair. It is the INPUT to copy four: `ButtonCapCycle`'s
dim end, which was only ever as opaque as the face.

What remains: a tint too faint to show a hover step now shows no hover at all. Before, a
release build drew the accent's opaque spelling in the caps — black, for `.clear` —
which was a hover of sorts, and a wrong one.


## 50. An overwritten row kept the content's claims (2026-09-10)

A scroll view with `.scrollIndicatorStyle(.text)` shows its "N more" lines one of two
ways. Under `.visible` it reserves two lines and draws the content between them. Under
`.automatic` it OVERWRITES the viewport's first or last line: an indicator is there only
when there is content past it, so the line it covers is one the reader reaches at a
neighbouring offset.

The overwrite dropped the content's RUNS on those rows — a focus ring's breath would
otherwise repaint over "▲ 3 more above" on a clock — and kept its CLAIMS. So a
translucent content line under the indicator left its alpha behind, and the indicator
resolved at an alpha nobody had painted it with. While the indicators claimed nothing of
their own that faded an opaque indicator; once they claim, the two would multiply.

Every claim is now clipped to the band of rows that survives. The replaced rows are only
ever the edges, so one clip does it — the trim a clipping container makes — where
cutting each row out separately would have split a claim spanning the whole viewport into
slivers.


## 51. A List row's claims landed on another row after a front drop (2026-09-10)

A `List` carries each visible row's content claims up into its buffer the way it carries
the row's hit regions and overlays: by pairing the frame's row ranges with the rows they
were drawn from, by position (`attachRowOpacity`). Two things drop ranges off the FRONT
and keep the rows — a push past the bottom, which slides the top rows out, and a reorder
hold's overrun, clipped away from the slot — and after either, each row's claims sat on
the line of a row further down, one of them on the slot's blank line, and the last rows'
claims went nowhere.

The rows are now put back in step with the ranges before anything pairs them. The
anchoring spec's overscroll record carries the fix, because the claims were one of three
payloads with the same defect, and a row's buttons were the one a user would see.

Two things stayed, and both are closed now. A row cut partway through its top, by either
producer, still read its claims from the top of its own buffer, so they sat as many lines
low as were cut — §67. And the claims the list paints itself (`rowClaims`: the selection
mark and fixed fills) did not go through the reorder clip at all. No hold constructed then
had any to move — every selected row is in hand, and the slot's background is a pulse — so
it was recorded here; a `.live` hold turned out to have one, and §54 fixed it.


## 52. A row in hand lost its claims at the slot (2026-09-10)

A reorder takes the rows in hand out of the list and draws them only at the slot where
they would land: as a faint copy under `.dimmed`, which is also what every keyboard move
shows. Both twins built that copy from the rows' lines alone. `_ListCore` dimmed and
stacked them with `FrameBuffer(lines:)`, which carries none of a buffer's payloads, and
`Table.reorderSlotLines` kept each held row's line and pulse from a `renderRow` that
returns its claims as well. So a translucent row showed at its opaque spelling for as
long as it was held, and at its own alpha again once dropped. The grabbed row of a
multi-row keyboard hold, which is not dimmed, showed it at full strength.

The copies now carry their claims, and only their claims. The dim moves no cell, so a
claim still names the cells it did. The runs stay behind, because replaying the undimmed
frames would un-dim the copy on its first tick; so do the hit regions, because a row in
hand is not a control; and so do the overlays, whose drawing the dim never reached.

What the runs said about ALPHA was left behind with them, which this section did not see
because nothing stated an alpha only on a run when it was written. Since §69 something does:
a `.border(AnimatedColor)` at several alphas claims nothing and carries its alpha on its
runs, so a held row with one drew its border at full strength in the slot. The copies now
also carry each animating run's drawn-frame regions, after their claims (§69.4).

The slot's claims reach the list's buffer through the row pairing §51 repaired, so this
needed that first: a front-clipped hold would have put them on another row.


## 53. The text scroll indicators claim what they paint (2026-09-10)

The "N more above" / "N more below" lines of `.scrollIndicatorStyle(.text)` are drawn in
the palette's tertiary and, on a focused scrollable, breathe to its accent. They went to
the emitter through a raw `colorize` with no claims, on every host that draws them:
`List`, both of `Table`'s paths, and both of `ScrollView`'s. Rendering a page under a
wholly faded palette trapped on them in a debug build (§16.3); a release build drew
them opaque. The suites never saw it. Plenty of them draw the text style, but none
under a palette that faded its tertiary — one that had would have trapped — and the
faded fixture nearest the line, `FadedInk`, pins the tertiary opaque by its own
comment, because the line was drawn in it.

### 53.1 A line is a row

`renderScrollIndicator` returns a `ScrollIndicatorLine`: a `ClaimingRow` whose
centring blanks are a `skip` — no colour, so no claim — and whose arrow and label are
appended in the ink, so the bytes spell the colour opaque and the claim carries its
alpha, the pairing every claiming paint uses (§43.1). Each host places the claim on
the row it drew the line on, beside the run it already moved there:

| host | rows | |
|---|---|---|
| `List` | the first and last assembled lines | added after the slide, as the runs are (§43.3) |
| `Table`, single- and multi-line | 0 and `lines.count` | before the line is appended |
| `ScrollView`, overwriting | 0 and last | after §50's cut, so the content's claims are gone from those rows first |
| `ScrollView`, reserving | 0 and `height - 1` | the content's claims moved down a row with it |

`Table`'s measure asks `scrollIndicatorWidth`, which chooses no colour at all; it used
to render the whole line to read its width.

### 53.2 The unfocused line carries, the focused one spends

Unfocused, nothing replays the line, so the tertiary's alpha goes into its claim
(§29.2).

Focused, the line breathes between two palette slots with alphas of their own, so both
ends spend against the enclosing surface (`scrollIndicatorBreath`) and every frame is
opaque. The scrollbar's breath carries instead, because its two ends are re-spellings
of one accent (§44). Here a faded `.tint` alone put 255 at the dim end and 128 at the
bright one — §29's pair, a ninth time. The frames' claims go through
`assertFramesOweOneClaim`, and all of them owe nothing. A navigation crumb's breath is
the exact twin: a resting rung and the accent, both spent (§47.2).

A focused line under `.selectionIndicatorStyle(.none)` is still — one frame, no run —
and spends all the same, so focus shows one colour whether it breathes or not.


## 54. A back clip left the list's own claims past the rows (2026-09-10)

`_ListCore.clipReorderOverrun` clips a reorder frame that holds more lines than fit,
and it took the lines, the row ranges and the pulse runs with it — not `rowClaims`, the
claims the list paints on its rows itself. §51 found none to move in any hold it built.
There is one. A `.live` hold draws no slot, so the cursor row stays a drawn row —
focused, not selected — and its focus wash is a fixed fill on every line of it. Pressed
on a row taller than the lines left at the bottom, the frame is clipped from the back,
and the wash's claims on the lines cut stayed past the rows: on the "N more below" line
and the border, and — since §53 — on top of the indicator's own claim wherever that
line claims too.

Only a palette that states a translucent `focusBackground` reaches it; the default
derives the wash with `opacity(_:over:)`, which spends the alpha. The claims now travel
with their lines by the rule the runs already follow: moved up and cut at a front clip,
cut at the cap at a back one. The front branch has no reachable claim today — a front
clip needs a drawn slot, and a drawn slot leaves no cursor row — and takes the same
rule regardless.


## 55. A tab chip's breath ends disagreed about alpha (2026-09-10)

A focused `TabView`'s active chip breathes its label between a resting tone and the
accent. The resting end is black or white, chosen for contrast with the chip's surface,
so it is opaque by construction; the loud end was the accent floored for readability,
and it carried the accent's alpha. A faded palette, or a faded tint alone, therefore put
255 at one end and 128 at the other — §29's pair, a tenth time — and the pulse
interpolated alpha as a fourth channel through every phase between.

The two strips failed differently. The compact one claims what it draws, and draws the
cycle's current phase — the loud end, with no cursor timer running — so it claimed half
the label's ink and replayed every other phase under that one claim, silently. The
bordered one paints its labels through a raw `colorize`, so the translucent end went to
the emitter: a debug trap under a faded tint alone.

The loud end is now spent against the chip's surface, then floored. Spent, because the
other end cannot carry: it is not a palette slot, and giving it the accent's alpha would
fade a label the theme never faded. Floored after, because the floor reads RGB, not
alpha. Exact for a faded tint on an opaque surface; under a faded surface an
approximation, since what the cell shows is that surface composited over whatever is
behind it. `ActiveChipCycle` asserts that its two ends agree about alpha. An opaque
accent is untouched by the spend, so a shipped palette's bytes do not move.

The order matters in practice, not only in principle. Tried the other way round once —
floored, then spent — the loud end fell under the 3.0 readability floor for ten of the
sixteen shipped palettes under a faded tint, as low as 1.53:1, and the suite now checks
the floor after the spend.

The bordered strip's own chrome — its walls, tops and mouth — painted raw until §56.


## 56. The bordered strip claims what it paints (2026-09-10)

A bordered `TabView` draws its folder tabs and the box around its panel itself:
`folderStripRows` the tops and labels of every row of tabs, `activeRowBottomBorder` the
box's top border curving up around the active tab, and `renderBordered` the walls, the
pads either side of the content, the filler rows under a short tab and the bottom rule.
Every one of those went to the emitter through a raw `colorize`, so a palette whose
border, page or surface was translucent trapped on the first wall in a debug build
(§16.3), and drew opaque in a release one.

Each line is a `ClaimingRow` now, as the compact chips' already were. A wall or a rule is
border ink on nothing; a label is ink on field; the mouth under the active tab is the
panel's surface with no ink. The row that emits each run is the thing that knows its
column, so each claim sits where its cells are. A label is drawn by a function of its
own, because the chip's breath has to replay the same cells, and
`ClaimingRow.append(contentsOf:)` splices it into its line, claims and all; an assertion
ties the column the row reached to the one the click region and the run were given. The
box's rows are `panelRow`'s, the compact panel's, between two walls. `renderBordered`
collects every line, the strip's first, and places each line's claims on the row it
lands on, once.

Under an opaque palette the bytes do not change: the TabView pins hold, still and
focused, at truecolor and at 256 colours.


## 57. A breathing bracketed toggle claims its mark (2026-09-10)

A focused `Toggle` drawn with bracketed glyphs — `.toggleCharacterSet(.ascii)` —
breathes its brackets through a run, and the mark between them, or a switch's knob,
does not move. `_ToggleCore` withheld the indicator's claims whenever a run existed, on
§23.2's reasoning: a region carrying the phase drawn now would resolve every later phase
at the wrong alpha. That holds for a cell whose alpha moves, and none of these does. The
brackets breathe between `accentPulse`'s two ends, and both are spent, so every frame of
them is opaque and owes nothing; the mark and the knob are one colour in every frame. So
the claims taken at the drawn phase are every frame's, and withholding them left a
faded tint's mark replaying at its opaque spelling — silently, since the bytes were
opaque either way.

`IndicatorCycle.claims(at:)` returns the drawn frame's claims, and in a debug build
asserts, through the shared `assertFramesOweOneClaim`, that every frame of the cycle
owes the same. The checkbox and the bracketed switch use it. The coloured switch track
did not: its bright end carried the accent's alpha when on, and a lerp took it to 198
of 128 when off, so its frames disagreed and its claims stayed withheld until §58.

An opaque palette's bytes do not change: an opaque colour is its own opaque spelling,
and spending it returns it untouched.


## 58. A switch track's breath ends disagreed about alpha (2026-09-10)

A focused switch in the coloured-track styles breathes its track — the switch's own
background — between the track dimmed over the page and a brighter tone in the state's
hue. The dim end was composited, so opaque. The bright end was the raw accent when on,
carrying its alpha; off, it was a lerp from `.brightBlack` toward the raw foreground,
and a lerp interpolates alpha as a fourth channel: 198 of 128 under a half-faded
foreground, neither kept nor spent. §29's pair, an eleventh time. `_ToggleCore` withheld
the indicator's claims while it breathed, so no frame blended at a wrong alpha — every
frame simply dropped it, and with it the knob's claim, although the knob is the same in
every frame.

`SwitchTrackBreath` now gives both ends spent over the page: on, `accentPulse`'s bright
end; off, the lerp toward the foreground as it shows. Every frame is opaque, so the
track claims while it breathes, through `IndicatorCycle.claims(at:)` and its assertion.
An opaque palette's bytes do not change: spending an opaque colour returns it untouched.


## 59. An animated border's alpha, when its frames share one (2026-09-10)

`.border(_:)` takes an `AnimatedColor` and replays every cell it drew from the colour's
frames. The claims for those cells were skipped whenever the colour animated, on §18.4's
reasoning, and the comment beside the skip said the arm "stays loud": that the emitter's
assertion would fire on a translucent phase. It could not. Since §18.3 every frame goes
through `BorderRenderer.band` at its opaque spelling, so an animating border's alpha was
dropped in silence — the band's, a faded title's and the ●'s alike. The same wording was
stale in three more places — `DropdownMenuRenderer`, a `FadedPaletteRenderTests` doc
comment, and §43.5 — and each became a silent drop the day `band` began stating the
opaque spelling.

### 59.1 One alpha, or not

A run replays bytes under one static claim per cell (§29.2), so the question is whether
every frame is at one alpha. For an `AnimatedColor` that is not a property of the type.
A pulse interpolates alpha as a fourth channel and a blink alternates its ends, so the
alpha holds only when the two ends agree, and `AnimatedColor(frames:)` can hold anything.
The type's own documented example, `animatedColor(isFocused, dim: palette.border,
bright: palette.accent)`, breathes between two slots that a faded tint sets at different
alphas; under a palette fading both alike, it is one alpha.

`hasOneAlpha` asks the frames. The layout is the same in every frame and only the colours
change, and `BorderRenderer.opacityClaims` reads a colour only through its alpha — the
floored title keeps its alpha, and a painted field is the colour itself — so one alpha
across the frames is one claim across them.

- **One alpha:** the border keeps its runs and claims the drawn frame, which is every
  frame's claim. That is `FadedAll`'s border and accent, a faded tint's breath spelled
  through `Color.breathEnds(dimmedTo:over:)`, and every opaque one.
- **Several:** the border keeps its runs and claims nothing of its own, as before. Its
  alpha is dropped and the frames replay at full strength. Still open; §59.2 says why.

### 59.2 Why frames at several alphas are not declined

§36.7's answer for a run that cannot carry the alpha is to decline the RUN: draw the
frame the run would be showing now, claim it exactly, and render again next tick. It was
the first design here, and it is not used, because of what "render again next tick" has
to be made of.

A run goes with its buffer. A render whose buffer is thrown away takes its runs with it:
a `NavigationStack`'s root while a screen is pushed over it, which is rendered to keep its
state and then discarded; the content of `.hidden()`. So does a `ScrollView` that renders
its whole canvas and keeps only the rows in view. Every other way of asking for the next
frame is pass-wide — a volatile read, or `requestAnimation` — and outlives the buffer it
was made for. So a declined border that animates regardless of focus kept the loop doing
a full render every 50 ms while nothing of it was on screen, where the replayed border it
replaced let the loop idle. Found in review and traced through the code, not run.

`requestAnimation` has a second problem of its own, by reading: it bumps a side-effect
count, and `App.renderFrame` stops the cursor timer — zeroing its elapsed time — unless a
frame read the pulse or the caret or left runs. A border indexing its frames by that timer
would then draw tick 0 on every render the scheduler drove.

So the arm stays as it was until a request for a render can ride on the buffer, the way a
run does, and go where the buffer goes. For a caller the remedy is in reach now: give both
ends one alpha. `palette.accent.breathEnds(dimmedTo:over:)` spends a faded accent at
both, and the framework's own focus ● is built that way.

The ● in the top border is claimed at its current frame whenever the border is, so it must
be one alpha too. Its only producer, `activeSection`, spends both of its ends, and a debug
build asserts it.

### 59.3 Not `OpacityCycle`

§18.4 as first written, and §19.1, named `OpacityCycle` as the route: a phase-indexed
alpha. It is the *layer* channel, a repeating `.opacity` fade whose phases tick
independently of any run, and a run under a cycle-bearing region is dropped (§29.2's first
case). A colour whose alpha moves with its frames is not that.

### 59.4 Still open

- **An animated border at several alphas** (§59.2).
- **The drop-down menu's breathing border**, its own renderer, whose pair was §29's again —
  the dim end spent, the bright end carried. Closed in §64.
- **A resizable view's grips**, the other `AnimatedColor.run` consumer, drew their still
  frame through `colorize` with the raw tint and claimed nothing, so a faded tint trapped.
  Closed in §62.
- **§36.7's indeterminate bar, and `Spinner` for a cycle whose frames differ in width.**
  They decline their runs through `requestAnimation`. The freeze was real and is fixed in
  §66; the other problem, a request that outlives a render whose buffer is thrown away,
  still applies to them by reading.


## 60. A caret on a selected character carried its text's alpha (2026-09-10)

§30.1 said a selection's two colours are opaque by construction. Only its FIELD is: the
highlight goes through `opacity(_:over:)`, which stamps its result opaque. Its text is
`readableText(on:)` — a palette slot floored for contrast, and the floor keeps the slot's
alpha. The runs claimed that text's alpha correctly, run by run: §30.1's mechanism was
right and only its reason wrong. The caret was not. `caretSetup` spent the entered text
over the field but handed the selection's text to the emitter as it was, so when the
caret sat on a selected character — which any leftward selection leaves it doing — its
blink-OFF frame drew that character in a translucent colour, and the emitter's assertion
fired. A faded tint alone does not reach it, since the text is the palette's foreground
or background; a faded foreground or background does.

It is spent now, over the highlight. That is literally what is behind the ink in that
frame, and it is the blend the resolver makes for the claimed selected cells beside it:
an ink claim over the cell's own opaque field. An opaque palette's bytes do not change.


## 61. The text editor's rows claim (2026-09-10)

A `TextEditor` under a wholly faded palette trapped in a debug build on its first frame.
Three of its paint sites had never been migrated: each row's runs handed the palette's
foreground and the well to the emitter with their alpha; blank rows did the same with the
well; and the focused caret built its own colours and passed the translucent well and
text straight through. §43.3's "its first claims of any kind" was the bar's alone. The
well is `fieldBackground`, which a faded page fades since §39.

### 61.1 One accumulator, shared as it was

The rows go through `TextFieldContentRenderer.RunAccumulator`, the type a focused field's
content already writes into; only its access changed. The editor's row walk has the
field's shape — runs of colours compared by equality, an external column (`outputCells`)
that holds the next cell's column wherever a run opens or flushes, and the caret written
out of band — which is why it is not `ClaimingRow`. A row states its claims in its own
frame and the render shifts them by the VIEWPORT row, as it shifts the caret; the
downward merge folds a plain editor's identical rows into one rectangle. A blank row is
one run with no caret, so it goes through `ClaimingRow`, claiming the well as a field with
no ink. A disabled editor has no well, so its text claims ink only — as a disabled
`TextField`'s does, and not §31.3's spend, which is the slider's own composite.

The colours are derived once per render and resolved there, because the bytes no longer
pass through `TextStyle.resolved(with:)` and a custom palette may state a slot
semantically. Selected cells claim their text's alpha over the highlight's opaque field
(§60). An opaque palette's bytes do not change.

### 61.2 The caret goes through `caretSetup`

The editor's caret now takes its colours from the field's `caretSetup`, once per render,
so the two carets agree about what a faded palette's caret spends. Its ink owes nothing in
any frame: the caret's own colour is opaque at every tick (§29.3), a block caret punches
its character out in the well's opaque spelling, and the blink-OFF text, selected or not,
is spent (§60).

Its FIELD was open, in both carets, and is **closed in §69.1**. The analysis below is why
it could not be a rectangle, and it stands; what changed is that it no longer has to be
one. The frames painted the well's opaque spelling and claimed nothing, so under a
translucent well the caret's cell showed the well at full strength. Whether one claim
could fit turns on the frames: a bar or underscore off a selection shows the well in every
frame, and a pulsing block shows only its own opaque colour; but a blinking block — the
default — and a blinking bar on a selected cell alternate between the well and an opaque
colour, and no one claim fits them.

The way out was not the one considered here. Declining their runs, as §36.7 does, would
re-render the page every tick while the editor or field is focused over a faded well — the
cost the caret's runs were built to remove — and §59.2's reason applies to how it would
ask. Stating the alpha per FRAME, on the run, costs no renders at all.

### 61.3 What the tests assert

`FadedPaletteRenderTests` draws the editor under a wholly faded palette — overflowing,
blank, scrolled across a tab and a wide glyph, disabled, focused with every caret shape
and animation, and with a selection — and checks cells for owing exactly the colours
painted in them. The caret's own cell is checked for owing no ink, and deliberately not
for its field. Under an opaque palette nothing is claimed.


## 62. A resizable view's grips (2026-09-10)

`.userResizable()` marks each draggable edge — and the corner, when both axes move — by
stamping a glyph over the border in a tint: the border colour at rest, lifted when
hovered, and while focused the breath `activeSection` gives a focus section's ●. The still
frame went through `colorize` with the raw tint and the raw page background, and nothing
claimed, so a faded tint — or a faded palette's border or background — reached the
emitter and trapped.

It was also two colours, not one, while focused. The still frame was the accent, floored
for contrast; the run that replaced it on the next tick breathed through
`activeSection`'s spent ends. So the grip changed shade on the first replayed tick, and
under a faded tint the drawn frame and the run disagreed about alpha as well: no one claim
could have fitted both.

Now the frame drawn while focused is the breath's current one — the colour the run
replays over it — and every frame is emitted at its opaque spelling through `ClaimingRow`,
whose claim the overlay carries: the ink's alpha, and the page background's as a field.
`composited` punches the border's own claim from those cells and lifts the grip's in its
place, so each is claimed once, and the claim holds in every frame: the breath's ink is
opaque at both ends, and the field is the page's in all of them. At rest and hovered the
grip keeps its floored tint and claims its alpha. An opaque palette's bytes do not change
at rest; focused, the frame drawn is the breath's current one rather than the floored
accent, which is what the next tick showed anyway.


## 63. A split view divider's grip dots (2026-09-10)

A resizable `NavigationSplitView` draws its divider as three `◦` dots in the quiet
tertiary rung, breathing toward the accent while hovered, over a background that pulses
while the divider is focused or dragged. Every cell went through `colorize` with the raw
colours, and nothing claimed. So a palette whose tertiary rung is faded trapped the moment
the split drew, hovered or not; and the hovered breath was §29's pair a twelfth time — its
dim end the accent composited over the page, its bright end the raw accent — so a faded
tint trapped on hover.

The dot's ends now come from `breathEnds`, and each cell is built through `ClaimingRow`:
the bytes state the opaque spelling, and the divider's buffer carries the drawn frame's
claims. Those are every frame's claims. The colours that move are the dot's breath and the
background's `accentFillPulse`, both spent at both ends, and a resting dot is the tertiary
rung in every frame. `combineColumns` already carried a divider's claims across, through
`appendHorizontally`; there had been none to carry. An opaque palette's bytes do not
change.


## 64. A drop-down menu's breathing border (2026-09-10)

An open drop-down's border echoes the highlighted row's pulse at lower intensity, from
`DropdownMenu.pulseEnds`. That pair was §29's a thirteenth time: the dim end the accent
composited over the page, the bright end the raw accent. Under a faded accent its frames
were at different alphas, so the breathing arm — the default — stated no claim for its
chrome, and its frames went out at their opaque spelling: the tint's alpha dropped in
silence. The still arm, under `.none`, claimed the raw accent's alpha.

The pair now comes from `breathEnds`, spent at both ends. Every frame of the border is
opaque, so the claim taken from the frame drawn is every frame's, and it is stated in both
arms now — empty in both, since the colour is opaque. A debug build asserts that the frames
share one alpha. Under `.none` the border is the accent spent over the page rather than
the raw accent claimed: how every other focus breath treats its bright end, blending toward
the page rather than toward whatever the popup covers. An opaque palette's bytes do not
change.


## 65. A plain container's title and footer rule (2026-09-10)

A container with no border — `.listStyle(.plain)`'s, the only one — draws its title on a
line of its own and, above a footer, a full-width rule, since there is no top border to
host the one and no walls to cap the other. Both went through `colorize` with the raw
colour and claimed nothing. A title defaults to the accent, so a plain list with a title
under a faded tint handed the tint to the emitter and trapped; the rule is the border's
colour, which a faded palette fades.

Both now go through `ClaimingRow`, and their claims join the ones the body and footer
carry up — the title's on its row, the rule's on its. A plain list's border colour never
animates, so each claim is every frame's. An opaque palette's bytes do not change.


## 66. A declined run's clock (2026-09-11)

§36.7's translucent bar, and `Spinner` for a cycle whose frames differ in width, decline
their runs and ask the scheduler to render them at the cycle's own rate. Both still took
the frame to draw from the cursor timer's content clock — the clock a RUN replays on, and
right on the run path, where the frame drawn must be the frame the loop will splice. On the
declined path nothing keeps that timer running: the loop stops it, zeroing it, after any
frame that read neither the pulse nor the caret and left no runs, which is exactly a page
holding only such a view. So every render the scheduler drove drew frame zero: a bar or a
spinner that did not move, re-rendered several times a second for nothing.

A declined run now takes its frame from the frame clock, `frameNowNanos`, which the loop
stamps on every render and which the other per-render animations already read —
interpolations, transitions, tooltips. That adds no wake-ups: the scheduler request each
already made is the only driver. The run path keeps the cursor timer, so a bar that moves
between the two — a tint fading or unfading it — may jump once, on a change that re-renders
the screen anyway.

The test drives `RenderLoop` itself: four frames of a page holding only such a spinner, or
only such a bar, at advancing frame times and with the cursor timer as the loop leaves it.
Nothing in those frames would keep the timer alive, the scheduler has a next firing after
each, and the pictures differ. Before this, all four were one picture.


## 67. A row cut through its top carried its payload a line low (2026-09-12)

§51 paired a `List`'s drawn rows with the ranges they were drawn from, and recorded what
that left: a row cut partway through its own TOP still read its payload — its hit regions,
its overlays, its opacity claims — from the top of its own buffer, so the payload sat as
many lines low as were cut. Two paths cut a row that way, and both trim its range to the
viewport's first line: a reorder frame's overrun, clipped from the front away from the
slot, and a push past the bottom, whose slide takes the top row's first lines.

The scroll's own `topClip` was never the problem — that one belongs to the origin row
alone, and every consumer added it already. What nothing recorded was the extra cut. A
range carries it now as `linesCutAbove`: the reorder clip adds what it took, the slide
reports it from `slidRange`, which owns that arithmetic, and the three consumers add it to
the clip they already applied — both to the window they read from the row's buffer and to
the shift they place it by.

Measured with a button on every line of a multi-line row, clicking each line the frame
drew: the line drawn as `r5bb` tapped `r5a` after a push, and under a reorder overrun
`r7ccc` tapped `r7bb` and `r7bb` tapped `r7a` — each exactly one line off, which is what
each path had cut.

Single-line rows never showed it, which is why §51's own cases did not: a cut of one line
does not cut a one-line row, it drops it, and a dropped row's payload was §51's subject. A
push also engages only where the resting bottom is row-aligned — a push IS a step the edge
blocked, and off that lattice every tick still has a line of the top row to give — so the
fixture picks a row height and indicator style that land there, and asserts it.

The `Table` carries no per-row payload at all, its cells being drawn by the table itself,
so nothing sits in a row's own coordinates to misplace. Its bands did diverge, though, and
chasing that down found the same bug wearing different clothes: `drawnBands` DROPPED a
band whose start went negative, where the List trims it. Right for a row slid wholly off
the top, wrong for one the slide cut THROUGH — pushed two lines past its bottom, a
multi-line table left its top row's last line on screen answering no click at all, since
the click map (`rowAt(y:)`) walks those same bands. Fixed by trimming instead, with two
corrections to the obvious form of it. The floor is the top of the ROW BLOCK, not of the
interior: the slide moves the rows and not the "N more above" line above them, so
trimming to zero would hand the indicator's line to the row. And the drop guard has to
compare against the CLAMPED start — comparing against the raw one is what made an earlier
attempt at this leave a fully-slid row competing for the first line. So `offset` split
into `slide` and `rowsTop`, which is what keeps the two from being summed back together.

The `topClip` path was never affected: it trims the row's lines before its height is
recorded, so its bands were right all along. Only the two things applied AFTER the heights
were taken — the overscroll excursion and the reorder overrun's front clip — could cut a
row the bands still described at full height.

Not quite only two, as it turned out the same day. The multi-line `Table` also cuts its
BOTTOM row after the heights are taken — the row `ScrollRowWindow` admits across the line
budget, drawn short so the "▼ N more rows below" line fits under it — and it trimmed its
bands at the content area, which includes that line. The cut row's band ran on over the
indicator, so a click on "▼ 4 more rows below" selected the row above it, and in a
reorderable table a press there grabbed it (review batch 2026-09-12, #26). A cut at the
bottom moves nothing below it, so the fix is a ceiling rather than drawn heights: the bands
are trimmed at the row block's drawn end, which `_ListCore` and the single-line path
already passed.

## 68. Six sites the ledger never had: the faded-palette live sweep (2026-09-12)

Every count of "the sites that must honour alpha" in this document was arrived at by
reading. §16.1's thirteen entry points, the re-counts at §40.2 and §43 that found the
ledger low by 3–6× each time — all of them re-read the same list, and each re-read
recovered what the last one had missed rather than what nobody had looked at.

So the app was run instead, with translucency everywhere. `CustomizablePalette.init(from:)`
in the example takes a snapshot of every semantic colour, and
`TUIKIT_EXAMPLE_PALETTE_ALPHA=0.5` now fades all of them but the four grounds — the grounds
being a claim about how present a LAYER is rather than about paint, so fading them tests the
compositor instead and makes every cell owe something, which buries the one that does not.
In a debug build the emitter's assertion is armed, so any unclaimed paint site is a trap
with the alpha in its message.

It was found by patching that initialiser by hand; the environment variable is what the
find turned into, and `Tools/Smoke/faded_palette_sweep.py` is the sweep itself, so the
check is repeatable rather than a thing that happened once.

**The existing walk cannot do this job, and that is measured rather than assumed.**
Wiring a second `ci-pty-smoke.sh` walk under the fade looked like the cheap answer; with
the drop-down marker's fix reverted on purpose, that walk reported every page alive,
including the two the sweep names first. `tui_walk.py` steps a menu — `down*3,up` per item
— and a `Picker`'s ✓ is not painted until the pop-up is OPENED. **A walk that only
navigates cannot see a control that has to be opened**, so under a fade it proves only
that the pages draw at rest. The sweep pokes each page (Tab, Space, arrows) and catches
all six; on the same reverted build it trapped on six pages and exited non-zero.

Two other things the sweep does that the walk cannot. It runs one process per page, so it
reports the whole inventory instead of stopping at the first trap — which is the
difference between six fixes and six rounds. And it keeps stderr on a pipe of its own,
which the walk cannot: reconstructing a screen with `pyte` is the walk's whole method, and
a Swift backtrace interleaves into unreadable columns through it.

It runs in CI, at `full` depth, last in `ci-pty-smoke.sh` because it is far and away the
most expensive thing there: **7 min 15 s** for 35 pages, nearly all of it settling between
keystrokes (12% CPU). Measured end to end, `full` went from about four minutes to
**11 min 23 s**. Two lanes run it — macOS 26 and Linux 6.3 — so that is the bill, and it
was the owner's call to pay it. The ordering is deliberate: every other check in that
script gives its signal in seconds, so the seven-minute one goes last and a fast failure
stays fast.

Six sites, on ten-plus pages, none of them in any ledger here:

| Site | |
|---|---|
| `DropdownOptionMenu.attach` — the ✓ beside a drop-down's current value | six pages |
| `Spinner.renderBouncingFrame` | alpha **192** |
| `DimmedModifier`'s `Flattening`, via `dimmedAsBackdrop` | |
| `_ListCore.renderLineWithBadge` | |
| `_ImageCore.renderPlaceholder` | |
| `_DatePickerCore.renderToBuffer` | |

The alpha-192 one is the sharpest lesson. Nobody greps for a paint site that never
mentions opacity, and `renderBouncingFrame` does not: it calls
`Color.lerp(color, trackColor, phase:)`, and a lerp between a faded colour and an opaque
one MAKES an alpha that no palette slot holds and no author wrote. An audit by reading
cannot find that; running it finds it in a second.

### 68.1 A drop-down option's selected marker

`DropdownOptionMenu.attach` paints the ✓ in `palette.accent`, one layer ABOVE the renderer
that draws the popup — so it is neither the chrome's claim (§64) nor a row the renderer
painted, and it fell between them. Every `Picker` in the example trapped on opening.

The marker's bytes are now the accent's opaque spelling, and its alpha travels as a claim
on `Row.option` — in ROW-LOCAL columns, `offsetX: 1` being the cell the row's leading
space puts the marker in. The renderer places it, shifting by the same window it draws the
row with, exactly as it already does for a divider's rule. The alternative — having
`attach` work out the line number itself — means re-deriving the scroll window outside the
only thing that owns it, and the two would part the first time either changed. That the
claim rides on the case rather than in a dictionary beside `rows` is the same argument one
step further in: a `[Int: [OpacityRegion]]` can be keyed wrong, an associated value cannot.

The claim is sound under the popup's breath for the reason §64 gives for the chrome: every
line of the popup is inside a run, and a marker's colour is the same in every frame of
that run, so one static claim describes them all.

### 68.2 A list row's badge

`.badge(7)` on a row is the one text a `List` draws itself — the rest of the row is a
child buffer that claims for itself and `attachRowOpacity` carries those up — and it is
drawn in `foregroundTertiary`, which a wholly faded palette fades by derivation rather
than by declaration. So it trapped on a list nobody had thought to fade.

The claim goes in `SelectableRowClaims.claims`' `cells`/`ink` pair, which the `Table`
already fills with the text it draws and the `List` had been passing `0..<0, nil`. That
parameter's own documentation says what it is for: "the columns the row's TEXT occupies …
empty where the caller draws no text of its own". A badge is exactly that text.

Its columns come from one derivation shared with the bytes (`badgePlacement`) rather than
counting back from the right edge, because the fill between content and badge is
`max(1, rowWidth − used)`: on a row too narrow for both, the badge is NOT at
`rowWidth − badgeWidth − 1`, and a claim placed there would fade a cell of the content
and leave the badge opaque. That the pad after the badge owes no ink is asserted too, for
the reason the shared builder already states about the gap cell beside a mark: an ink
claim on a bare space lets what is behind it through where the row drew a pad.

### 68.3 An image's placeholder and its error line

Three paints, one shape: the placeholder's spinner glyph in `palette.accent`, its caption
in `foregroundSecondary`, and the failure path's whole line in `palette.error`. All three
were colorized by their callers and handed to `centerContent` already drawn.

That is why the claim could not be made where the colour was known: only the centring
knows what cells a line ends up on — it pads on the left by `(width − visibleWidth) / 2`,
and it may CUT a line wider than the buffer, which changes that width. So the content now
travels as `(text, ink)` pairs and `centerContent` does both halves: opaque bytes from
`ink.opaqueSpelling`, and the claim over `padding ..< padding + visibleWidth` after the
cut has had its say. The pad itself claims nothing, for the reason §68.2 gives.

This is the same conclusion as §68.1 reached from the other direction. There, the producer
knew the colour and the renderer knew the position, so the claim travelled as data to the
renderer. Here the producer could hand over the colour itself, so it does. What is not
allowed is the third option: deriving the position twice.

### 68.4 A date picker's field

`_DatePickerCore` draws every component of the field itself: the separators in
`foregroundSecondary`, the editable parts in `foreground` (or `foregroundTertiary` when
disabled, or `hoveredForeground` under the pointer), and the focused component's glyph on
a breathing accent block. All of it went to the emitter with the palette's alpha on it.

The claim is taken at the column `line` has already reached, before the bytes go on, and
once per cell — never once per run frame, which is the trap the run here invites: the
active component's `activeCell` is called for the line AND for every frame of its breath.
One claim is nonetheless right for all of them, because only the BLOCK breathes and
`accentFillPulse` spends a faded accent against the page at both ends, so no frame states
a translucent colour of its own. That is the same argument §51 records for a list row's
breathing fill, and it is why the ink can be claimed while the field cannot.

The colours are resolved before either half is taken. A palette slot may be `.semantic`,
and `opaqueSpelling` only clears the alpha field — it cannot flatten a semantic case, so
the emitter would `fatalError` on it rather than assert, and the claim would be reading an
alpha off the wrong colour. Both halves ask the one resolved colour.

Two rungs on one line is also why this is claimed per cell rather than as a rectangle over
the field: the separators and the digits are different colours, and a single ink claim
across both resolves one of them at the other's alpha — §23.2's mistake again.

### 68.5 The wash a modal dims its page with

`dimmedAsBackdrop` flattens the page under a modal to one foreground on one background,
and those are `foregroundTertiary` and `overlayBackground` — both of which carry a faded
theme's alpha since §39. Both went to the emitter.

The doc comment there already explained why the CONTENT's claims are dropped: the flatten
rewrites every cell, so a region saying "these cells are 40% translucent" no longer
describes anything present. That reasoning stands. What it went on to say — "the dim is
deliberately flat and opaque" — conflated two things. Flat means one colour everywhere.
Whether that colour is opaque is the theme's business, and a theme that asks for a
translucent overlay is asking to see the terminal through the wash.

So the two channels are answered differently, which is the interesting part:

- The **field is claimed**, as one rectangle over everything the wash covers. Every cell
  of a backdrop is painted in it, so the rectangle is honest, and one region is all a
  uniform wash needs.
- The **ink is spent** against that field. A dimmed row's glyphs sit on the wash and
  nowhere else, so `spendingAlpha(over:)` gives exactly the right colour — and an ink
  claim would also have to cover the blanks between words, where there is no glyph to
  blend and what is behind would show through a cell this one painted (§68.2's rule about
  the pad, met from the other side).

The claim covers the flattened runs too — their frames are washed in the same two colours,
so the one static claim a run replays under is true of every frame of it.


### 68.6 The bouncing spinner, and a decline that had to be revisited

This one was already written down. `spinnerFrames` says `.bouncing` "stays unhonoured",
§16.3 says it "stays loud", and `ForegroundStyleAlphaTests.bouncingSpinnerDeclined` existed
so that reading as a decision rather than an omission. The reasoning was sound: its trail
lerps a different colour into every cell of every frame, a run replays its frames under one
static claim per cell, and no such claim can describe a ramp that moves.

What the decision got wrong was the cost. "Stays loud" meant a debug build traps, and the
alpha it trapped on — **192** — is one no palette holds and no author wrote:
`Color.lerp(color, trackColor, phase:)` between a faded colour and an opaque one MAKES it.
So the one paint site in the framework deliberately left to trap is also the one that
manufactures its own alphas, and it took a live run under a faded palette to notice that
the decline was reachable from a plain theme rather than only from a deliberate tint.

Spending both ends against the page costs nothing and needed no machinery: `trackColor` was
already spent, by the `over:` on its own `opacity(_:)`, one line above. The other end now
gets the same treatment from the same ground, every lerp between two opaque colours is
opaque, and the style claims nothing — which is what the claim-exclusion in `renderToBuffer`
had been saying all along, for a different reason.

The general lesson is narrower than "re-probe a stale note" (§59.4's) and worth keeping
separate: **a decline is a decision about a cost, and the cost can be re-priced.** This one
was taken when the alternative looked like per-cell claims. It was never re-examined when
`spendingAlpha(over:)` made a second alternative cheap, because the note recording it read
as settled rather than as a trade.

## 69. A run can carry an alpha per frame (2026-09-12)

§29.2 narrowed "an animating colour cannot carry a claim" to two cases. The second — a
breath whose phases have different alphas — was closed nine times over by making the
phases AGREE, which is what `breathEnds(dimmedTo:over:)` is for. Twice that was not
available, and those two sat open: an animated `.border` at several alphas (§59.2) and a
caret's field over a translucent well (§61.2). Both simply dropped the alpha.

The answer is not to decline the run. It is to let the run say what its cells owe **per
frame**, which is `AnimatedRunAlpha`: one list of spans per frame, in the run's own frame
order, plus the index the buffer's lines were drawn at. The resolver already walks every
frame of every covered run and blends each one; all that was fixed was the alpha, folded
once for the whole run on the argument that "every frame of a run occupies the same cells,
so the answer cannot differ between them". The cells are the same; what they owe is not.

### 69.1 Four things that made it correct rather than merely plausible

Three independent designs were written for this and **all three were refuted** on first
reading — the survivor by a defect that the obvious implementation would have shipped.
They are worth recording as the shape of the problem.

**The line needs the drawn frame's claim, and the run cannot be the only carrier.** A run
is the one payload this codebase deliberately DROPS where a region is clipped and kept:
`ScrollView+Content.visibleRuns` drops a run wider than its viewport whole while
`visibleOpacity` clips and keeps every region; `clipped(toCanvasColumns:rows:)` and the
punch path drop a cut that stopped animating. Had the alpha ridden only on the run, a
bordered box wider than its `ScrollView` would have drawn an opaque top rule with faded
side walls — the very bug class this branch exists to close, reintroduced behind the fix.
So `resolvingOpacity` keeps **two** region lists: `regionsForLines` (what covers the
buffer, PLUS each run's drawn-frame spans as ordinary rectangles) and `regionsForRuns`
(what covers it, and nothing else). The lines fade at the drawn frame; the frames fade at
their own. `AnimatedRunAlpha.drawnRegions(forRunAt:offsetY:)` is the same statement for a
site that discards a run to leave behind, so those cells degrade to a static claim —
right at the drawn frame, frozen after — instead of to full strength.

**Appended, never prepended.** `foldedAlphas` takes the LAYER from the first region
covering a cell and multiplies only ink and field across the rest. A run's payload has no
layer channel at all — deliberately, because a layer's alpha nests and `OpacityFade` has
already folded every enclosing `.opacity(_:)` into the regions it can see, which will
never include a payload riding on a run. Put ahead of an enclosing fade it would answer
the glyph contest with a 1 that is not true.

**`isAnimating` had to learn about it.** Four sites drop a run they consider still, and
all four run BEFORE the resolver blends alphas into frames. A blinking caret whose frames
differ only in what the cell owes is byte-identical until then, so without teaching that
predicate — and `timeUntilChange`, which decides how long the loop may sleep — the fix
would have been discarded before anything could see it.

**Spans are run-relative.** Column 0 is the run's first cell, so `shifted(byX:y:)` and
`movedTo(row:)` are the identity for the payload and no compositing shift touches it. That
is also what will let a border share one payload across all `2 × (height − 2)` of its side
walls rather than computing one per row.

### 69.2 The caret's field

Closed. `caretCells` now reports the field it painted alongside the bytes it painted it in
— one function, one switch, so the claim cannot drift from the colour — and `CaretColors`
holds the well as AUTHORED rather than pre-spelled, which is where the alpha used to be
lost. A block frame owes nothing (its colour is its own, opaque by §29.3); every other
frame owes the well. The ink owes nothing in any frame, which §60 and §29.3 already
established, so this is a field statement and not a pair.

Measured on a focused `TextField` under a wholly faded palette, over an opaque ground:
before, **7 of the 14 frames showed the well at full strength** (`48;2;31;31;62`) and none
showed it resolved; after, those seven are `48;2;21;21;41` — the well at its own alpha
over the ground — and the block frames are untouched at `48;2;15;106;131`. The line the
render drew states the same background as the frame it was drawn at, which is the
invariant the two-list split exists for and what the test pins.

One thing this does NOT change: resolving any run against a *translucent surface* trips a
separate assertion (`OpacityBlend.swift:608`). A plain `Spinner` under a faded palette
does it too, so it predates this and is not caused by it — but it is now written down.
Every shipped palette's background is opaque, and the example's fade seam deliberately
leaves the four grounds alone (§68), which is why nothing has met it.


### 69.3 The animated border at several alphas

Closed, and it is the case §59.2 left open. The border states no region of its own when
its frames disagree — that guard stays exactly as it was — and states the alpha on its
RUNS instead, one list of spans per frame.

The spans come from `BorderRenderer.opacityClaims` called once per STEP, at that frame's
colours: the same function the static claim uses, so the claim cannot drift from the
bytes, and a title and a focus ● come along at their own alphas without this code knowing
anything about where they sit. Each run then slices its own cells out of that one answer.

The interesting part is the side walls, and it is a cost lesson rather than a correctness
one. A bordered box emits **2 × (height − 2)** wall runs — 44 for a 24-row section, not
the four a reader might picture — because the wall is one run shifted to every interior
row. Building a payload inside that loop would be ~950 array allocations per box per
render for an answer that is identical every time. Because spans are run-relative, the
payload is worked out once per SIDE and every shifted copy carries it, exactly as the
frames already were. The rule to keep is *one payload per distinct claim geometry* —
three shapes here, top band, bottom band and wall — never one per row.

### 69.4 Where a dropped run degrades

A run is the one payload this codebase discards where a region is clipped and kept, so
"the run carries the alpha" needs an answer for the places the run cannot go. Two of the
four are answered by ``AnimatedCellRun/isAnimating`` consulting the payload: the overlay
punch and `clamped` both drop a cut that stopped animating, and a cut whose frames are
byte-identical but whose alphas differ is now animating, so it survives.

The other two drop on GEOMETRY and needed the degradation:

- `ScrollView+Content.visibleRuns` drops a run wider than its viewport whole, while
  `visibleOpacity` clips and keeps every region. The shape that would have broken: a
  bordered box wider than its viewport, whose top and bottom rules are dropped here while
  its width-1 side walls survive — an opaque rule above faded walls.
- `_ListCore` drops a child's run that will not fit the row, while the row's lines are
  carried through.

Both now append `AnimatedRunAlpha.drawnRegions(forRunAt:offsetY:)` at the point of the
drop, so those cells degrade to what a static claim would have said — right at the drawn
frame, frozen after — instead of to full strength. `RowRun` also had to CARRY the payload
for the runs it keeps, which is the same omission its own comment already records about
`frameDuration`: rebuilding a child's run with the defaults silently retimed a spinner,
and rebuilding it without the alpha would silently unfade a caret.

A third drops on neither ground. A breathing `_ListCore` row — the cursor row of a focused
list — repaints its whole line every tick, so it discards every child run that DID fit: a
narrower run on that line would be overwritten by the pulse. Dropping them is right, but the
line the pulse repaints is the child's drawn frame at its opaque spelling, and nothing was
left behind. Rows bordered with a `.border(AnimatedColor)` at several alphas faded, all but
the cursor row's, which drew at full strength while the cursor sat on it. That return now
leaves the same drawn-frame regions for the runs it drops.

WHERE the list puts those regions matters as much as that it puts them anywhere. The
geometry drop first sent them with the list's own claims — the selection mark, a still
background — which the container lays down before any row's content regions, and the
resolver takes a cell's layer from the first region covering it. So a row whose content
wrapped such a border in `.opacity(0.3)` resolved the dropped cells at layer 1: the border's
ink right, the row's fade lost. Both drops now hand their regions on in the row buffer's own
coordinates, beside the lines rather than among the list's claims, and `attachRowOpacity`
appends them after that row's content regions, through the same clip.

A fourth sat in the same function's first guard. A row carrying a `.badge(_:)` drops every
child run on its first line, because the badge truncates that line's content to make room
— and keeps the line. So a badged row with a several-alpha border drew an opaque top rule
above faded walls: the shape the `ScrollView` bullet describes, with no `ScrollView`
anywhere. It now takes the geometry arm, and its regions are cut to the content the badge
kept, by the derivation the line is drawn through, so none of them reaches the fill or the
badge.

A fifth builds the held slot of a reorder: `dimmed(_:)` and `stacked(_:)` rebuild the rows in
hand from their lines and claims (§52), so their runs were gone before `renderRow` ever saw
the slot. Both now append the runs' drawn-frame regions after each buffer's claims, in the
buffer's coordinates, and the slot's buffer carries them to `attachRowOpacity` like any
row's content regions.

## 70. A run left outside the buffer that carries it (2026-09-12)

`OverlayLayer`'s leading cut (`cutting(_:leadingColumns:rows:)`) moves every payload
riding on a buffer by `(-dropX, -dropY)` and deliberately leaves what it cut naming
columns and rows that are no longer there. Its comment states the rationale:

> `HitTestRegion`, a run and an opacity region record no clip counters, so translation
> and clipping commute, and payload left at a negative offset names cells that were cut
> away — dropped by `AnimatedCellRun.clipped(toCanvasColumns:rows:)` at the screen, and
> already read as `max(0, …)` by the opacity resolution.

The second of those two escapes was not true. `resolvingOpacity`'s run walk clamps only
the alignment `prefix` it builds for the frame; the span it then hands to `blendedSpan` is
the run's raw `offsetX..<(offsetX + width)`, and `blendedSpan` indexes its source array by
ABSOLUTE column with no bounds test — `sourceCells[-1]`, which aborts the process in
release as well as debug, an array subscript being a precondition and not an assertion.
The destination side of that same walk *is* bounds-checked, and carries a comment saying
in as many words that a negative shift is legal. The line path escaped only because
`rebuild` clamps its own start to `max(0, first)`.

So the resolver now cuts before it blends, with `AnimatedCellRun.clipped(toColumns:)` —
the primitive the punch and `clamped` already use — which drops the cells that are not
here from every frame and slices the per-frame `AnimatedRunAlpha` to the same window in
the same expression. A run wholly left of the edge returns `nil` and takes nothing with
it: §69.4's rule is that a run must never be the sole carrier of an alpha, and a run with
no surviving cells is the one case where there is nothing to have carried it for.

A cut and not a clamp, because a clamp is what hid it. Pinning the frame's first cell at
column 0 makes the arithmetic *work* while drawing the frame's leading cells at columns
they do not belong to — silently, and only for a view displaced past an edge. The span's
contract ("already trimmed to the source's own coordinates, by the caller, which is the
only thing that knows which cells to drop") is now asserted at `blendedSpan`'s own head
rather than left in its doc comment.

### 70.2 The seventh faded-palette site: a mono image's theme colours

§68 closed six paint sites by running the app under a wholly faded palette. This is the
seventh, and the sweep could not have found it: the poke sequence is fixed
(`tab tab space down space right tab space up`) and cannot drive the Images page's radio
group to Mono and then toggle "Theme colours", and every page gets a fresh
`TUIKIT_CONFIG_DIR`, so no persisted setting steers it there either. It took a reader.

`_ImageCore.inked(_:mode:palette:)` is the post-cache pass that gives `.mono` art the
theme's ink and paper — applied after the render cache deliberately, because the cache is
not keyed on the palette. It handed `palette.foreground` and `palette.background` to
`ANSIRenderer.colorize` raw. The only regions the buffer carried were `art.claims`, which
describe the SOURCE PICTURE's per-pixel transparency and are empty for the overwhelming
majority of pictures; they say nothing about the two colours this pass stamps over every
cell of every line. So a faded theme tripped the emitter's `isOpaque` assertion in debug,
and in release drew the whole picture at full strength with nothing claimed — the picture
not following the page it sits on, which is the class §68 closed six times.

Two records said this path was clear, and both were right about something else. §16.3 named
the image glyph path "the last of them", meaning §42's converter. §42.4 says mono "paints
no colours at all and therefore has no claim to make", which is true of `isMonoInk` inside
the converter and false of the post-pass four hundred lines away. `fc37ec97` migrated the
placeholder and the error line in this very file and walked past `inked` a few lines below.
Both records now say which half they meant.

Fixed the way every other painted colour in the framework is: `opaqueSpelling` in the
bytes, the alpha claimed beside them, one region per line over the whole line — because a
whole line is exactly what `colorize` puts both codes in force for. `OpacityRegion.claim`
answers `nil` for an opaque pair, so an ordinary palette adds no regions and the resolver
keeps its `opacityRegions.isEmpty` fast path.

**2026-09-13: the pair is the view's styles.** `inked` no longer reads the palette. Its ink
is `.foregroundStyle` and its paper `.backgroundStyle`, each falling back to the palette's
colour. Both are derived once, in `ImageMonoColours`, which `inked(_:monoColours:)`,
`inkClaims` and the terminal-graphics path's `monoInk`/`monoPaper` all read, and resolved
against the palette there, because a style stated straight into the environment arrives
unresolved. A faded style is paired exactly as the faded palette was: the opaque spelling in
the bytes, the alpha claimed beside them. One difference follows from §70.4: a faded
`.backgroundStyle` owes its field alpha, where the palette's paper is a root ground and
reaches the view already spent. The pixel path drops the alpha of both, as it does for every
colour it bakes into a picture.

### 70.1 And the cut site, which had a second consequence

The same negative offsets had a second effect that the resolver's cut does not address,
because it is not about alpha at all. `clipped(toWidth:height:)` re-bases the layer's own
origin to the CONTAINER's coordinates — not the screen's — and every container outside it
then adds a positive shift. So a run left at row -2 inside a viewport that ends up at page
row 3 arrives at absolute row 1, passes the screen's `offsetY >= 0` filter unharmed, and
replays there every tick: a spinner animating on a header line above the `ScrollView` it
belongs to, having drawn nothing of itself anywhere.

`clipped(toWidth:height:)` therefore pre-clips its runs, next to the `hitTestRegions` clip
that was already there and for the same reason. `placed(maxWidth:maxHeight:)` does not need
to and does not: its own returned placement is 0 on whichever axis it cut, so the offset is
still negative when the screen's filter reads it. That distinction is now in `cutting`'s
comment, which previously offered one rationale for both callers and was right about one.

Deliberately no `isAnimating` drop for a cut piece that stopped moving, unlike `clamped`:
`RenderLoop` filters those at the screen anyway, and dropping one here would discard the
only statement of a *non-varying* translucent `AnimatedRunAlpha` — a payload `varies`
reports false for and `isTranslucent` reports true for — which is §69.4's rule.

**Live route, no `.opacity(_:)` required.** The pointer-anchored branch of
`OverlayLayer.placed(maxWidth:maxHeight:)` — a drag preview, which declines to be clamped
to the screen and loses its overhang out of its content instead — cuts the same way, and a
run carrying a translucent `AnimatedRunAlpha` satisfies the resolver's entry guard on its
own (§69.1). A dragged preview holding a focused `TextField`, or an animated border, needed
nothing else in the tree to reach it.

## 73. The status bar's tooltip row (2026-09-12)

The status-bar presentation of a tooltip — the default one, `Documentation/Tooltips.md` §4
— draws its text in `palette.foregroundSecondary`, and `_StatusBarCore.tooltipContent`
handed that slot to `colorize` raw. Nothing claimed the rows. §24's `finished(buffer:…)`
claimed the items' two configurable colours, and the chrome claims its rule or its frame,
which (§18.1) is a frame and not the interior. So a palette fading the slot tripped the
emitter's `isOpaque` assertion in debug, and in release drew the row at full strength in a
bar whose every other paint was faded. The slot needs no naming to be reached: `Palette`
defaults `foregroundSecondary` to `foreground`, so a conformance that fades only
`foreground` is enough — which is exactly `FadedAll`, and what the test uses.

The two presentations of one tooltip disagreed, and the default one was the wrong one:
`TooltipPopover.panel` already spelled its text opaque and claimed it, with a comment
saying a theme's own translucency arrives there. §68's sweep could not have seen the row: it
drives neither the pointer nor the help key, and the Example has no `.help(_:)` to reveal.

Fixed as the items are, and in the same function, for §24's reason — a style added later
must not be able to claim the items and forget the row. The opaque spelling in the bytes,
and one claim over the rows. They sit directly above the items
(`rowOffset - tooltipLines.count`), are inset exactly as the items are (flush in `.compact`
and `.rule`, past the wall and a space of padding in `.bordered`), and are
`ChromeStyle.barContentWidth` wide, the width the text is padded to. They resolve where the
items do, against `palette.statusBarBackground` (§24.1). The claim is asked of
`tooltipLines` before the palette is read, so a frame showing no tooltip pays one
comparison, and `OpacityRegion.claim` answers `nil` for an opaque slot, so an ordinary
palette adds no region and keeps the resolver's fast path.

### 70.5 The same pass papered over a transparent surround

`inked` wrapped each line whole, so the paper went over every cell of it, including the
cells the converter had left blank because nothing of the picture reaches them. §42 took
the flatten out so that a logo's transparent surround shows what the logo sits on, and in
every colour mode it does: those cells are a space stating no colour (§42.2's table). In
mono they came out in the theme's background. `Image(…).imageColorMode(.mono)
.background(.blue)` hid the blue entirely where `.trueColor` showed it round the logo.
On the page itself this was invisible, because the page's background *is* the paper. Over
any other surface it was plain: a `.background(_:)`, a selected row, a dialog.

**Not a claim.** A zero-field claim over the papered surround was the obvious repair, and
it resolves against the wrong thing: against what the compositor sees *behind* the
picture. A `.background(_:)` fill or a row's highlight is not behind it at all:
`applyPersistentBackground` writes it into the picture's own bytes and restates it only
after a reset, and the paper stated at column 0 had already overridden it. The surround
would have resolved to the ambient surface. So the fix is in the bytes, where the colour
modes already put it: an uncovered span is left out of the wrapper and states no colour.

A mono line cannot say "absent" by itself — the space where a pixel is transparent and
the space where it is dark are the same byte — so the converter says it beside the lines,
in `ASCIIArt.uncovered`: runs, collected by the same `CoverageMap` as `coverage`, and kept
out of `coverage` because that list becomes claims and a cell stating nothing needs none.
Every renderer records it, in every mode — the ramps, `.solid`, `.fine`, braille and the
shape matcher — because `inked` wraps all five, and a fact about the picture that held in
one mode only would be a trap for its next reader. "Uncovered" means every pixel the cell
is drawn from is at alpha 0, the same test that makes a colour arm's cell a space in no
colour.

`inkClaims` walks the same spans (`forEachInkedSpan`, shared so the bytes and their claim
cannot disagree), so §70.2's region per line is now a region per painted span. Left whole,
it would have faded whatever shows through the surround toward the surface by the
palette's alpha.

What it does not do: a cell only PART-covered keeps its paper whole (a half-block with
one half absent, braille with some dots absent, a partly transparent unlit pixel), so a
logo's edge can still carry up to half a cell of paper where a colour mode shows the
backdrop. Fixing that needs a claim on the paper's coverage, which colour cells make and
mono cells do not yet. An opaque picture has no uncovered cell: `uncovered` is empty,
`inked` takes the path it always had, and nothing is allocated. The conversion is cached,
so the added per-cell test runs only on a cache miss.


## 72. What the picture is measured from (2026-09-12)

§42 took the flatten out of the glyph path, and §42.4 lists the four renderers that now
ask coverage before they draw. Two things read the picture before any renderer does, to
decide something ABOUT it rather than a glyph — a set of colours and a threshold — and
neither was on that list, so a sweep of the glyph decisions walked past both. Both counted
every pixel, and both resamplers write every uncovered pixel as `(0, 0, 0, 0)`, so both
counted a transparent surround as black.

### 72.1 The adaptive palette's histogram

`ASCIIPalette.Histogram.init(of:)` bucketed every pixel at weight 1 and never read its
alpha. A logo that is 60% transparent, 30% red and 10% blue built `{black: 60, red: 30,
blue: 10}`, so `.adaptive(2, by: .popularity)` answered `[black, red]`: one entry nothing
draws, and the blue mark drawn red, blue being nearer red than black in OKLab (0.288
against 0.302). `.leastError` cut black off into a box of its own at the first median cut
and kept it there. A logo with more colours than the Example's default of eight, whose
surround outweighed every colour in it, drew in seven.

Not only since §42: `recoloured` never flattened, so the pixel path has derived palettes
from transparent pixels since adaptive palettes shipped. §42.6's "already correct" was
about alpha surviving that path, which it did.

An uncovered pixel is now skipped, and a covered one counts at full weight. Both halves
are decisions:

- **Any coverage, not the ½ rule.** The ½ rule decides glyphs. This chooses colours, and a
  partly covered pixel is drawn in its own colour on both paths —
  `CellColours.color(for:)` states one for every `a > 0`, and `PixelQuantiser` sends it
  quantised to this very palette at its own alpha — so its colour is in the picture.
- **Full weight, not weighted by coverage** as §41.1 weighted the resamplers. Their
  weights cancel on an opaque picture and these would not: every weight scales by 255, and
  `medianCut`'s weighted median `box.weight / 2` stops cancelling on an odd total, so an
  opaque picture's palette could move. Skipping leaves an opaque picture's buckets
  exactly as they were. The price is that a one-pixel antialiased fringe votes as much as
  the mark it fringes — in the mark's own colour, since the resamplers un-premultiply.

A wholly transparent picture now finds no buckets and keeps its stand-in greys, where it
used to answer black; nothing in it is covered, so neither was ever drawn.

`AdaptivePaletteTests.transparentPixelsAreNotBlack` pins both methods, and a mark at a
quarter coverage that must still earn its entry.

### 72.2 The mono split

`monoInkThreshold(for:)` — Otsu over a 256-bin luminance histogram — counted every pixel
too, so a transparent surround was a spike at level 0, and the between-class variance
could split that spike from the subject instead of splitting the subject. Tones of 110 and
190 behind a surround nine times their size split at **0.5** rather than **110.5**: every
covered pixel ink, braille's U+28FF and `.blocks(.fine)` mono's `█` across the whole mark,
its interior gone. The surround itself still drew nothing, because the coverage gates
held — which is why a sweep of the gates found nothing wrong.

It depends on the input; it is not universal. That same two-tone subject flips somewhere
between 15% and 17% of the frame transparent, and not below. A mark whose darker tone is
near black already sits on the spike's side and splits where it should: 60 and 200 behind
a 90% surround still give 60.5. A subject cut out of a photograph, all mid-tones, is the
case that bites.

The histogram now counts `a >= 128` — **the ½ rule, and deliberately not `a > 0`**, which
the finding proposed. Every consumer asks coverage first: `isMonoInk` is
`pixel.a >= 128 && …`, braille's dot gate is `coverage >= 128, …`, and the pixel path's
`PixelQuantiser.mono` and the dither go through `isMonoInk`. A pixel under half coverage
is never ink whatever the split, so it has no business moving the split. Weighting by
coverage would be worse than either: it re-admits exactly those pixels as a fractional
vote. So this is the opposite call from §72.1, for the reason §72.1 gives — that one
chooses colours, this one feeds a glyph decision. An opaque picture's histogram is
unchanged; a wholly transparent one falls to the existing `total > 0` guard and keeps
`midLuminance`, as it did before.

§42.4 called `isMonoInk` the only way coverage reaches mono. It was the only glyph gate;
the number the gate compares against is the other way, and that record now says so. Both
paths call the one function, so `recoloured`'s `.mono` is fixed by the same line.
`MonoThresholdTests.uncoveredPixelsDoNotVote` pins it at coverage 0 and at 127.


## 71. A lightness step on a faded colour came back solid (2026-09-12)

`Color.lighter(by:)` and `Color.darker(by:)` both go through one private helper,
`adjusted(by:)`, whose only exit past its semantic guard rebuilt the colour with
`Color.hsl(…)` — a factory that never sees `self`, so it starts at alpha 255. That is
§37.1's shape exactly (the alpha is not decided away, it is structurally absent), and it
is the lightness step §39 answered for `Palette.scaled(_:by:)`, one layer down.
`Color.red.opacity(0.5).lighter()` came back opaque; used as a paint,
`OpacityRegion.claim` read 255 and stated no region, so the text drew at full strength
with no assertion, because an opaque colour never trips one.

It now ends in `carryingAlpha(of: self)`, the exit every other `Color` → `Color`
derivation already ends in. Carried rather than composed: a lighter ink is the same ink
re-spelled, there is one alpha in play, and nothing here knows a ground to spend it
against.

A semantic base was never affected, although the finding's first repro used one:
`Color.palette.accent.opacity(0.5).lighter()` leaves by the guard as `self`, alpha and
all — it does not lighten, which the helper documents. The failing input is a concrete
colour: `.rgb`, `.standard`, `.bright` or `.palette256`.

`ColourAlphaStorageTests.derivationsCarryAlpha`, the table that exists to catch exactly
this, had no row for either. Its doc comment said to add one for anything below
`// MARK: - Color Derivations`, and `Color.swift` has no such mark; `adjusted(by:)` sits
under "Private Helpers". The rows are added, and the comment now describes what a
derivation looks like rather than where one lives. The framework's own caller,
`TerminalProfilePalette`'s bar background, is only ever handed the opaque colours decoded
from Terminal's profiles, so no bundled theme renders differently.

### 71.1 `Color.gradient` took the same step, and a faded colour's ramp faded in

`AnyGradient.derive(from:in:)` builds `Color.gradient`'s lighter stop the same way —
`rgbToHSL`, then `Color.hsl(hue, saturation, lightness + 15)` — beside a bottom stop that
is the resolved colour itself, alpha intact. So `Color.blue.opacity(0.5).gradient` was a
ramp from alpha 255 to alpha 128, and a ramp interpolates alpha as a fourth channel: a
vertical ramp's alpha varies per row, which `.background` has claimed since §15 and
`Text`'s ink since §34.1. A block with the height to show the ramp was nearly solid at
the top and half-faded at the bottom — an honoured claim of the wrong thing rather than
a missing one — where the colour asked for half all the way down. A one-line `Text`
samples the base stop (see `AnyGradient`'s note) and was already right.

The lighter stop now carries `resolved`'s alpha. Carried and not composed, because
`resolve(with:)` has already multiplied the reference's alpha into any faded palette
slot's, so `resolved` holds the one alpha this ink has and the lighter end is that ink
re-spelled. With both stops equal the ramp's `AlphaShape` is `uniform` rather than
`perRow`, which is the cheaper claim as well as the right one.

### 70.3 The §69.1 assertion, which could not tell a producer from its ancestors

`b9804700` added an assertion to the run walk: a run carrying a translucent per-frame
payload must have no ink or field claim covering its cells, because a producer stating
both would have them folded together and the run faded twice. The rule is real. The
assertion was not a test of it.

`faded` sees the SUM of every producer's claims, and an ancestor states ink and field
claims over a run's cells for entirely legitimate reasons. `.background(Color.blue
.opacity(0.5))` claims a field over its whole box, border rows included;
`.listRowBackground` does the same for a row. The multiply four lines below the assertion
— "MULTIPLIED into what covers it, never replacing" — is exactly the right answer for
those, and could only ever act on the states the assertion forbade. So every debug build
that wrapped an animated border of several alphas, or a focused text field under a faded
palette, in a translucent background trapped on the first frame, on a blend release got
right. Minimal repro, two public modifiers:
`Text("hi").border(AnimatedColor(frames: [.red, faded], step: 0)).background(Color.blue.opacity(0.5))`.

Narrowing it — to a region exactly the run's own rectangle — was considered and not done:
a translucent `.background` on a view exactly as wide as its run is the same false
positive with a smaller window, and nothing at this altitude can tell who stated a
rectangle. The rule belongs where the producer is, and is pinned there: the border's
several-alphas test asserts it states no static claim on its rule rows, and the caret's
per-frame test asserts its field claim rides only on the run.

Found by the 2026-09-12 hunt (entry 17 of `Review-batch-2026-09-12.md`), in the same
branch that added it — the hunt's "holes in the last 30 commits" lens, which has now found
a defect in the preceding work on every hunt this project has run.

### 70.4 A translucent ground, which has nothing behind it

Reported by the owner: moving the alpha channel of `background` on the Example's Theme page
crashed the app instantly. It was the trap §69.2 wrote down and left, reached by the most
direct route there is — every colour picker on that page offers `A`, grounds included.

The page background, the app header's and the status bar's are composite ROOTS. Nothing
inside the app is behind them; only the terminal's own background is, and the framework does
not know its colour. So a translucent root ground has nothing to be composited over, and
every path that spells a colour asserts it is opaque. `RenderBackgroundCodes` spells all
three at the top of every frame, before any view has drawn — hence "instantly" — and behind
it the root `resolvingOpacity(surface:)` calls, the opaque-layer paint in
`compositingOverlays`, and twenty-odd controls that paint `palette.background` directly
would each have trapped in turn. Proven red at the parent:
`OpacityBlend.swift:618: Assertion failed: translucent colour reached sgrBackground: alpha
128`.

Fixed once, at the boundary where a palette enters the environment, instead of at those
sites — twenty-odd being exactly the kind of count §68 exists to distrust. The
`EnvironmentValues.palette` setter hands every palette back unchanged unless one of the three
root grounds is translucent, and wraps that one in `GroundedPalette`, which spends those three
and forwards every other role. Every write to the palette comes through that setter:
`.palette(_:)`, `.tint(_:)`, a theme, and the render loop's own. An ordinary palette pays three
alpha compares at the rare write and nothing on the hot reads.

`overlayBackground` is deliberately NOT spent. It is the wash a modal dims its page with, the
page IS behind it, and §68.5 already claims its field and resolves it there.

**What "spent" means here, and the open question.** With no colour to spend against, spent
means the opaque spelling: the alpha is dropped. That is precisely what a release build
already drew, so no picture changes — the change is that a debug build no longer traps. It
also means the ground's alpha channel does nothing visible yet. The honest way to give it a
meaning is to ask the terminal: `OSC 11 ; ? ST` reports the terminal's default background on
most hosts, and a reported colour is exactly the "what is behind it" this boundary lacks —
`GroundedPalette` would then spend each root ground over it with `spendingAlpha(over:)`, one
line, and keep the opaque spelling where a terminal does not answer. That is a
terminal-specific behaviour with its own measurement to do (which hosts answer, over tmux and
ssh, how late), so it is left for a decision rather than built here.

Proven across the app, not only at the sites read: the Example's
`TUIKIT_EXAMPLE_GROUND_ALPHA` seam fades the four grounds and nothing else, and the faded-
palette sweep, which passes its environment through, runs every page under it.

**Seven claims became no-ops, and the tests that pinned them now say so.** A resize grip's
field, a TabView's panel, mouth and lifted surface (`liftedBackground` derives from
`background` and `appHeaderBackground`, both roots), a coloured switch's knob drawn in the
page's colour, and a mono image's paper all paint a root ground in order to look like the
page. The page now draws opaque, so they match it opaquely — which, over the page, is
visually identical to the claim they used to make. Their tests computed the expected alpha
from the raw `FadedAll` palette while the views read the grounded one through the
environment; they now take it from `GroundedPalette.grounding(_:)`, with the environment
assignment left raw so the boundary is what they exercise. The ground's own commit should
have carried these. Its targeted test run did not include those suites; the full suite did.

## 74. The run and its fallback read one instant (2026-09-13)

§66 left two clocks behind one picture. A spinner or indeterminate bar that leaves a run
took its frame from the cursor timer's content clock, because that is what the loop
replays the run on; one that declines its run took the frame clock, because nothing keeps
the timer running on a page of nothing else. The two did not agree. The timer's clock was
a sum of the sleeps it had asked for, zeroed whenever the loop stopped it, while the frame
clock is `MonotonicClock`. Two spinners side by side, one on each path, could draw
different steps in the same frame, and a bar that moved between the paths (a tint fading
it) jumped.

The timer is now measured. `.content` is `MonotonicClock` itself, with no origin of its
own; `.cursor` is that reading less the moment the focus last moved, floored to the 50 ms
lattice. Every render shows the timer its `frameNowNanos` before anything in the frame
reads a phase (`CursorTimer.observe(nowNanos:)`, called by the run loop before it reads the
breath and again at the top of `RenderLoop.render`), and a replay reads the snapshot its
wake took. So at render time `elapsed(.content) == frameNowNanos / 1e9`, and the run path
and the fallback draw the same step.

**One instant by convention, not by construction.** The snapshot is taken with `max`, so
it never runs backwards. That keeps a wake queued behind a later render from rewinding the
phases, and it also means a caller that stamps a frame EARLIER than a time the timer has
already seen keeps the later one, and the two clocks then differ. Production cannot do
that: `FrameClock.nowNanos` and the timer's own `nowNanos` both read `MonotonicClock`, and
each frame observes its own stamp first. A test stamping frames by hand has to keep them
ahead of anything the timer has seen.

The test renders a same-width `.custom("ab")` beside a mixed-width `.custom("-你")`, both
at 0.12 s, through `RenderLoop` at six advancing frame times, and requires the two to show
the same frame index every time. Before, with the timer never started as a unit test
leaves it, the run-backed one drew `a` in every frame while the other stepped.

**With the clocks agreeing, the §66 branch had nothing left to choose between, and it is
gone.** `Spinner` and `ProgressView` draw their own frame from `frameNowNanos` on both
paths; only the replay reads the timer. That also fixes a case the branch never covered:
a render with no cursor timer at all — a snapshot, a test — drew a run-backed spinner's
or bar's first frame whatever its frame time, because the timer's absence read as zero.
Tested through `RenderLoop` with no timer: a same-width `.custom("ab")` at four frame times
shows `a b a b`, and an opaque indeterminate bar changes between frames. Measured on the
Spinners page against the commit before, the change is nil, as it should be: the value
read is the same number.
