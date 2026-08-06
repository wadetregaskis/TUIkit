# Mouse and Gestures

Respond to clicks, scrolling, and drags from the mouse or trackpad.

## Overview

TUIkit reads terminal mouse reports — both the modern SGR encoding and the
legacy X10 encoding — and delivers them as `MouseEvent` values. Once mouse
support is enabled, the built-in controls respond automatically: buttons
activate on click, scrollbars drag, ``List`` and ``Table`` rows select, and
``ScrollView`` scrolls on the wheel. You can also handle raw events or
higher-level gestures on any view.

## Enabling Mouse Support

Mouse reporting is **opt-in**. Turn it on for the whole app with the
`mouseSupport(_:)` scene modifier, or for a subtree with the view modifier of
the same name:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .mouseSupport(.full)
    }
}
```

``MouseSupport`` has four presets:

| Preset | What it enables |
|--------|-----------------|
| `.disabled` | No mouse reporting (the default) |
| `.scrollOnly` | Wheel / trackpad scrolling only |
| `.standard` | Clicks, scrolling, and drag tracking |
| `.full` | Everything, including cursor-motion reporting (hover) |

## Gestures

High-level gesture modifiers cover the common cases:

```swift
Text("Click me")
    .onTapGesture { x, y in
        // a left-click release at terminal cell (x, y)
    }

Text("Double-click me")
    .onTapGesture(count: 2) {
        // fires on the second click of a double-click
    }

content
    .onScrollGesture { direction in
        // direction is .up, .down, .left, or .right
    }

content
    .onDragGesture { event in
        // event.phase is .began / .moved / .ended;
        // event.x / event.y and event.translationX / event.translationY
        // give the current position and displacement from the start
    }

content
    .onHover { isHovering in
        // true when the cursor enters the view's region, false when it leaves
    }
```

Horizontal scrolling (`.left` / `.right`) is produced by a trackpad swipe or a
shifted mouse wheel.

## Context Menus

`contextMenu(menuItems:)` attaches a pop-up of `Button`s to any view, anchored
at the click point:

```swift
Text("Right-click me")
    .contextMenu {
        Button("Duplicate") { duplicate() }
        Button("Delete", role: .destructive) { delete() }
    }
```

Selection, <kbd>Esc</kbd>, or a click outside dismisses it. A right-click that a
view does not handle bubbles to an ancestor menu, the way the wheel does.

Not every terminal will give you the right button: iTerm2 keeps it for its own
menu by default, so TUIkit also accepts <kbd>Ctrl</kbd>-click, and
<kbd>Shift</kbd>+<kbd>F10</kbd> opens the menu of whatever is focused. See
`Documentation/Terminal-compatibility.md` for what each terminal forwards.

`onMenuOpen(_:)` reports the opening — of a `contextMenu` or of a ``Menu`` — to
any view above it, however the menu was opened. It exists for a specific
problem: when the app shows what was last chosen from a menu, choosing the same
item again changes nothing on screen and so reads as nothing having happened.
Clearing the display as the menu opens fixes that, and there is no other moment
to hang it on. TUIkit-specific; SwiftUI's menus are system-drawn, and their open
moment is not the app's to observe.

## Press-and-Hold

Pop-up menus — ``Menu``, a `.menu`-style ``Picker``, a `TextField`'s suggestion
list, and `contextMenu` — track the pointer while the button is held, the way a
Mac menu does: press to open, drag to move the highlight, release over an item
to choose it. Releasing anywhere else — the page behind, the menu's own frame, a
divider — dismisses without choosing. Once the menu is up, a press that starts on
one item and lifts on another chooses the one it *lifted* on: the press is not a
commitment.

Click-then-click works too; both gestures drive the same highlight. The two are
told apart by whether the pointer moved: a release that never left the cell it
was pressed on completes a **click**, and leaves the menu up to be picked from at
leisure. It also chooses nothing — not even when it lands squarely on an item.
The cell an opening click comes back up on is usually chrome (the trigger, or for
a `contextMenu`, anchored where you clicked, the menu's own top border), but a
drop-down with more options than fit below its control is placed *over* the
control, exactly as on a Mac, and then that cell is an item nobody aimed at.
Without both halves of the rule a quick click would open and shut the menu in one
gesture, leaving whatever happened to be under the pointer as the new value.

A pointer-opened menu deliberately starts with **nothing** highlighted, so a
release straight after the press cannot choose an item you never pointed at. The
first <kbd>↓</kbd> lands on the first item and the first <kbd>↑</kbd> on the
last.

## Drag and Drop

Views can act as drag sources and drop targets, in the style of SwiftUI's
`Transferable` modifiers. Mark a source with `draggable(_:)` — optionally with
a custom preview that floats at the cursor — and a target with
`dropDestination(for:action:isTargeted:)`:

```swift
Text("🍎 Apple")
    .draggable(Fruit.apple)

Text("🧺 Basket")
    .dropDestination(for: Fruit.self) { fruits, info in
        // info is a DropInfo: the drop cell in local space plus the
        // modifiers held at release
        basket.append(contentsOf: fruits)
        return true
    } isTargeted: { over in
        isHighlighted = over   // highlight while a compatible drag hovers
    }
