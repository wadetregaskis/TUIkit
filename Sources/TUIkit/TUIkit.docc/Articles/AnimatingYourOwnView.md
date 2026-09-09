# Animating Your Own View

Make a view of your own breathe, blink or pulse without re-rendering the screen
to do it.

## Overview

> Note: This is the low-level route. For animating a *change* — a value moving
  from one number to another because something happened — reach for
  <doc:AnimatingChanges> first: ``withAnimation(_:_:)`` and ``View/animation(_:value:)``
  need no offsets, no clocks and no runs. What follows is for a **decoration**:
  something that moves for as long as it is on screen, which is the one shape
  `withAnimation` cannot serve cheaply unless it is a pure re-colouring.

The terminal has no compositor. Anything that changes on screen changes because
something wrote to it, and the naive way to animate — ask what time it is while
you render, and render again on a timer — costs a full pass over the view tree
for every frame of the animation. One focused control doing that puts the whole
page through measure, layout and render ten to twenty times a second to
recolour a single cell.

TUIkit's built-in controls do not work that way, and neither do yours have to.
The idea is to render the animation *once*, as a finished sequence of frames,
and hand it to the run loop. The loop then advances it by splicing those frames
over the frame already on screen — no view involved, no tree walked.

The shape of it:

| You want | You do |
|----------|--------|
| A cell whose **colour** varies over the focus pulse | Ask for the *cycle*, not the phase; leave an ``AnimatedCellRun`` |
| Something a **modifier** paints (a border) | Hand it an ``AnimatedColor`` and let it place the runs |
| Anything else | Render each frame yourself and describe the spans that differ |

## Say when you are focused

Start with the question that usually prompts this: your view is the focusable
thing, so how does it show that it has the focus?

``View/focusable(_:)`` makes any view a Tab stop, and publishes
``EnvironmentValues/isFocused`` to its content so the view can say so.
``EnvironmentValues/selectionEmphasis`` turns that into the same affordance
every built-in control uses, on the same clock, honouring whatever
``View/selectionIndicatorStyle(_:speed:)`` is in force — pulse, blink, or a
static accent. Neither decision is yours to make:

```swift
struct Target: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    var body: some View {
        Text("Pick me")
            .foregroundStyle(emphasis(isFocused).color(
                dim: palette.foregroundTertiary, bright: palette.accent))
    }
}
```

That is correct, and it is the expensive path: ``SelectionEmphasisClock`` called
as a function reads the animation clock *while rendering*, which tells the run
loop this frame consumed it — so the only way to advance the pulse is to render
again. Everything below is about not doing that.

## Ask for the whole cycle

``SelectionEmphasisClock/cycle(_:)`` gives you every frame of the animation
instead of the one showing now. It computes them from a static formula, so
nothing about your view's appearance depends on *when* it rendered — which is
exactly what makes the frames replayable.

Draw ``SelectionEmphasisCycle/colorNow(dim:bright:)`` for the frame on screen,
and leave a run behind for the rest:

```swift
struct FocusDot: View, Renderable {
    let cycle: SelectionEmphasisCycle
    let dim: Color
    let bright: Color

    var body: Never { fatalError("renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(
            lines: ["●".styled(foreground: cycle.colorNow(dim: dim, bright: bright))])
        buffer.animatedCells = [
            cycle.run("●", dim: dim, bright: bright, offsetX: 0, offsetY: 0)
        ].compactMap { $0 }
        return buffer
    }
}
```

``SelectionEmphasisCycle/run(_:dim:bright:offsetX:offsetY:)`` returns `nil` when
the cycle does not actually animate — an unfocused element, or a
`.selectionIndicatorStyle(.none)`. That is not an omission to paper over: a
still picture was already drawn by the ordinary render, and a run would have the
loop rewrite it on every tick to no visible effect.

For an element whose appearance is more than a foreground colour, the
`draw:` overloads hand you each frame's colour (or the whole
``SelectionEmphasis``, if two things pulse at once) and take back the finished
cells.

## Let the modifier place them

Both of those need the view to know where its own cells are. Often it does not:
what animates is a colour something *else* paints, and that something knows the
geometry only after layout. The `.border` of the focus example above is exactly
that case — there is no offset for you to pass.

So hand the modifier the colour instead. ``AnimatedColor`` is every frame of
one, and ``View/border(_:style:width:)-(AnimatedColor,_,_)`` takes it and leaves the runs for the
cells it drew:

```swift
struct Target: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    var body: some View {
        Text("Right-click me")
            .padding(.horizontal, 1)
            .border(emphasis.animatedColor(
                isFocused, dim: palette.border, bright: palette.accent))
    }
}
```

No offsets, no ``Renderable``, nothing to get wrong — and an unfocused view
produces a still colour, which draws exactly what `.border(_ colour: Color)`
would and leaves nothing behind. That is the shape to reach for first.

