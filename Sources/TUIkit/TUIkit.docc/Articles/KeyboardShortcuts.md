# Keyboard Shortcuts

How keyboard input flows through TUIkit: from raw terminal bytes to your view handlers.

## Overview

TUIkit uses a layered event dispatch system. When a key is pressed, it passes through up to five layers. The first layer that consumes the event wins: remaining layers are skipped. Layer 0 (text input) and Layer 3 (focus system) are mutually exclusive: when a text input element is focused, Layer 0 runs and Layer 3 is skipped. The one key Layer 0 does not offer the focused text control is an Emacs editing chord your own `.keyboardShortcut` is on; see <doc:KeyboardShortcuts#Your-Shortcuts-and-the-Editing-Chords>.

Three additional stages refine the layer sequence. When an open drop-down (e.g. a ``Picker`` menu) has claimed Escape for the frame, ESC is pre-routed through the focus system *before* Layer 1, so the surface closes instead of a page-level handler firing. Layer 0.5 then offers the key to a drag in flight, which is how you scroll to an off-screen destination without letting go — it has to beat every layer below, all of which would otherwise spend the key on the focused control. And between Layer 3 and Layer 4, a semantic-shortcut stage (Layer 3.5) fires the default button on Return and the cancel button on Escape — à la SwiftUI's `.keyboardShortcut(.defaultAction)` / `.keyboardShortcut(.cancelAction)` — when the focused control let the key fall through.

@Image(source: "keyboard-event-dispatch.svg", alt: "Flowchart of the keyboard dispatch: a hasTextInputFocus check gates Layer 0 (Text Input via focusManager.dispatchKeyEvent for TextField/SecureField/TextEditor), except that an editing chord the focused control gives up to an app shortcut registered on it skips Layer 0 and continues down the chain. Without text focus, an ESC-claimed-by-an-open-surface check pre-routes Escape through the focus system so an open drop-down closes before any page-level handler. Layer 0.5 Drag Navigators (while a drag is in flight, arrows and paging scroll whatever the pointer is over). Layer 1 Status Bar Items (statusBar.handleKeyEvent). Layer 2 View Handlers (keyEventDispatcher.dispatch, deepest view first). A second hasTextInputFocus check skips Layer 3 if text input was focused. Layer 3 Focus System (focusManager.dispatchKeyEvent: focused element delegation, Tab/Shift+Tab, arrow key fallback). Layer 3.5 Semantic Shortcuts (Return fires the default button, Escape the cancel button, and a key-equivalent .keyboardShortcut fires on its key). Layer 4 Default Bindings (q quit and ? help always; t theme and a appearance gated while a modal grabs input). Unmatched events are dropped.")

`Ctrl+C` is an ordinary key here. A terminal normally turns it into SIGINT, but TUIkit's raw mode switches that off, so it reaches these layers as `c` held with Control like any other chord, and nothing binds it unless you do: a ⌘C shortcut under the default ``EnvironmentValues/commandKey``, or ``QuitShortcut/ctrlC``. `Ctrl+Z` arrives the same way, and Layer 4 suspends the app on it only when nothing earlier claimed it (see Default Bindings).

## Available Keys

The ``Key`` enum defines all keys that TUIkit can recognize from terminal input:

### Character Keys

Any printable character is represented as `.character(Character)`:

```swift
.onKeyPress(Key.from("x")) {
    // handle "x" key
}
```

Uppercase detection: when a capital letter is typed, the resulting ``KeyEvent`` has `shift: true` set automatically.

### Special Keys

| Key | Description |
|-----|-------------|
| `.escape` | Escape key |
| `.enter` | Enter / Return |
| `.tab` | Tab |
| `.backspace` | Backspace / Delete backward |
| `.delete` | Forward delete |
| `.space` | Space |
| `.paste(String)` | Bulk text from a bracketed terminal paste |

### Arrow Keys

| Key | Description |
|-----|-------------|
| `.up` | Arrow up |
| `.down` | Arrow down |
| `.left` | Arrow left |
| `.right` | Arrow right |

### Navigation Keys

| Key | Description |
|-----|-------------|
| `.home` | Home |
| `.end` | End |
| `.pageUp` | Page Up |
| `.pageDown` | Page Down |

### Function Keys

| Key | Description |
|-----|-------------|
| `.f1` … `.f12` | Function keys F1 through F12 |

## Key Events and Modifiers

