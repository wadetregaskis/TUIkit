# Opacity as composition, not as a blend

**Status: exploration, 2026-08-24. Nothing here is implemented.** Commissioned
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

**Recommendation: α ≥ 0.5, with α = 0 special-cased to draw nothing at all.**
The midpoint rule is what a dissolve does, the special case is what makes
`opacity(0)` mean what SwiftUI says it means, and both are one comparison.

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
