# Animating Changes

Change a value and let the picture catch up.

## Overview

```swift
withAnimation(.easeInOut(duration: 0.3)) {
    isExpanded.toggle()
}
```

The change itself is immediate. `isExpanded` is `true` the instant the closure
returns, every event handler sees `true`, and every `if` in every body sees
`true`. What lags is the *picture*: views that nominated something continuous
about themselves are drawn at values between the old and the new until the
animation ends.

That distinction is the whole model, and it is why an animation cannot break
your logic. Nothing is deferred, queued, or half-applied — only drawn late.

## What actually animates

A view animates by conforming to ``Animatable`` and naming the one continuous
thing about it:

```swift
struct Bar: View, Animatable {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        let filled = Int((Double(width) * fraction).rounded())
        Text(String(repeating: "█", count: filled))
    }
}
```

Everything else about the view — its width, its glyphs, its colour — is a
function of that one value, so the framework only has to interpolate the value
to get every frame in between.

Terminal geometry is whole cells, and ``VectorArithmetic`` is deliberately not
conformed by `Int` for that reason: the *animation* is continuous and the
*drawing* rounds. Rounding per sample instead would quantise the curve as well
as the position, and an eased move would come out linear.

Much of what you would want to animate is animatable already, so most changes
need no type of your own:

| You change | What moves |
|------------|------------|
| ``View/opacity(_:)`` | The fade |
| ``View/offset(x:y:)`` | The displacement — layout is untouched, so this is the cheapest |
| ``View/padding(_:_:)`` | The insets, and the layout around them |
| ``View/frame(width:height:alignment:)`` | A **fixed** width and height |
| ``View/foregroundStyle(_:)``, ``View/background(_:)``, ``View/border(_:style:width:)-(Color,_,_)`` | The colour |
| A **gradient** given to ``View/foregroundStyle(_:)`` or ``View/background(_:)`` | Every stop's colour, every stop's location, and the geometry's own numbers |

```swift
Text("Saved")
    .opacity(hasSaved ? 1 : 0)
    .animation(.easeInOut(duration: 0.4), value: hasSaved)
```

A `ViewModifier` of your own joins that list by conforming to ``Animatable``
and naming one property — `ModifiedView` is animatable whenever its modifier
is, so there is nothing else to learn.

A gradient animates as a handful of independent numbers rather than as one
value, which is what makes the awkward case fall out for free: growing a
two-stop ramp into a five-stop one fades the two stops that were already there
and shows the three that were not at their final colours, because a value the
animator has never seen appears rather than fades.

Three boundaries are worth knowing because they look like bugs otherwise. A
**flexible** frame (`maxWidth: .infinity`) has no number to move between, so it
snaps. `Text`'s own `foregroundStyle(_:) -> Text` overload carries the colour in
the view *value* rather than painting it, so a colour set that way changes at
once; wrap the text to fade it. And a gradient that changes KIND — a colour
becoming a ramp, a ``LinearGradient`` becoming a ``RadialGradient`` — snaps,
because the numbers on either side mean different things and interpolating a
radius toward an ordinate is not a transition.

## Saying it at the change, or at the view

``withAnimation(_:_:)`` states it where the change is made. Use it when the code
making the change is the code that knows it should be seen moving — a button's
action, a keyboard shortcut.

``View/animation(_:value:)`` states it where the change is *seen*. Use it when
the change is made somewhere with no business knowing how it will be shown — a
model update, a network result, a binding written by a control.

The two compose, and neither vetoes the other. `.animation(_:value:)` **adds**
an animation for changes to its value; it does not mask an explicit
`withAnimation`, and several of them nest happily, each governing its own value.
To refuse animation outright, say so outright:

```swift
content.transaction { $0.disablesAnimations = true }
```

A view does not animate into existence: the first render of a value is not a
change, so nothing fades in merely because it scrolled into view.

## What it costs

A terminal has no compositor and no render server. SwiftUI can hand an
interpolation to Core Animation and never re-evaluate a body; here, an
animating subtree really is walked once per frame. So the honest accounting is:

| Animation | Cost |
|-----------|------|
| A finite one (``Animation/easeInOut``, a spring, `repeatCount`) | One render pass per frame at 30 Hz, **for its duration**. A quarter-second ease is eight passes, then nothing. |
| ``Animation/repeatForever(autoreverses:)`` on ``View/opacity(_:)`` | The cycle is pre-rendered once and replayed by the run loop — **no render passes at all** while it runs. |
| `repeatForever` on anything else | One render pass per frame, for as long as the view is on screen. |

The middle row is the one to understand, because it generalises. A never-ending
animation is a *decoration*, and a decoration that costs a render pass twenty
times a second, forever, is the pathology ``AnimatedCellRun`` exists to remove.
Where the animated value only ever **re-styles a buffer the content already
produced** — which is exactly what `.opacity` does — the framework computes
every point of the cycle up front and hands the run loop the finished frames.
Nothing re-renders; the loop splices frames over the picture already on screen.

