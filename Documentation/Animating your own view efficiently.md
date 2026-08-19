# Animating your own view efficiently

*Scoping note, 2026-08-19. Nothing here is implemented beyond what §2 says is
already public; §5 is a menu of options, not a plan.*

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

### 5.1 Publish what already works, and document it

Make `View.animatedCells(_:)` public; publish a styled-string helper (a narrow
public face on `ANSIRenderer.colorize`, not the whole type); add a DocC article
built around the `Renderable` recipe in §2.

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

### 5.3 Automatic runs by diffing pre-rendered phases

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

## 6. Recommendation

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

## 7. What is still on the live clock

Independent of the above, these built-ins still resolve a live
`SelectionEmphasis` while rendering and so still force a full render per tick.
Each is a straight conversion of the kind already done a dozen times:

| producer | where |
|---|---|
| `scrollIndicatorEmphasis` — the "N more above/below" lines | `_ListCore`, `Table` (`scrollIndicatorCycle` already exists, unused) |
| `heldSlotBackground` — the keyboard reorder hold | `_ListCore` |
| `DropdownMenuRenderer` — the pop-up menu's highlight | `DropdownMenuRenderer.swift` |
| `Color256Grid`, `SwatchGrid` — the cursor marker | the colour-picker panel |
| `ContextMenuTarget` | `Example` — blocked on §3.2, i.e. on 5.1 or 5.2 |

`grep -n 'SelectionIndicator.resolve\|selectionEmphasis(' Sources/` is the
running list: the direct call is the expensive route, `.cycle(` is the cheap
one.