A ``KeyEvent`` combines a ``Key`` with modifier flags:

```swift
public struct KeyEvent {
    public let key: Key
    public let ctrl: Bool     // Ctrl modifier
    public let alt: Bool      // Alt / Option modifier
    public let shift: Bool    // Shift modifier
}
```

The terminal encodes modifiers differently from GUI frameworks:

- **Ctrl+letter**: Detected from ASCII control codes (0x01–0x1A). For example, `Ctrl+C` produces byte `0x03`.
- **Alt+key**: Detected from ESC prefix sequences (`ESC` followed by the key byte).
- **Shift**: Only auto-detected for uppercase letters. The terminal does not send distinct shift codes for most keys.

## Registering Key Handlers

Use the `.onKeyPress()` modifier to handle keyboard events in your views:

### Handle All Keys

```swift
Text("Press any key")
    .onKeyPress { event in
        if event.key == .enter {
            doSomething()
            return true   // consumed: stops propagation
        }
        return false      // not consumed: passes to next handler
    }
```

### Handle Specific Keys

```swift
Text("Use arrow keys")
    .onKeyPress(keys: [.up, .down]) { event in
        if event.key == .up { moveUp() }
        else { moveDown() }
        return true
    }
```

### Handle a Single Key

The single-key variant always consumes the event:

```swift
Text("Press Enter to continue")
    .onKeyPress(.enter) {
        continueAction()
    }
```

### Handler Priority

Handlers are dispatched in **reverse registration order**: the deepest view in the tree (most recently registered) gets the event first. This means inner views can intercept events before outer views see them.

```swift
VStack {
    Text("Outer")
        .onKeyPress(.enter) {
            // Only reached if inner handler did NOT consume it
            print("outer enter")
        }
    Text("Inner")
        .onKeyPress(.enter) {
            // Gets the event FIRST
            print("inner enter")
        }
}
```

> Important: All key handlers are re-registered every render frame. If a view is not rendered (e.g. behind a conditional), its handlers are not active.

