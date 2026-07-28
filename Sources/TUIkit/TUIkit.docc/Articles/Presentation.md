# Modals, Sheets, and Alerts

Present overlays — alerts, modal dialogs, and transient notifications — above
the current screen.

## Overview

TUIkit presents alerts and modals as a **centred overlay that dims the whole
screen and captures keyboard input**, no matter where in the view tree the
modifier is attached. The overlay is hosted at the root, so you can hang it off
any subtree rather than a special full-screen container. <kbd>Esc</kbd>
dismisses the presentation, and says so on the status bar while it is up — it
has to claim the key there, or a page carrying its own `⎋ back` item would eat
it and navigate out from under the dialog. A presented dialog can also be
dragged by its title or border, and is clamped to stay on screen.

## Alerts

Use `alert(_:isPresented:actions:message:)` for a titled alert with an
actions area and an optional message. Bind it to a `Bool` state:

```swift
struct ContentView: View {
    @State private var confirming = false

    var body: some View {
        Button("Delete") { confirming = true }
            .alert("Delete this item?", isPresented: $confirming) {
                Button("Delete", role: .destructive) { deleteItem() }
                Button("Cancel", role: .cancel) { keepItem() }
            } message: {
                Text("This action cannot be undone.")
            }
    }
}
```

An overload without the `message:` closure presents an actions-only alert. Both
accept optional `borderStyle`, `borderColor`, and `titleColor` arguments for
terminal-specific styling.

Choosing **any** action dismisses the alert, as in SwiftUI — the action closure
does not flip `isPresented` itself. <kbd>Esc</kbd> *is* the `.cancel`-role
button: it runs that action if there is one (a disabled one is skipped) and
closes the alert either way, which is why `Cancel` above has something to do.
An alert with no cancel role simply closes, and no other action is conscripted
into the job.

Each action is a separate focusable control: <kbd>Tab</kbd> moves between them
in drawn order and <kbd>Return</kbd> activates the focused one.

## Confirmation Dialogs

`confirmationDialog(_:isPresented:titleVisibility:actions:message:)` is the same
host with its buttons **stacked vertically** — an action sheet — and the
`.cancel` role sorted to the bottom. `titleVisibility: .hidden` suppresses the
title.

```swift
Button("Delete item…") { confirming = true }
    .confirmationDialog("Delete this item?", isPresented: $confirming) {
        Button("Delete", role: .destructive) { choice = "deleted" }
        Button("Cancel", role: .cancel) { choice = "cancelled" }
    } message: {
        Text("This action cannot be undone.")
    }
```

Dismissal works exactly as it does for an alert, Escape included.

## Modals and Sheets

`modal(isPresented:onDismiss:content:)` presents arbitrary content with the
same centred, screen-dimming treatment.
`sheet(isPresented:onDismiss:content:)` is a SwiftUI-compatible alias that
forwards to `modal`:

```swift
struct ContentView: View {
    @State private var showingDetails = false

    var body: some View {
        Button("Show details") { showingDetails = true }
            .sheet(isPresented: $showingDetails) {
                DetailView()
            }
    }
}
```

The optional `onDismiss:` closure runs on the presented → dismissed
transition, whatever cleared the binding — a Close button, a key press, or a
programmatic change.

As in SwiftUI, there is also an item-driven overload,
`sheet(item:onDismiss:content:)`: a non-`nil` `Identifiable` value presents
the sheet, built from the unwrapped item, and clearing the binding dismisses
it:

```swift
@State private var editing: Row?

List(rows, selection: $selection) { ... }
    .sheet(item: $editing) { row in
        EditView(row)
    }
```

There is also an always-on `modal { … }` overload (bound to a constant `true`)
for content that should always be presented while its host is on screen.

> Note: TUIkit does not currently provide `.popover`, `.fullScreenCover`, or
> `presentationDetents`. A pop-up anchored to a control is spelled ``Menu`` or
> `contextMenu(menuItems:)`.

## Notifications

Notifications are toast-style messages that appear briefly and then fade,
**without** dimming or blocking the background. Add a host where they should be
drawn with `notificationHost(width:)`, then post from anywhere — they are
delivered out of band, not declared in the view tree:

```swift
// Install the host once, near the root:
ContentView()
    .notificationHost()

// Post from anywhere, including non-view code:
NotificationService.current.post("Saved!", duration: 2.0)
```

Because the host is independent of the view that posts, a notification survives
navigation between screens.

## Topics

### Notifications

- ``NotificationService``