## Composed views declare their runs

A ``Renderable`` owns a buffer and can write runs onto it. A view whose `body`
is other views has no buffer of its own, so it declares them instead with
``View/animatedCells(_:)``:

```swift
var body: some View {
    HStack(spacing: 0) {
        Text("[")
        Text("●").foregroundStyle(cycle.colorNow(dim: dim, bright: bright))
        Text("]")
    }
    .animatedCells([cycle.run("●", dim: dim, bright: bright, offsetX: 1, offsetY: 0)]
        .compactMap { $0 })
}
```

Offsets are relative to the view's own top-left and travel with it: padding,
borders and stacks shift the runs along with the cells they describe.

## Getting it wrong looks like a win

A run is spliced over cells *by position*, without consulting your view again.
So a run in the wrong place, one cell too wide, or built from different colours
than were drawn does not fail loudly — it repaints whatever is really there,
every tick, until something else forces a full render. And a run that is
*dropped* looks even better: the CPU graph reads as a total success, because the
indicator has simply stopped moving.

## Which clock a run belongs to

Every ``AnimatedCellRun`` names an ``AnimationClock``, and there are two. They
tick together, off one timer, at the same interval; they differ only in where
their zero sits.

- ``AnimationClock/cursor`` restarts every time the focus moves, so whatever
  has just taken the focus is at its bright end immediately. A text cursor's
  blink and a focus breath want this — a breath caught at its dim end leaves a
  newly focused control looking unfocused.
- ``AnimationClock/content`` never restarts. An indeterminate progress bar, a
  spinner, a `repeatForever` fade — anything the app is showing that happens to
  move — wants this.

Choosing wrongly is quiet in exactly the way the rest of this section warns
about: a content animation on the cursor clock looks perfect until someone
presses Tab, at which point it jumps back to its first frame and starts again.
Ask whether the animation is *about* the focus. If it is not, it is
``AnimationClock/content``.

Three things are worth asserting in a test, and the framework holds its own
controls to exactly these:

1. **Focused leaves an animating run.** Not "a run" — ``AnimatedCellRun/isAnimating``,
   which requires two distinct frames.
2. **Unfocused or disabled leaves none.**
3. **Replaying the current step changes nothing.** Splice
   ``AnimatedCellRun/frame(atIndex:)`` back over the buffer at the run's own offset
   and compare the visible cells. That is precisely what the loop does on a
   tick, so at the step you rendered at it must be a no-op — which is what
   proves the offset, the width and the frames describe the cells you drew.

```swift
let replayed = buffer.composited(
    with: FrameBuffer(lines: [run.frame(at: 0)]), at: (x: run.offsetX, y: run.offsetY))
#expect(replayed.lines.map(\.stripped) == buffer.lines.map(\.stripped))
```

## Where `withAnimation` meets this

The two are the same machinery seen from opposite ends, and they meet at
``Animation/repeatForever(autoreverses:)``.

A repeating animation has a finite cycle — at the 50 ms replay clock, a 0.8 s
breath is sixteen distinct values — so it *can* be pre-rendered, and where the
animated value only re-styles a buffer the content already produced, the
framework does exactly that and hands the loop the frames. ``View/opacity(_:)``
is the case that qualifies today: a never-ending fade costs no render passes at
all.

The reason it is not automatic for everything is worth knowing, because it is
the same reason this article exists. Pre-rendering a cycle of an arbitrary
subtree means rendering that subtree once per phase — and a render is not a pure
function. It registers focus, publishes hit-test regions, fires `onAppear`,
writes preferences. Sixteen phases would do all of that sixteen times.

So the framework only takes the shortcut where the phases are re-stylings of one
render, and everything else is offered this article instead: *you* know what your
view draws at each point of its cycle, and you can build the frames without
rendering anything sixteen times.

## One reader spoils the frame

The run loop may only replay a tick when *no* view read the clock while
rendering — one reader anywhere in the frame forces the render for everyone on
that clock. So a half-converted page costs exactly what it cost before; nothing
breaks, nothing freezes, and the saving arrives when the last reader on that
screen stops asking.

Which means: if your own view is cheap and the page still re-renders on every
tick, the reader is somewhere else.

## Topics

### Declaring animated cells

- ``View/animatedCells(_:)``
- ``AnimatedCellRun``
- ``AnimationClock``

### The shared focus clock

- ``EnvironmentValues/selectionEmphasis``
- ``EnvironmentValues/isFocused``
- ``SelectionEmphasisClock``
- ``SelectionEmphasisCycle``
- ``SelectionEmphasis``
- ``View/selectionIndicatorStyle(_:speed:)``

### Assembling cells by hand

- ``String/styled(foreground:background:bold:underline:)``
