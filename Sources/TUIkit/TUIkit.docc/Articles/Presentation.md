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

## Popovers

A `sheet(isPresented:onDismiss:content:)` centres a panel over the dimmed
screen; a **popover** stays next to the thing it belongs to. It is a bordered
panel anchored to the presenting view, over a page that is *not* dimmed —
the same presentation `.contextMenu` and the `Picker` drop-down use, with your
content instead of menu rows. <kbd>Esc</kbd> closes it, and so does a click
anywhere outside it.

```swift
Button("Details") { showing = true }
    .popover(isPresented: $showing) {
        VStack(alignment: .leading) {
            Text("Ganymede").bold()
            Text("Largest moon in the solar system")
        }
    }
```

`arrowEdge` decides which side it sits on — a terminal draws no arrow, but the
edge still means something: `.bottom` (the default) puts it below the view,
`.top` above, `.leading` / `.trailing` beside. `attachmentAnchor` decides where
along that edge: `.rect(.bounds)` centres it on the view, `.point(_:)` puts it
at a unit point within it.

## Full-screen covers

`fullScreenCover(isPresented:onDismiss:content:)` replaces the page rather than
floating over it: the content fills the area between the app header and the
status bar, nothing shows through, and — unlike a sheet — it cannot be dragged,
because there is nowhere for it to go.

## Sheet heights: detents

By default a sheet is as tall as its content. ``PresentationDetent`` overrides
that, applied to the sheet's **content**:

```swift
.sheet(isPresented: $showing) {
    Settings()
        .presentationDetents([.medium])
}
```

`.medium` is half the available height, `.large` all of it, `.fraction(_:)` a
share of it, and `.height(_:)` an exact number of **rows** (a terminal has no
`CGFloat`).

The height goes to the sheet's own **box**. In SwiftUI a sheet is a card with
its own material, so a detent is always visible as that card; a terminal sheet
has no material of its own — the content *is* the sheet — so the outermost
container in it (``Dialog``, ``Panel``, ``Card``, `.border()`) renders exactly
that tall and encloses the slack as empty interior. Content that can fill the
space fills it as usual: a `List`, a `ScrollView`, anything with a `Spacer`
sees the detent as its available height. Content with no box has nothing to
stretch, so it keeps its own size — a detent cannot make a bare `Text` taller,
and does not try by painting blank rows under it.

Two more things to know. It must be the content's **outermost** modifier — the
detent is the height the content is rendered *into*, so it has to be readable
before that render happens, which is why it rides the view's type rather than a
preference. (An `if` in the sheet's builder is fine; another presentation
modifier such as ``View/interactiveDismissDisabled(_:)`` is fine either way
round. Anything else you wrap it in is not.) And a terminal has no grabber to
drag: with several detents and no `selection:` binding the smallest applies, so
bind one if the sheet should be able to change size.

```swift
@State private var detent: PresentationDetent = .medium

.sheet(isPresented: $showing) {
    Settings()
        .presentationDetents([.medium, .large], selection: $detent)
}
```

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

### Insisting on an answer

``View/interactiveDismissDisabled(_:)`` takes away the reader's own ways out.
SwiftUI's gesture is a downward swipe; a terminal's are **Escape** and a click
outside, so those are what it suppresses — Escape stops being offered on the
status bar at all, rather than being offered and doing nothing.

```swift
.sheet(isPresented: $editing) {
    Editor()
        .interactiveDismissDisabled(hasUnsavedChanges)
}
```

Everything programmatic still closes it: a `Done` button flipping the binding,
`@Environment(\.dismiss)`, or the app clearing it once whatever the sheet was
insisting on is done. Alerts and confirmation dialogs are unaffected — Escape
there chooses the `.cancel` button, which is an answer rather than a dismissal.

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

The item's **id is the sheet content's identity**, which is the whole reason to
reach for this form: move the selection to another row while the sheet is up and
the editor is a *different view* — its `@State` back at its initial values, its
`onAppear`/`task` firing again — rather than the same editor handed a new row to
describe, still holding the previous row's half-typed draft. The same is true of
`fullScreenCover(item:onDismiss:content:)` and
`popover(item:attachmentAnchor:arrowEdge:content:)`.

There is also an always-on `modal { … }` overload (bound to a constant `true`)
for content that should always be presented while its host is on screen.

> Note: `popover(isPresented:attachmentAnchor:arrowEdge:content:)` and
> `fullScreenCover(isPresented:onDismiss:content:)` are both available, as is
> `presentationDetents(_:)` — see the sections above. A pop-up of *choices*
> anchored to a control is still better spelled ``Menu`` or
> `contextMenu(menuItems:)`; `.popover` is for arbitrary content.

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

### Presentation

- ``PresentationDetent``
- ``PopoverAttachmentAnchor``
- ``PopoverAttachmentRect``

### Notifications

- ``NotificationService``