This precedence holds inside memoized subtrees too. A `ForEach` row or an `.equatable()` view served from the render cache registers its handlers again at the place in the tree where it would have rendered, so they rank exactly as they would if it had rendered (see <doc:RenderCycle#Registrations-a-Hit-Makes-Again>).

A `Button`'s own shortcut is registered again the same way, on one condition: the `keyboardShortcut(_:)` modifier has to be inside the memoized subtree, as it is when you write the button and its shortcut together. Planted above the boundary instead — `Button("Save") { … }.equatable().keyboardShortcut("s")` — the subtree goes on declining the cache, because the modifier offers its shortcut to the first control that renders *under* it and a served frame renders none.

## Focus Navigation

The `FocusManager` dispatches key events in three steps:

1. **Focused element delegation**: the focused element's `handleKeyEvent(_:)` is called first. If it consumes the event, dispatch stops.
2. **Tab / Shift+Tab**: cycles focus between elements (wraps around).
3. **Arrow key fallback**: Up/Left move to the previous element in the section, Down/Right move to the next. This only triggers if the focused element did not consume the arrow key in step 1.

| Key | Action |
|-----|--------|
| Tab | Move focus to the next focusable element (wraps around) |
| Shift+Tab | Move focus to the previous focusable element (wraps around) |
| Up / Left | Move to previous element in section (fallback) |
| Down / Right | Move to next element in section (fallback) |

For more details, see <doc:FocusSystem>.

## Framework Shortcuts

A few controls bind keys of their own, the way SwiftUI's built-in menu items do.
``NavigationSplitView`` binds SwiftUI's sidebar chords, View ▸ Show Sidebar
(⌃⌘S) and Toggle Sidebar (⌥⌘S). A terminal cannot report ⌘, so they go through
``EnvironmentValues/commandKey`` like any other ⌘ shortcut: <kbd>⌃S</kbd> and
<kbd>⌥⌃S</kbd> under the default `.control`, nothing under `.unavailable`.

| Chord | Default keys | Action |
|-------|--------------|--------|
| ⌃⌘S | Ctrl-S (0x13) | Toggle the sidebar of the split view that holds the focus, else the first on screen |
| ⌥⌘S | Option-Ctrl-S (ESC 0x13, where Option sends ESC) | The same |

They work wherever the focus is, but they are the framework's, not yours, so
everything of yours on the same keys comes first:

- A `.keyboardShortcut` on the same keys wins, wherever its button renders. Under
  `.control`, your ⌘S *is* Ctrl-S, so a Save button takes Ctrl-S and the split
  view keeps Option-Ctrl-S.
- An `onKeyPress` handler that consumes the key wins.
- A focused control that uses the key wins: a sortable ``Table`` sorts on
  Ctrl-S. A `TextField`, a `TextEditor` and a `List` do not use it, so the chord
  works while typing. That holds for every framework shortcut, including the
  text controls' own editing chords against a framework default. Only your
  own shortcuts can take one of those, as the next section describes.

A `.disabled()` split view ignores them.

## Your Shortcuts and the Editing Chords

A focused control is offered a key before your shortcuts are (Layer 0 and
Layer 3 come before Layer 3.5), so as a rule a focused control that uses a key
keeps it. The text controls are the exception, for one family of keys.

Under the default ``EnvironmentValues/commandKey`` of `.control`, a SwiftUI ⌘
shortcut arrives as a Control chord: `.keyboardShortcut("f")`, Find, is Ctrl-F.
Ctrl-F is also an Emacs editing chord in ``TextEditor``, where it moves the
caret forward a character. Under `.option`, ⌘B and ⌘F arrive as Option-B and
Option-F, readline's word motions, which every text control answers. The text
controls read those chords the way the macOS text system and readline do, and
they are a bonus: whatever one does can be done some other way, with another
key or by selecting and typing. So **your shortcut wins them**. Layer 0 does
not offer the chord to the focused text control when a `.keyboardShortcut` is
registered on it. The chord goes on down the chain as a chord the control does
not bind would, and Layer 3.5 fires your button.

| Chord | What the text control does with it | With your shortcut on it |
|-------|------------------------------------|--------------------------|
| Ctrl-A, Ctrl-E | A field: start, end of the line, as Home and End do | Yours |
| Ctrl-A, Ctrl-E | `TextEditor`: start, end of the line; its Home and End go to the ends of the document | The editor's |
| Option-B, Option-F | Back, forward a word, as Option-Left and Option-Right do; with Shift, a field extends its selection | Yours |
| Option-Ctrl-B, Option-Ctrl-F | A field: back, forward a word. `TextEditor`: back, forward a character | Yours |
| Ctrl-B, Ctrl-F | `TextEditor`: back, forward a character | Yours |
| Ctrl-D | `TextEditor`: delete forward | Yours |
| Ctrl-K, Ctrl-Y | `TextEditor`: kill to the end of the line, yank it back | Yours |
| Ctrl-T | `TextEditor`: transpose the characters around the caret | Yours |
| Ctrl-P, Ctrl-N | `TextEditor`: previous, next line | Yours |
| Ctrl-O | `TextEditor`: open a line after the caret | Yours |
| Ctrl-V | `TextEditor`: page down | Yours |
| Option-Ctrl-A | Select all | The control's |
| Ctrl-C, Ctrl-X | A field's copy and cut of the selection | The field's while text is selected; with nothing selected, yours |
| Ctrl-V, Ctrl-Z, Ctrl-U | A field's paste, undo and erase | The field's |

A chord gives way when what it does can be done some other way in that
control, and keeps the key when it is the only way. Select-all has no other key
at all, since ⌘A cannot reach a terminal app. A field's Home and End go to the
ends of its line, so its Ctrl-A and Ctrl-E give way. The editor's Home and End
go to the ends of the whole document, which leaves Ctrl-A and Ctrl-E its only
keys for the ends of a line, so there they stay. A field's clipboard and undo
chords stand in for ⌘C, ⌘X, ⌘V and ⌘Z and do what those would, and its Ctrl-U
erases it; those stay too, except that copy and cut have nothing to act on
without a selection. Then Ctrl-C and Ctrl-X are not the field's at all: they
go on down the chain whether or not you have a shortcut on them, so your ⌘C
fires, and so does ``QuitShortcut/ctrlC``.

Only your shortcuts take a chord this way, and only one that is registered: an
enabled button on screen, not on a page behind a modal. A framework default,
such as the split view's sidebar chord above, never takes a key from the
focused control.

Nor does an `onKeyPress` handler. Layer 0 comes before Layer 2, so a focused
text control keeps its editing chords, and every key it types, from your key
handlers. SwiftUI orders these the other way round: on macOS 15, an
`onKeyPress` on a view that contains the focused `TextField` sees even a plain
letter before the field does, and returning `.handled` takes it from the field.
But a SwiftUI handler only sees keys while the focus is inside its view, and a
TUIkit one sees them wherever the focus is, so the same order here would let
any handler on the page take typing away from a field. To take a chord from a
focused text control, give it a `.keyboardShortcut`.

## Default Bindings

Layer 4 provides five built-in key bindings, but only quit, suspend and help are enabled without configuration:

| Key | Action | Condition |
|-----|--------|-----------|
| `q` / `Q` | Quit application | Enabled by default; gated by ``QuitBehavior`` |
| Ctrl-Z | Suspend the app, as the shell's `^Z` would | Always — but only once no view has claimed the key, so a text field's undo binding wins |
| `?` | Show the focused view's `View.help(_:)` tooltip | Enabled by default; falls through when the focused view has no help text. Reachable behind a modal, unlike `t` and `a` |
| `t` / `T` | Cycle to next color theme | Opt-in: requires `statusBarSystemItems(theme: true)` (or `showThemeItem = true`) |
| `a` / `A` | Cycle to next appearance | Active unless a modal surface has grabbed input (its status bar item is hidden by default) |

### The help key, and the one place it cannot reach

`?` toggles the tooltip for whatever holds the focus. It is settable —
`tooltipState.helpKey = .f1`, or `nil` to claim no key at all — and, like `q`, an
app beats it at any earlier layer: a status-bar item with shortcut `"?"`, an
`.onKeyPress`, or a `.keyboardShortcut(KeyboardShortcut("?", modifiers: []))`.

> Important: **A focused text control swallows `?`.** It is punctuation, and
> Layer 0 gives a focused ``TextField``, ``SecureField``, ``TextEditor`` or
> ``DatePicker`` first refusal on every printable key — so inside one the
> question mark is typed and Layer 4 is never reached. That precedence is
> correct: a help key must not stop the reader typing a question mark. It is
> also a real gap, and the awkward part of it is that the controls whose help
> most needs explaining are exactly the ones the key cannot reach. Their
> tooltips are still available by hovering, and an app wanting a keyboard route
> inside a text field should move `helpKey` to something text input does not
> consume. (An F-key would not have this problem, and was declined for a
> different one: F-keys are frequently claimed system-wide, so they fail
> elsewhere and less visibly.)

### Quit Behavior

The ``QuitBehavior`` enum controls when `q` is allowed to quit:

| Value | Behavior |
|-------|----------|
| `.always` | `q` quits from any screen (default) |
| `.rootOnly` | `q` only quits when no status bar context is pushed |

`.rootOnly` is useful for modal dialogs: push a status bar context for the dialog, and `q` will be blocked until the user dismisses it:

```swift
Dialog(title: "Confirm") {
    Text("Are you sure?")
} footer: {
    ButtonRow {
        Button("Yes") { confirm() }
        Button("No") { cancel() }
    }
}
.statusBarItems(context: "confirm-dialog") {
    StatusBarItem(shortcut: "y", label: "yes")
    StatusBarItem(shortcut: "n", label: "no")
}
```

### Changing the built-in quit key

The default quit binding is configurable through ``StatusBarState/quitShortcut``:

```swift
@Environment(\.statusBar) private var statusBar

statusBar.quitShortcut = .escape
statusBar.quitShortcut = .ctrlQ
statusBar.quitShortcut = QuitShortcut(
    key: .f12,
    shortcutSymbol: Shortcut.f12,
    label: "exit"
)
```

This changes both the Layer 4 quit binding and the displayed system item.
`.ctrlC` quits from a focused text field too, unless text is selected there:
then Ctrl-C copies it.

### Overriding `q` in a local view context

A user-defined status bar item with shortcut `q` and an action intercepts the key before the default quit binding runs:

```swift
EditorView()
    .statusBarItems {
        StatusBarItem(shortcut: "q", label: "close") {
            dismissEditor()
        }
    }
```

This is the correct way to repurpose `q` for a specific screen, dialog, or focus section. The matching user item handles the event in Layer 1, so Layer 4's built-in quit binding is never reached.

## Status Bar Shortcuts

The status bar displays available shortcuts to the user. Use the ``Shortcut`` namespace for consistent, platform-standard symbols:

### Display Symbols

```swift
.statusBarItems {
    StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
    StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter)
    StatusBarItem(shortcut: Shortcut.escape, label: "back")
}
```

### Common Symbols

| Symbol | Constant | Description |
|--------|----------|-------------|
| `⎋` | `Shortcut.escape` | Escape |
| `↵` | `Shortcut.enter` | Enter |
| `⇥` | `Shortcut.tab` | Tab |
| `⇤` | `Shortcut.shiftTab` | Shift+Tab |
| `⌫` | `Shortcut.backspace` | Backspace |
| `⌦` | `Shortcut.delete` | Delete |
| `␣` | `Shortcut.space` | Space |
| `↑` | `Shortcut.arrowUp` | Arrow up |
| `↓` | `Shortcut.arrowDown` | Arrow down |
| `←` | `Shortcut.arrowLeft` | Arrow left |
| `→` | `Shortcut.arrowRight` | Arrow right |
| `↑↓` | `Shortcut.arrowsUpDown` | Vertical arrows |
| `←→` | `Shortcut.arrowsLeftRight` | Horizontal arrows |
| `↑↓←→` | `Shortcut.arrowsAll` | All arrows |
| `⌃` | `Shortcut.control` | Control modifier |
| `⇧` | `Shortcut.shift` | Shift modifier |
| `⌥` | `Shortcut.option` | Option / Alt |

### Shortcut Helpers

```swift
// Combine modifier + key: "⌃c"
Shortcut.combine(.control, "c")

// Ctrl+key display: "^c"
Shortcut.ctrl("c")

// Range display: "1-9"
Shortcut.range("1", "9")
```

### Common Shortcut Letters

| Constant | Value |
|----------|-------|
| `Shortcut.quit` | `q` |
| `Shortcut.yes` | `y` |
| `Shortcut.no` | `n` |
| `Shortcut.cancel` | `c` |
| `Shortcut.ok` | `o` |

### Automatic Key Matching

``StatusBarItem`` automatically derives the trigger key from the shortcut string when no explicit `key:` parameter is given:

- Symbol shortcuts (`⎋`, `↵`, `⇥`) map to their corresponding ``Key`` values
- Single-character shortcuts (`"q"`, `"y"`) map to `.character(thatChar)`
- Arrow combinations (`"↑↓"`) match **both** individual arrow keys
- Multi-character non-symbol strings are informational only (no trigger key)

```swift
// Automatic: shortcut "q" triggers on Key.character("q")
StatusBarItem(shortcut: "q", label: "quit") { quit() }

// Explicit: override the trigger key
StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter) { select() }

// Informational: no action, no trigger
StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
```

## Status Bar Context Stack

The status bar supports a context stack for temporary shortcut overrides: useful for modals and nested navigation:

```swift
// Set global items
.statusBarItems {
    StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
    StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter)
}

// Push context-specific items (e.g. for a dialog)
.statusBarItems(context: "my-dialog") {
    StatusBarItem(shortcut: "y", label: "yes") { confirm() }
    StatusBarItem(shortcut: "n", label: "no") { cancel() }
}
```

When a context is pushed, its items replace the global items in the display. System items (quit, theme, appearance) remain visible unless a user item uses the same shortcut string.

### System Items

There are three system items; only quit is shown by default:

| Shortcut | Label | Order | Shown by default | Description |
|----------|-------|-------|------------------|-------------|
| `q` | quit | 900 | Yes | Quit the application |
| `a` | appearance | 910 | No (opt-in) | Cycle border appearance |
| `t` | theme | 920 | No (opt-in) | Cycle color theme |

System items appear on the right side of the status bar. Opt in to the theme and appearance items with the `statusBarSystemItems(theme:appearance:)` modifier, or toggle them individually:

```swift
// As a modifier
ContentView()
    .statusBarSystemItems(theme: true, appearance: true)

// Or directly on the state
statusBar.showSystemItems = false       // Hide all system items
statusBar.showThemeItem = true          // Show theme cycling (also enables the `t` binding)
statusBar.showAppearanceItem = true     // Show appearance cycling
```

When all system items are hidden and there are no active user items, the status bar is hidden completely — until a status-bar tooltip shows, which it still makes room for and draws.

## Topics

### Input Types

- ``Key``
- ``KeyEvent``
- ``QuitBehavior``

### Focus

- ``FocusReference``
- ``Focusable``

### Status Bar

- ``StatusBar``
- ``StatusBarItem``
- ``StatusBarItemProtocol``
- ``Shortcut``
