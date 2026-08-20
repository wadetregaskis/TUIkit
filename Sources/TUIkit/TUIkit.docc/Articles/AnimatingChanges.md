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

``View/opacity(_:)`` is `Animatable` already, so a fade needs no type of your
own:

```swift
Text("Saved")
    .opacity(hasSaved ? 1 : 0)
    .animation(.easeInOut(duration: 0.4), value: hasSaved)
```

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

Where the value changes what is *drawn* rather than how it is coloured, that
shortcut is not available: rendering a subtree once per phase would multiply
every one of its side effects — focus registration, hit-test regions,
`onAppear`, preference writes — by the length of the cycle.

So for a decoration that is not a re-colouring, reach for the lower-level route
in <doc:AnimatingYourOwnView>, which lets a view hand the loop its own finished
frames. `withAnimation` is for *changes*; that is for *decorations*.

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
- ``Animation``

### Declaring what moves

- ``Animatable``
- ``VectorArithmetic``
- ``AnimatablePair``
- ``EmptyAnimatableData``

### Controlling it

- ``Transaction``
- ``withTransaction(_:_:)``
- ``View/transaction(_:)``
- ``EnvironmentValues/transaction``

### Doing it by hand

- <doc:AnimatingYourOwnView>
