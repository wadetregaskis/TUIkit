# Composing List and Table on ScrollView

This document records what's already been done toward task
#29 ("compose List/Table on top of ScrollView"), what was
deferred, and the architectural mismatches that make the
remaining work non-trivial. It's the place to look the next
time someone proposes "let's just have List wrap ScrollView."

## What was done

The duplication called out in the original task description
— "both currently duplicate scroll-handling / indicator /
clamp logic" — is gone. Commit `22b3982c` extracted the
shared arithmetic into a single protocol,
``ScrollableOffsetState``, in
`Sources/TUIkit/Focus/`. Both ``ScrollViewHandler`` and
``ItemListHandler`` conform; the protocol's extension supplies
every formula and predicate they previously open-coded:

- ``maxOffset`` (the clamp ceiling)
- ``hasContentAbove`` / ``hasContentBelow`` (indicator
  predicates)
- ``rowsAbove`` / ``rowsBelow`` (indicator counts)
- ``visibleRange``
- ``scroll(by:)``
- ``clampScrollOffset()``
- ``handleWheelEvent(_:linesPerTick:)``

The two handlers differ in exactly one place: their `extent`.
``ScrollViewHandler.extent`` returns `contentHeight` (lines);
``ItemListHandler.extent`` returns `itemCount` (rows). Every
formula above is written in terms of `extent`, so the math
works for both shapes without forcing them into a common unit.
(Line-granularity scrolling has since landed in List/Table as
internal ``ItemListHandler`` state without changing this
contract — its `extent` is still row-based.)

What used to be three places where a wheel handler's
`switch event.button` case-`.scrollUp`-and-case-`.scrollDown`
manually called `handler.scroll(by: ±N)` collapsed to one
method call: `if handler.handleWheelEvent(event) { return
true }`. Same for the two open-coded `scrollOffset =
max(0, min(maxOffset, scrollOffset))` clamps and the two
inline `rowsBelow = handler.contentHeight - ...` calculations.

Net diff: about 65 lines of duplicated arithmetic gone, one
new protocol file. All 1554 tests pass on Linux Swift 6.3.2.

## What was deferred

The "compose List/Table on top of ScrollView" framing —
where ``List`` literally wraps ``ScrollView`` in its body and
delegates wheel handling, indicator rendering, and scroll
state entirely to ScrollView — was deferred. The case for
doing it rests on "ScrollView and List should share the same
wheel-and-indicator behaviour by *construction* rather than
by convention," which is a real but contained gain. After the
deduplication pass, the by-convention version is small and
easy to keep in sync. The full composition is days of
careful work for a smaller payoff than the original task
description implied.

## Architectural mismatches

Four obstacles stand between the current state and a full
"List is a ScrollView" composition. Any future attempt has
to solve all of them, not just one.

### 1. The lazy-rendering invariant

``_ListCore`` only renders the rows whose indices fall inside
``handler.visibleRange`` — at most ``viewportHeight`` rows.
For a 1900-row emoji list that's roughly 24 rows rendered per
frame, not 1900. The factor-of-N win is invisible in the
benchmark output for the small cases but dominant for any
realistic scrolling list.

``ScrollView``, by contrast, renders its content to a tall
canvas:

```swift
var measureContext = context.withChildIdentity(type: Content.self)
measureContext.availableHeight = max(viewportHeight * 64, 4096)
if horizontal {
    // Horizontal scrolling inflates the width axis the same way.
    measureContext.availableWidth = max(contentWidth * 64, 4096)
}
let fullBuffer = TUIkit.renderToBuffer(content, context: measureContext)
```

It then windows from `fullBuffer.lines` by index. That works
fine for static prose, but if List composes naively on top of
this it forces every row to render every frame, regardless of
visibility. The current List perf profile would regress by
~80x for long lists.

Resolving this requires ScrollView to grow a "windowed
content" mode where the content provides its rows lazily and
ScrollView tells it which range to materialise. The protocol
shape gets messy because:

- Rows can be multi-line (`ListRow.height = buffer.height`),
  so the window is measured in lines but the items are
  measured in rows. Translating between the two requires
  knowing each row's height, which requires *rendering* it
  unless rows declare their height ahead of time.
- The protocol has to be expressive enough to handle Section
  headers / footers, which behave differently from content
  rows (non-selectable, non-focusable, fixed-position within a
  section).
- The protocol has to expose hit-test regions per row so the
  enclosing ScrollView's snap-to-focused-control logic can
  find them.

This is a real abstraction that doesn't exist yet. It's a
project in itself.

