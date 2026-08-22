# Animating your own view efficiently

*Scoping note, 2026-08-19. **Status: §6.1, §6.2 and §6.4 are done.** §6.3 was
attempted as part of §6.4 and turned out to be unsound in its general form —
see §5.3 and §8. The standing constraint below is answered in §8: the
TUIkit-specific spellings stay, and now for a reason rather than by default.*

*Standing constraint on §6.4: when the SwiftUI-style API can do all of this
correctly and at the same cost, the TUIkit-specific spellings it replaces —
``AnimatedColor``, `animatedCells(_:)`, `SelectionEmphasisCycle` — come out.
They are steps toward that, not a parallel surface to maintain beside it.*

## 1. The question

Every built-in control that breathes while focused has been converted from
"read the animation clock while rendering" to "hand the run loop a finished
cycle" (see `AnimatedCellRun`, and the ledger in
`Documentation/Performance-profile-2026-08.md`). The win is large and
consistent: a page whose only animation is one focused control drops from
~20 full render passes a second to the resting heartbeat, because the loop
advances the animated cells by splicing pre-rendered frames over the frame
already on screen instead of walking the view tree.

The question is whether an app — the `Example` target, or any downstream
package — can do the same for a view of its own, and if not, what it would
take.

## 2. What is public today

More than I expected, and less than is useful. Verified by compiling the
following inside `Example`, which is a separate module and sees only TUIkit's
public API:

```swift
struct MyIndicator: View, Renderable {
    let cycle: SelectionEmphasisCycle
    let dim: Color
    let bright: Color

    var body: Never { fatalError("renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: ["●"])
        if let run = cycle.run("●", dim: dim, bright: bright, offsetX: 0, offsetY: 0) {
            buffer.animatedCells = [run]
        }
        return buffer
    }
}

struct MyControl: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    var body: some View {
        MyIndicator(
            cycle: emphasis.cycle(isFocused), dim: palette.border, bright: palette.accent)
    }
}
```

That compiles and works. `Renderable`, `FrameBuffer.animatedCells`,
`AnimatedCellRun`, `AnimationClock`, `SelectionEmphasisCycle` and its `run`
overloads, `\.isFocused` and `\.selectionEmphasis` are all public and all
re-exported from `TUIkit`.

So the answer to "is the mechanism available at all?" is **yes**. The answer to
"can an app be as efficient as the built-ins?" is **yes in principle, no in
practice**, for three reasons.

## 3. The three gaps

### 3.1 A composed view has nowhere to put a run

The example above works because it is a `Renderable` — it owns a buffer. A view
whose body is other views does not, and that is the ordinary way to write one.
The framework hit this itself with the colour swatch and added
`View.animatedCells(_:)`, which attaches runs to whatever the body rendered to.
That modifier is **internal**.

Making it public is a one-line change. It is not sufficient, because of 3.2.

### 3.2 The view that knows the cycle does not know where its cells are

`Example`'s `ContextMenuTarget` is the case that exposes this, and it is the
documented answer to "my own view is the focusable thing — how does it show
that?":

```swift
Text(title)
    .padding(.horizontal, 1)
    .border(borderColor)          // ← this is what pulses
```

The cells that breathe are the border's, and the border is drawn by a modifier
*around* this view. Its geometry — where the top row is, how wide, which
columns the side walls occupy — is not known until after layout, and is never
known to the view that decided the colour. There is no offset for the author to
pass to `animatedCells(_:)`, however public it is.

The framework's own answer for the focus-section `●` was to move the *decision*
down to the thing that draws: `FocusIndicatorEmphasis` (the cycle and its two
endpoints) travels in the environment, and `ContainerViewCore` — which knows
exactly which cell the ● landed in — emits the run. That works, and it is
per-feature plumbing, not a general mechanism.

### 3.3 A hand-written `Renderable` cannot style a string

