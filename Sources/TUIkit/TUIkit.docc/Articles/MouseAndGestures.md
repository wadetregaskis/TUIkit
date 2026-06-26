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
| `.standard` | Clicks and scrolling |
| `.full` | Clicks, scrolling, motion, and drag tracking |

## Gestures

High-level gesture modifiers cover the common cases:

```swift
Text("Click me")
    .onTapGesture { x, y in
        // a left-click release at terminal cell (x, y)
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

The raw event types (`MouseEvent`, `MouseButton`, `MousePhase`) live in the
re-exported `TUIkitCore` module.