```

Dragging requires drag tracking (`.standard` or `.full`). The floating
preview's grab-point anchoring is configurable via
`dragPreviewAnchor(_:)`.

A drag source has to take the press to find out whether it becomes a drag, but
it keeps only the ones that do: a press released without moving is a **click**,
and goes wherever it would have gone had the source not been there — to an
interactive view inside it, or failing that to whatever it sits on. So a
``List`` whose rows are `draggable(_:)` still selects a row when you click it,
and still starts a drag when you move.

## Raw Events

For full control, handle the raw event and return whether you consumed it.
Returning `false` lets the event keep propagating to views behind yours:

```swift
content
    .onMouseEvent { event in
        switch event.button {
        case .left where event.phase == .pressed:
            // handle a left press at event.x, event.y
            return true
        default:
            return false
        }
    }
```

Each view that wants the mouse registers a hit-test region for its on-screen
rectangle; the dispatcher routes an incoming report to the front-most region
that contains the point. See <doc:RenderCycle> for where mouse dispatch sits in
the frame.

## Topics

### Mouse Types

- ``MouseSupport``
- ``ScrollDirection``
- ``DragGestureEvent``

### Drag and Drop

- ``DropInfo``
- ``DragPreviewAnchor``

The raw event types (`MouseEvent`, `MouseButton`, `MousePhase`) live in the
re-exported `TUIkitCore` module.

A view being carried leaves its place: while its own drag is in flight it draws
blank, because it is already on screen at the cursor and drawing it twice says
two things are moving. That is the contract row reordering has always kept under
``RowReorderFeedback/cursor``, now kept by `.draggable` too — so a row dragged
out of one list and into another looks the same as a row dragged within one. It
goes blank rather than vanishing from the layout: the space is still the view's,
and a list closing up mid-drag would move the very rows the drop is aimed
between.

A list whose rows fill it exactly borrows a row's worth of scrolling while a
drag hovers it, because the landing slot needs a line and nothing left the list
to free one. It does not grow — the page must not shift under the pointer —
so instead it overflows by one and says so, with its "▼ N more rows below"
indicator or its scrollbar, and can be scrolled (by wheel, by the mid-drag
navigators, or by holding the pointer at its edge) one further than usual. That
last position is the one after the final row: without the borrowed line a full
list could not draw every row AND the slot, so "drop at the very end" could not
be pointed at. The indicators still count only real rows — the borrowed line is
the slot, which is on screen and is not a row.

The one place it does close up is the list the row is being dropped back into.
A `List` whose rows are `.draggable` opens a landing slot while the drag hovers
it, and a slot plus a blank would be two gaps for one row — the list would grow
by a line for the duration of every same-list drag. So the row that the slot is
*for* is dropped from the drawing instead: one row out, one slot in, and the
list keeps its length, exactly as an ``View/onMove(perform:)`` reorder has
always drawn it. Move the pointer to a different list and the blank comes back,
because that list has no slot of its own and nothing there should shift.

Only a row that is **on screen** can pay for the slot that way. Carry it far
enough — dragging to the bottom edge scrolls the list, and the row it came from
goes off the top — and nothing has left the drawing any more, so the list
borrows a line exactly as it would for a drag from elsewhere. Without that, the
end of a scrolled list could not be pointed at: the furthest the pointer could
reach was the position *before* the last row.

## Abandoning a Drag

Let go with nowhere to land and the drag is abandoned: the floating preview
walks back to where it started rather than vanishing under the pointer — about
a fifth of a second, cell by cell. "Nothing happened" reads far better as a row
going home than as one disappearing in mid-air.

**No key cancels a drag**, deliberately. A drag has to be carriable across the
app — pick a row up on one page, navigate to another, drop it there — and that
requires the navigation keys to keep navigating while something is in hand.
<kbd>Escape</kbd> was the obvious candidate and is exactly the key that
navigation needs, so releasing over nothing is the cancel, as it is on macOS.
The movement keys are the other half of the same rule: mid-drag they scroll
rather than move the cursor, so a destination that is off screen can be reached
without letting go. They scroll **the view under the pointer**, not the one the
drag came from — carrying a payload somewhere else is the whole point, and
somewhere else is where you need to reach. A view the drag could not land in is
not scrolled under it, and with the pointer over nothing that qualifies the keys
mean what they usually mean.

A keyboard move (<kbd>Ctrl</kbd>+<kbd>R</kbd>) is a different thing — a mode,
not a gesture — and it does answer <kbd>Escape</kbd>, which puts the row back.
Its rows leave the list and are drawn as the landing slot, which pulses to say
"these are in your hand". Several rows at once make that pulse ambiguous, so the
row the cursor is on stays at full strength while the others travel faint: an
indicator every row wears is an indicator none of them wears.

A **row reorder** is carriable in the same way, with one limit that follows from
what it is: a reorder can only land in the list it came from, so leaving that
list's page and coming back resumes the gesture, and releasing anywhere else
abandons it. The rows go home and the preview walks back, exactly as a refused
drop does. Which control finishes a reorder is decided at the release, against
whatever is on screen then — not against the list that was there at the press —
so the drop lands in the list you are looking at, moving the rows you can see.