For `.opacity` that computation happens at the COMPOSITE rather than at the
view, because a phase cannot be coloured until what is behind the layer is
known. The saving is the same: the content is rendered once, and the cycle
costs one re-colouring of its finished lines per phase.

Where the value changes what is *drawn* rather than how it is coloured, that
shortcut is not available: rendering a subtree once per phase would multiply
every one of its side effects — focus registration, hit-test regions,
`onAppear`, preference writes — by the length of the cycle.

So for a decoration that is not a re-colouring, reach for the lower-level route
in <doc:AnimatingYourOwnView>, which lets a view hand the loop its own finished
frames. `withAnimation` is for *changes*; that is for *decorations*.

## Updating on a schedule

Not everything that changes over time is a change to *state*. A clock is not
animating: it is showing a different value each minute, and the view that shows
it wants to be re-rendered when the minute turns. That is ``TimelineView``:

```swift
TimelineView(.everyMinute) { context in
    Text(context.date, style: .time)
}
```

The date the content receives is the schedule's **entry**, not the instant of
the render. With ``TimelineSchedule/everyMinute`` it is the top of the current
minute however late in that minute the frame lands, so a clock never shows a
time that disagrees with the boundary it was drawn for.

The cost model is the one this article keeps coming back to. A timeline is not a
poll: each frame it declares exactly one wake — the next entry — and the run
loop sleeps until then. A clock ticking once a minute renders once a minute, and
a schedule with nothing left to show (an exhausted
``TimelineSchedule/explicit(_:)``, a paused ``TimelineSchedule/animation``)
declares no wake at all, so the screen goes fully idle.

``TimelineSchedule/animation`` is the exception that proves it: asking for the
app's frame rate really does mean a render pass per frame, and it belongs to the
same "decoration" bucket as `repeatForever` above. If what varies is how the
content is *coloured* rather than what it *says*, the lower-level route in
<doc:AnimatingYourOwnView> is cheaper by the width of the render pass.

## Coming and going

``View/transition(_:)`` says how a view arrives when it is inserted and how it
leaves when it is removed:

```swift
if showDetail {
    Detail().transition(.move(edge: .top).combined(with: .opacity))
}
```

``AnyTransition/opacity``, ``AnyTransition/move(edge:)``,
``AnyTransition/slide``, ``AnyTransition/offset(x:y:)``,
``AnyTransition/scale(anchor:)`` and ``AnyTransition/identity`` compose with
``AnyTransition/combined(with:)`` and ``AnyTransition/asymmetric(insertion:removal:)``.
A transition runs *only* when the change that caused it was animated, so
leaving one on a view that also appears for other reasons — a page opening, a
list rebuilding — stays instant.

The effects apply to the rendered cells rather than to layout: a view sliding
in gets its space at once and moves into it. `.scale` has no sub-cell rendering
to shrink, so it uncovers the view from its anchor a cell at a time.

A **removal** needs somewhere to play out, because the view is gone from the
tree by the time anything notices. Whatever still stands in its slot is what
plays it: the picture the view drew on its last frame is left behind, and the
`nil` it became draws that picture part-way gone. This holds the view's row (and
its width) open for as long as the removal runs, so the rest of the stack does
not close up around it until it has finished leaving. See
``View/transition(_:)``.

## Springs

``Animation/spring(duration:bounce:)`` is a real damped oscillator, evaluated in
closed form. `bounce: 0` is the fastest approach that does not overshoot;
positive values overshoot and oscillate; negative values are sluggish.
``Animation/smooth``, ``Animation/snappy`` and ``Animation/bouncy`` are the
usual three points on that scale.

A spring approaches its target asymptotically, so it has no exact end. It is
given one where the answer stops mattering: a terminal draws whole cells and at
most 256 shades, so a residual of 0.2% cannot change anything on screen, and the
animation retires there.

## Topics

### Animating a change

- ``withAnimation(_:_:)``
- ``View/animation(_:value:)``
- ``Binding/animation(_:)``
- ``Animation``

### Coming and going

- ``View/transition(_:)``
- ``AnyTransition``

### Declaring what moves

- ``Animatable``
- ``VectorArithmetic``
- ``AnimatablePair``
- ``EmptyAnimatableData``

### Updating on a schedule

- ``TimelineView``
- ``TimelineSchedule``
- ``TimelineScheduleMode``
- ``TimelineViewDefaultContext``

### Controlling it

- ``Transaction``
- ``withTransaction(_:_:)``
- ``View/transaction(_:)``
- ``EnvironmentValues/transaction``

### Doing it by hand

- <doc:AnimatingYourOwnView>