`ANSIRenderer` and `BorderRenderer` are internal. An app writing its own
`Renderable` can render child views (`TUIkitView.renderToBuffer(_:context:)` is
public, though it needs the module qualifier because the instance method of the
same name shadows it) but cannot ask the framework for "this glyph, in this
colour" or "a top border of this width" without hand-writing escape sequences —
and getting the self-contained-cell discipline right, which is exactly the trap
that produced the replay-accumulation bug (see `AnimatedCellRun`'s notes).

## 4. How SwiftUI does it

SwiftUI has **no** equivalent of "here are my pre-rendered frames, replay them
without calling me back". Nothing in its public API corresponds to
`AnimatedCellRun`.

It does not need one, and *why* is the useful part. SwiftUI's animation model is:

- You declare a property `Animatable` (or use a built-in that already is).
- You change it inside `withAnimation`, or attach `.animation(_:value:)`.
- SwiftUI hands the interpolation to Core Animation, which runs it **on the
  render server**. Your `body` is not re-evaluated per frame.

So the efficiency comes from a mechanism the app never calls directly. The app's
side of the contract is a *declaration* — "this value is animatable" — and the
framework does the rest. The true analogue of `AnimatedCellRun` is one layer
further down: `CAKeyframeAnimation`, where you hand the render server the whole
sequence and it plays it without you. SwiftUI compiles down to that; it does not
expose it.

The two SwiftUI APIs that *look* relevant are both the expensive path:

- **`TimelineView(.animation) { context in … }`** re-evaluates its content on a
  schedule. In TUIkit terms that is precisely "read the clock while rendering" —
  the thing being replaced. It exists for content that genuinely cannot be
  described as an interpolation (a clock face, a particle field), and is
  usually paired with `Canvas` to keep the re-evaluated subtree small.
- **`PhaseAnimator(phases) { content($0) }`** and
  **`KeyframeAnimator(initialValue:keyframes:)`** (iOS 17+) are declarative
  *sequences*: you describe the content at each phase and SwiftUI animates
  between them. The content closure is evaluated per phase, not per frame.

`PhaseAnimator`'s shape is worth stealing, because in a terminal the phase set
is finite and small (a pulse is 16 frames at the regular speed, 10 fast, 24
slow) — small enough that rendering the content once per phase is affordable,
which is what would let the framework extract runs without the author computing
a single offset.

## 5. Options

Roughly in order of cost, and they compose — 5.1 is a prerequisite for nothing
and 5.4 subsumes 5.2.

### 5.1 Publish what already works, and document it — **DONE**

Make `View.animatedCells(_:)` public; publish a styled-string helper (a narrow
public face on `ANSIRenderer.colorize`, not the whole type); add a DocC article
built around the `Renderable` recipe in §2.

Shipped as `View.animatedCells(_:)`, `String.styled(foreground:…)` and the
`AnimatingYourOwnView` article. A fourth thing turned out to be missing and went
with it: `.focusable()` made a view a Tab stop and never published
`\.isFocused`, so an app's own control could hold the focus with no way to say
so. `PublicAnimationAPITests` imports TUIkit *without* `@testable`, so the
recipe is checked against the surface an app actually sees.

- **Buys:** the ceiling. Anything the built-ins can do, an app can do.
- **Costs:** public API surface that hands out a footgun — a run whose offset,
  width or frame set disagrees with the drawn cells repaints the wrong thing
  forever, and looks plausible while doing it. `FocusIndicatorAnimationTests`
  exists because that keeps happening *to us*.
- **Verdict:** worth doing regardless, as the escape hatch. Not the headline
  answer, because it does not solve 3.2 at all.

### 5.2 An animated colour, accepted where colours are accepted

```swift
let pulse = emphasis.cycle(isFocused).color(dim: palette.border, bright: palette.accent)
Text(title).padding(.horizontal, 1).border(pulse)
```

where `pulse` is an `AnimatedColor` — a cycle plus two endpoints, or in general
a `[Color]` on a named clock. `.border`, `.background`, `.foregroundStyle` and
friends take it, and *they* emit the runs, because they are the ones that know
which cells they painted.

- **Buys:** exactly the `ContextMenuTarget` case, with no offsets anywhere in
  app code. Also the built-ins' own remaining plumbing —
  `FocusIndicatorEmphasis` becomes an instance of this rather than a bespoke
  environment value.
- **Costs:** one overload per drawing modifier, and each has to actually emit
  correct runs (the same discipline as any conversion, but now in the modifiers
  rather than in the controls). `AnimatedColor` needs a resting colour for
  measurement and for terminals with no animation.
- **Open question:** whether `AnimatedColor` should be a distinct type or
  whether `Color` itself gains an animated case. A distinct type keeps `Color`
  a value; a `Color` case means every existing modifier gets it for free but
  every `switch` over colours has to answer for it.

**DONE**, as a distinct type — which is also the right shape for something
meant to be deleted when §5.4 lands. `.border(_:style:width:)` takes one;
`ContextMenuTarget` went from 4.8% of a core to 0.2% with the target focused.
`FocusIndicatorEmphasis` was retired onto it, as predicted.

Two things learned in the doing. A border is not one run: the rules are whole
lines (rebuilt through the same `BorderRenderer` calls, so a title comes along)
and the walls are two single cells per row sharing one frame set. And a focus
section's ● lives *in* the top border's line, so when the border animates the ●
must be folded into those frames rather than left as a second claim on the same
cell.

The cost of a *still* `AnimatedColor` is the thing to watch: every bordered
container in a frame builds one, and the first cut stored it as a one-element
array — +1.1% per frame on `table`. It stores a constant as a colour now.

### 5.3 Automatic runs by diffing pre-rendered phases — **attempted; unsound in general**

```swift
PhaseAnimator(emphasis.cycle(isFocused)) { phase in
    Text(title)
        .padding(.horizontal, 1)
        .border(phase.color(dim: palette.border, bright: palette.accent))
}
```

The framework renders the closure once per phase, diffs the resulting buffers
cell by cell, and emits an `AnimatedCellRun` for every span that differs. The
author writes an ordinary view and never sees a run, an offset or a clock.

- **Buys:** the general case, including anything the modifiers of 5.2 do not
  cover — a glyph that changes shape, a spinner, a chip whose width is stable
  but whose content is not. And it is the SwiftUI-shaped API, which matters for
  the parity rule.
- **Costs:** N renders of the subtree per render pass, N = 10–24. Acceptable for
  a focus indicator; not for a large subtree. Mitigations: memoise on the
  phase-independent inputs so the N renders happen only when something else
  changed; cap N; refuse (and say so) when the phases disagree on *size*, since
  a run cannot change a buffer's shape.
- **Risk:** the diff is the correctness boundary. Two phases whose lines differ
  in ANSI bytes but not in visible cells would produce runs that emit bytes to
  no effect — the ~12% byte overhead already known from the replay path, but
  multiplied. The diff must compare rendered cells, not strings.

**The cost this scoping missed, and it is the decisive one.** "N renders of the
subtree" is not N times the CPU — it is N times every *side effect* a render
performs. A render registers focus, publishes hit-test regions, fires
`onAppear`, writes preferences, declares animation rates. Sixteen phases would
register a control's focus sixteen times and appear it sixteen times. There is
no `isRehearsing` flag that fixes this either: suppressing side effects would
also change what several views *draw* (a measure-mode render reports natural
sizes and skips focus rings), so the phases would no longer be the picture the
real render produces — and a run that disagrees with the drawn cells is the one
failure mode this whole mechanism has.

So the general form is out. What shipped instead is the **narrow** form, which
is sound and covers the case that matters: a modifier whose output is a pure
re-styling of a buffer its content already produced renders that content ONCE
and re-colours the finished lines per phase. `AnimatedBufferCycle` is that, and
`.opacity(_:)` is its first user — a `withAnimation(.repeatForever)` fade costs
no render passes at all. Anything whose phases differ in what is *drawn* rather
than in how it is coloured is pointed at §5.1 instead, where the author knows
each phase and nothing is rendered sixteen times.

### 5.4 Make it implicit, the way SwiftUI does

The endpoint 5.2 and 5.3 both point at: an app declares a value animatable, and
the framework decides how to serve it — pre-rendered runs when the value is
finite and the geometry is stable, a re-render when it is not. `.animation(_:)`
and `withAnimation` would then mean something in TUIkit, and the run machinery
becomes an implementation detail nobody outside the framework names.

That is a much larger piece of work and it needs the interpolation model first
(`Animatable`, a real animation curve type, a transaction). Worth naming as the
destination so 5.2 and 5.3 are built as steps toward it rather than as
alternatives to it.

**DONE.** `withAnimation`, `Animation`, `Animatable`, `VectorArithmetic`,
`Transaction`, `.animation(_:value:)` and `.transaction(_:)` all exist and match
SwiftUI's signatures; see the `Animation` article. What it does *not* do is make
the run machinery an implementation detail nobody outside the framework names —
see §8.

## 6. Recommendation

*(1 and 2 are done; 3 and 4 stand as written.)*

1. **5.1 now** — it is small, it unblocks anyone who needs the ceiling today,
   and the escape hatch should exist whatever else is built. Publish
   `animatedCells(_:)`, publish a colorize helper, write the article.
2. **5.2 next** — it is the smallest change that makes the *documented* pattern
   cheap, which is the actual complaint. It also retires
   `FocusIndicatorEmphasis` as a special case.
3. **5.3 when something needs it** — a spinner or a phase-changing glyph in an
   app, rather than speculatively. The diffing machinery is the interesting
   half and should be built against a real case.
4. **5.4 as the stated destination**, gating on wanting `withAnimation` at all.

## 7. What was still on the live clock — **all converted, 2026-08-19**

The list this section used to hold is empty. Every producer named in it now
builds a cycle and hands the loop pre-rendered frames:

| producer | what it needed |
|---|---|
| The "N more above/below" indicators (`_ListCore`, `Table`) | the cycle overload `ScrollView` was already using; `scrollIndicatorEmphasis` deleted with its last caller |
| `DropdownMenuRenderer` | the whole popup redrawn once per cycle point, one run per line — every line carries border cells, so every line moves |
| `Color256Grid`, `SwatchGrid` | one run over the cursor swatch, at the placement each already records |
| `_ListCore`'s held reorder slot | `SelectableListRow.backgroundOverride` became a `RowBackground`, so it goes through the cursor row's machinery |
| `Example`'s `ContextMenuTarget` | `.border(AnimatedColor)` — §5.2 |

`grep -n 'SelectionIndicator.resolve\|selectionEmphasis(' Sources/` now finds
exactly one hit: `SelectionEmphasisClock.callAsFunction`, the public
this-tick's-colour route. That one stays. It is the simplest thing an app can
write, it is correct, and the article says plainly what it costs and what to
reach for instead. Deleting it would leave no easy answer to "just give me the
colour" — and the whole point of the cheap path is that it is a choice, not a
tax on understanding the machinery.

A sweep of every page in `Example`, at three different focus positions each,
reports zero clock reads while idle.

**One producer was missing from that list**: `TextEditor`'s caret, left on the
live clock on the grounds that its multi-line geometry made it different, and
its scrollbar with it. It was not different — the caret's row and column are
arithmetic the row walk already did — and leaving it there cost 6.7% of a core
for a focused editor against 0.2% for a focused `TextField`. Both converted
2026-08-21, together, because either half alone is wrong over time: the caret
alone leaves the editor re-rendering for the bar, and the bar alone leaves its
runs replaying over a screen the caret is still repainting. See
`Performance-profile-2026-08.md` §15.


## 8. What §6.4 turned out to be, and what stays

`withAnimation` works, and the answer to the standing constraint is: **the
TUIkit-specific spellings stay.** Not for want of trying to retire them — three
things came out of building it that the scoping above could not have known.

**A terminal has no render server.** SwiftUI's efficiency comes from handing an
interpolation to Core Animation, which runs it without re-evaluating a body.
There is nothing here to hand it to, so an animating subtree really is walked
once per frame. That is fine, and bounded, for a *change*: 30 Hz for the
animation's duration, eight passes for a quarter-second ease, then nothing. It
is not fine forever, and `repeatForever` is exactly forever.

**The cheap path exists but is narrow, and narrow for a good reason** (§5.3
above): only a pure re-styling of one render can be pre-rendered soundly.
`.opacity` qualifies. A glyph that changes shape, a spinner, a chip whose
content changes — none do, and no amount of API design makes them.

**The focus pulse is not an app animation.** It is a shared affordance on one
clock, phase-locked across every element showing focus, its cadence chosen by
`SelectionIndicatorStyle` rather than by the call site. Rebuilt on
`withAnimation(.repeatForever)` it would be per-element and phased from
whenever each element started, so a section's border and the control inside it
would drift apart — which is the exact bug that merged the two clocks into one
in the first place.

So the division is now a real one rather than a transitional one, and both
articles say it in the same words: **`withAnimation` is for changes; the run
machinery is for decorations.** `AnimatedColor`, `animatedCells(_:)` and
`SelectionEmphasisCycle` are the decoration half, they are documented as such,
and they are not redundant.

### What it cost

A paired A/B (41 reps, `ab_bench.py`) against the commit before the animator:

| scenario | change | verdict |
|---|---|---|
| `table` | +0.8% | slower |
| `deep` | +0.6% | slower |
| `kitchensink` | +0.7% | slower |
| `megalist` | +0.3% | indistinguishable |

Down from ~1.0–1.4% after three rounds of work — see the commit "Animating cost
every app 1% of a frame, animating or not". Three things were paying it and only
one was the obvious one: the per-view conformance check (now a static `View`
witness), an unconditional rebinding of the view value that copied the struct on
every render (now a `nil`-returning resolution and a branch), and three new
`EnvironmentValues` entries in a dictionary that is copied down the whole tree
(now one `AnimationFrame`).

The residual is spread thin — a witness call, one function call, one dictionary
entry — and the remaining candidates all trade a correctness hole for it.


## 9. A run does not decorate the cells — it *replaces* them

The failure this section exists for looked like a hover bug and was an
animation bug. A focused `ScrollView`'s scrollbar answers the pointer by
lifting the cell under it a step brighter, and it breathes the accent through
`AnimatedCellRun`s. Both were right on their own. Together the lift appeared
for one frame and then vanished, and did not come back while the pointer sat
there — because the runs are the bar from the first tick onward, and they had
been built by a constructor that knew about the cycle and nothing else.

`ScrollbarColors` had two makers: `focusIndicating(isFocused:hoveredCell:context:)`
for the drawn bar, and `accented(_:palette:)` for one frame of the cycle. The
second was missing a field the first had. Nothing in the type system noticed,
because a missing hover is a `nil` that reads as "no pointer here".

The rule, stated so it generalises:

> **Every input to the drawn cells is an input to the run that replaces them.**
> A run is not the animation layered over a picture; it *is* the picture, at
> each phase. Any state the static draw consults — the pointer, the selection,
> the disabled flag — must be threaded into the frame builder too, or the first
> tick paints it away.

Two things follow, and both are cheap:

- **Build the frames with the same function that draws the cell**, given a
  different colour. `_ListCore` does this (`cycle.colors(…).map { lines(over: $0) }`
  calls the very function that produces the still row) and cannot drift.
  Anything with a second, parallel constructor can, and did.
- **Give the animation's colour inputs one owner.** `accented(_:palette:)` is
  gone; `ScrollbarPulse` — cycle, hovered cell, palette — is the only thing
  that builds a frame's colours, and `focusPulse(isFocused:hoveredCell:context:)`
  is the only way to get one. A defaulted `hoveredCell: Int? = nil` would have
  been the same bug with a nicer signature: it compiles at every call site and
  is wrong at the ones that forgot. Now the pulse cannot be constructed without
  answering, and its call sits directly beside the `focusIndicating` call it
  has to agree with.

**Why the tests did not catch it.** `ScrollbarFocusPulseTests` already asserted
that replaying a run changes nothing — the right property — but compared
`.stripped` lines, which discard exactly the SGR bytes the lift lives in. The
assertion was about glyph placement and read like an assertion about the cells.
A test for this class has to compare raw bytes, and `ScrollbarHoverPulseTests`
does, driving a real pointer through the real dispatcher and hovering the cell
the bar *itself* nominated as animated.

Confirmed live as well as in test: with the pointer parked on the bar's top
arrow, the cell's foreground before the fix stepped through the plain accent
breath (`62f662`, `49b849`, `276127`, `0e230e` — the un-hovered tones) and after
it through the lifted one (`c6f3c6`, `a9ffa9`, `8fbf8f`, `767f76`), never
falling back.
