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