### 2. Focus-registration interaction

``ScrollView`` registers a ``ScrollViewHandler`` as a
``Focusable`` so that arrow keys (and Page Up / Page Down /
Home / End) scroll the viewport when ScrollView has focus.

When List wraps ScrollView, List's ``ItemListHandler`` is the
real Focusable — arrow keys should move the *selection*, not
scroll the viewport in lines. ScrollView's inner handler must
*not* register, otherwise both handlers fight for the same
key events.

Currently ``.disabled()`` on ScrollView suppresses both focus
registration *and* the wheel mouse handler. Wheel scrolling
still has to work inside a List (that's the whole point of
composing), so `.disabled()` is the wrong tool. The right tool
would be a separate `.focusable(false)` modifier that
suppresses only the Focusable registration. The mouse handler
stays active and wheel events still scroll the viewport.

Implementation cost: a new modifier, a new private flag on
``_ScrollViewCore``, and a small adjustment to the
focus-registration path. Maybe a session of work on its own,
but contained.

### 3. Carrying the focusID through to the focused row's region

ScrollView's snap-to-focused-control behaviour (added in
#30) scans the content's hit-test regions for one whose
``focusID`` matches the current focus and scrolls that
region into view:

```swift
if let region = fullBuffer.hitTestRegions.first(where: {
    $0.focusID == focusedID
}) { ... }
```

For this to work when List composes on ScrollView, the
focused row's hit-test region has to carry
``ItemListHandler.focusID``. The current ``_ListCore`` doesn't
emit per-row regions tagged with the handler's focusID — its
container-wide region carries `focusID = handler.focusID`,
and individual rows have no regions at all.

The fix is straightforward: when rendering a row, if its
`rowIndex == handler.focusedIndex`, emit a hit-test region
tagged with the handler's focusID covering that row's lines.
The snap machinery does the rest. But it needs care: row
hit-testing is currently done by tracking each row's y-range
in ``PopulatedRenderState`` and unifying them under a single
fallback region inserted at index 0 of ``hitTestRegions`` —
the click handler walks the y-ranges to translate `event.y`
back to a row index. Splitting the fallback back out into
per-row regions (so the focused row's region carries the
focusID for snap, while the others continue to land clicks
through y-range translation) is more than a one-line change.

### 4. Container chrome

List has a title, a border, optional footer, optional
sections with headers, an empty-state placeholder. ScrollView
is a bare viewport. The "List composes on ScrollView" pattern
would put List's chrome *outside* the ScrollView (title row +
border above, footer below, sections rendered inline within
the scrolled content). That's a sensible structure — it's
how SwiftUI's `List` decomposes — but it's a wrapping /
composition pattern, not deduplication. The work is in
moving the chrome rendering out of ``_ListCore.renderToBuffer``
and into a body that looks like:

```swift
public var body: some View {
    VStack(spacing: 0) {
        if let title { TitleRow(title: title) }
        Divider()
        ScrollView {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    SelectableListRowView(row: row, handler: handler)
                }
            }
        }
        .focusable(false)
        if let footer { footer }
    }
    .border()
}
```

(Where ``SelectableListRowView`` knows how to attach the
focused-row hit-test region — see mismatch #3.)

That body is much smaller than the current
``renderToBuffer``, which is a good sign — but every piece of
state currently threaded through ``renderToBuffer``
(per-row y-ranges, the empty-state placeholder, the sections
extractor, the selection-toggle dispatch) needs a new home.
None of those reasons are deep; all of them are work.

## Triggers for revisiting

The deduplication pass landed the *math* in one place, so the
two handlers can't drift on the arithmetic. The remaining
work is structural composition, which has diminishing returns
absent a real driver. Two reasons to take it on:

1. **The behaviours start drifting in practice.** If
   ScrollView's wheel handling, indicator strategy, or
   snap-to-focused-control diverge from List/Table's,
   composition is the way to reunify them. Watch for "fix
   for wheel handling that only applies to ScrollView" or
   similar commit messages.

2. **Something else needs the windowed-content primitive.**
   A virtualised grid view, a virtualised tree view, a `Lazy`
   variant of `ScrollView` — any of these forces mismatch #1
   to be solved, at which point composing List on the same
   primitive is a small additional step. If you find
   yourself reaching for `LazyVStack` inside a `ScrollView`
   and discovering that the lazy doesn't actually defer
   rendering for off-screen children, that's the same
   trigger.

Don't compose speculatively just to "tidy up." The current
two-tracks design works, the deduplication makes the
relationship explicit, and the test suite holds.
