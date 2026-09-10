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
| `.foregroundStyle(…opacity(…))` on anything but a plain `Text` | `Divider` and `Spinner` — **fixed, §19**; `RadioButton` and `_ToggleCore`'s indicators — **fixed, §23**; `Table` and `PaintRenderer`'s flat arm open |
| `.tint(…opacity(…))` | `TintedPalette.accent`, and from there dozens of controls — **fixed, §21**; it was inconsistent, `restingControlFace` consuming the alpha while `accentPulse` carried it |
| `String.styled(foreground:…)` | the documented escape hatch for a reader's own `Renderable` — **answered, §26.1** |
| `.listRowBackground(…)` | one site — **fixed, §22** |
| `Text` concatenation | **fixed, §14** |
| translucent gradient stops | **background fixed, §15**; `Text`'s ramped ink open |
| `TrackConfiguration(emptyColor:)`, `SegmentColoring` | `TrackRenderer`, 3+ sites |
| `StatusBarState.highlightColor` / `.labelColor` | 2 sites — **fixed, §24** |
| `.style(.text) { $0.foreground = … }` | the cascade's non-`Text` readers |
| `.colorMultiply(…)` | a silent drop, not a trap — **fixed, §25** |
| `ColorPicker` with a translucent binding | the swatch was **already right, §26**; `supportsOpacity` is a real parity gap and stays open |

Plus a whole second tier: `Palette` is a public protocol of plain
`var …: Color { get }` members, and nothing normalises what a custom palette
returns. One `.clear` in a palette reaches everything. (§18 closes the `border`
role of it — every box the framework draws. §20 fixed the reason it reached
*nothing*: `resolve(with:)` was discarding a slot's alpha outright.)

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
whose alpha is uniform or varies only down the page; `Text`'s single-style arm;
`Text`'s attributed-run arm; `.opacity(_:)` on a view (all three channels);
`ShapeStyle.opacity(_:)` and `Color.opacity(_:)`, which now agree; `.border` and
every box the framework draws through `BorderRenderer` (§18); `Divider` and
`Spinner` (§19); a `Toggle`'s and `RadioButton`'s own indicator glyphs (§23);
`.listRowBackground` (§22); the status bar's two configurable colours (§24);
`.colorMultiply` (§25).

Not honoured, each loud at its own line: everything in §16.1 not marked fixed,
`Text`'s ramped ink, and per-cell ramps.


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
*now* would resolve every later phase at the wrong alpha. The claim is therefore
made only for a still colour; the animating arm stays unhonoured and stays loud —
its frames reach the emitter as they are, so the assertion fires on a translucent
phase. Honouring it means a phase-indexed alpha, which is what `OpacityCycle`
already is for a layer fade; the pieces exist and the wiring does not. The
drop-down menu is in the same position, and always animating by default, so in
practice its chrome is the still arm only when the emphasis is `.none`.

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
rectangle can say what is true; it stays unhonoured and stays loud.
`ForegroundStyleAlphaTests.bouncingSpinnerDeclined` puts that on the record so it
reads as a decision rather than an omission.

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

As everywhere else in this design, a pulsing indicator claims nothing: the run
repaints those cells from its own frames, and a region carrying the phase drawn now
would resolve every later phase at the wrong alpha.


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
the app header's side payloads.

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

1. **A `cycle`-bearing region** — a repeating `.opacity` fade. Those runs are dropped
   (`covering.allSatisfy { $0.cycle == nil }`), because the fade's phases and the
   run's frames tick independently and their product is not one run.
2. **A pulse whose phases have different alphas** — which was this bug, in four
   places, and is now none.

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
cells genuinely differ: the selection's two colours are opaque by construction
(`selectionColors` goes through `opacity(_:over:)`), the entered text's are the
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

Row 8 of §16.1 — `TrackConfiguration(emptyColor:)` and `SegmentColoring` — said "3+
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
translucent `TrackConfiguration.emptyColor` must resolve `inkOpacity == 1,
fieldOpacity < 1` — solid glyph, faded remainder.

This is the cell that proves the two channels earn their keep. A single alpha per cell
gets it wrong in *both* directions, and `boundaryCellSplitsItsChannels` pins it.

### 31.2 A track's per-cell gradient is honourable, unlike a page's

§15 declines `perCell` ramps because a 2-D ramp needs a region per cell and the
resolver's fold is a linear scan per column. A track is **one row**, so per-cell alpha
is a run of one-cell rectangles rather than a grid — 10 to 40 of them, not 80 × the
height. So `.threeSegment(coloring: .gradient(…))` with translucent stops is fully
honoured, and so is a per-cell `emptyGradient`. A narrower result than §15's, and the
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
  `emptyColor` and `accentColor` do not. Still loud.
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