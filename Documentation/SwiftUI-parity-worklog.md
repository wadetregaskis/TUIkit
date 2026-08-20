# SwiftUI parity work log

*A running record of what I am doing, what I decided and why, and what I would
like a second opinion on. Newest at the bottom. Questions are marked **Q** —
none of them block me; each says what I did in the meantime.*

## 2026-08-19 — animation

### Done

| | |
|---|---|
| `withAnimation`, `Animation`, `Animatable`, `VectorArithmetic`, `Transaction` | shipped |
| `.animation(_:value:)`, `.transaction(_:)`, `Binding.animation(_:)` | shipped |
| `Animatable`: `.opacity`, `.offset`, `.padding`, fixed `.frame`, `EdgeInsets`, `UnitPoint`, `CellSize`, `CellRect`, any app `ViewModifier` | shipped |
| Colour fades on `.foregroundStyle` / `.background` / `.border` | shipped |
| `.transition(_:)` with the seven built-in effects | shipped |
| `repeatForever` on `.opacity` served by pre-rendered runs (no render passes) | shipped |
| Example page, Stress scenario, DocC article, parity re-baseline | shipped |

### Decisions worth a second look

**1. Colours do not go through `Animatable`.** A semantic `Color` is not
components until it meets a palette, and `animatableData` has no palette. So
the painting modifiers ask a helper at render time instead. SwiftUI solves the
same problem the same way (an internal resolved-colour type). App-facing API is
unchanged.

**Q1.** `Text.foregroundStyle(_:) -> Text` still does not fade — that overload
carries the colour in the view *value*, so no modifier is left to ask. Making it
fade means a store lookup per `Text`, which is the most-rendered view there is.
*Meanwhile:* documented on the modifier and pinned by a test. I think the cost
is not worth it, but you may disagree.

**2. Removal transitions need a surviving slot.** An `if` inside a stack has
none: a stack asks children to flatten and a `nil` optional flattens to *no
children*. Such a view animates in and jumps out.

**Q2.** Fixing it means an optional keeping a slot of its own rather than
flattening — which moves identities and stack spacing under every `if` in every
existing app. Worth doing as its own piece of work?
*Meanwhile:* documented and pinned by a test that asserts the jump.

**3. `PhaseAnimator` / `KeyframeAnimator` are recorded as not-implemented**,
with the reason: pre-rendering a subtree once per phase runs its render *side
effects* once per phase too. That is the same thing that killed the general
diffing engine in `Animating your own view efficiently.md` §5.3.

### Performance

Everything is A/B'd against the commit before the animation work
(`ab_bench.py`, 41 reps, paired, order randomised).

| stage | `table` | `deep` | `kitchensink` | `megalist` |
|---|---|---|---|---|
| first cut | +0.8% | +1.0% | +1.0% | ~0 |
| after three rounds | +0.7% | +0.6% | +0.7% | ~0 |
| after `.padding`/`.frame` became animatable | +1.4% | **+14.0%** | +1.8% | +1.0% |
| after the generic witness | +0.7% | +7.6% | +1.0% | +1.4% |
| after the store stopped rebuilding its tables | ~0 | **+7.5%** | ~0 | ~0 |

The +14% is the lesson of the batch: `view as? any Animatable` **boxes**, and
with layout modifiers animatable that is a heap allocation per layout node per
walk — on a tree whose whole shape is nested layout, measured O(depth²) times.
Replaced with a static `View._animated` witness where `Self` is concrete, so
nothing is boxed and nothing is cast back. A second round stopped
`endRenderPass` rebuilding a whole dictionary per pass and stopped
`beginRenderPass` sweeping every record to clear a flag almost none of them set.

`table`, `kitchensink` and `megalist` — the three that look like real app
shapes — are now **indistinguishable** from before any of this existed.

**Q3.** `deep` stays at **+7.5%**, and I have stopped chasing it. It is the
deliberately pathological scenario: nested layout modifiers, re-measured once
per enclosing level (O(depth²)), so every animatable `.padding` / `.frame` pays
a store probe that many times. The only remaining fix is a per-frame "could
anything animate at all?" gate that skips the probe — and it is not sound as
designed, because a record has to exist BEFORE a change in order to know what
the value was before it. Every gate I tried either drops the first animated
change or is open permanently once an app animates anything once.
*Meanwhile:* accepted and recorded. My read is that a 7.5% on the deep-nesting
stress case is a fair price for `.padding`/`.frame` animating at all, given the
realistic shapes measure clean — but it is a judgement call and it is yours.


## 2026-08-19 — parity, continued

Working down the gap list, picking the ones a character grid can honour
*exactly* rather than approximately.

### Done

- **Seven colour effects**: `.brightness`, `.contrast`, `.saturation`,
  `.grayscale`, `.hueRotation`, `.colorInvert`, `.colorMultiply`. These sound
  graphical and are not — each is a function from colour to colour, and a
  terminal names its colours explicitly in escapes it has already emitted.
  `.opacity`'s SGR walk turned out to be the general case and became one
  (`SGRColorRewrite`). All animatable, all size-neutral.
- **`Angle`**, which comes with `.hueRotation` and is the one place a geometric
  type earns its keep here: a hue *is* an angle, so this rotates colours exactly
  while nothing about the cells moves.
- **`.position(x:y:)` / `.position(_:)`** — the absolute counterpart to
  `.offset`, including SwiftUI's rule that a positioned view fills the space it
  is offered.
- **`Binding.animation(_:)`**.

A/B after the colour effects: `table`, `megalist`, `kitchensink`
indistinguishable. (`deep` unchanged at its known +7.7% — see Q3.)

### Pulled before shipping

**Q4.** `.background(alignment:content:)` — I wrote it and then took it out,
because "draw this *behind* that" has no honest meaning when every cell is
opaque. SwiftUI's background shows through wherever the content is transparent;
here the content's spaces are cells like any other, so a background under
`Text("Total")` is simply covered by the word. The options are (a) treat a
space in the content as transparent, which is a real and defensible rule but a
new one, (b) ship it as "visible only where the content is shorter", which
would be surprising, or (c) leave it out. I left it out.
*Meanwhile:* `.overlay(alignment:content:)` already exists and is unambiguous,
and `.background(_ color:)` covers the common case.

### Not attempted, and why

- **`deleteDisabled(_:)` / `moveDisabled(_:)`** — these belong on the ROWS of a
  `ForEach`, read by the enclosing `List`'s delete/reorder machinery. TUIkit has
  `onDelete` / `onMove` on `ForEach` itself, so wiring a per-row veto means
  threading an environment value through the reorder host. Worth doing; wants
  more room than the end of a batch.
- **`labelsHidden()` / `labelsVisibility(_:)`** — cheap to add, but only
  meaningful once `Toggle`, `Slider`, `Stepper`, `Picker` and `DatePicker` all
  honour it. Adding the modifier without that is the "silently does nothing"
  shape I have been avoiding all session.
