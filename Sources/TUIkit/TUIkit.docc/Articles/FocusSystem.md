# Focus System

Navigate between interactive elements using the keyboard.

## Overview

TUIkit provides a focus system that lets users move between interactive views (buttons, menus, text fields) using Tab, Shift+Tab, or arrow keys. The system consists of three parts:

- **`FocusManager`**: Tracks which element is focused, handles navigation
- **``Focusable``**: Protocol that views adopt to receive focus
- **``FocusReference``**: Lightweight handle that views use to query and request focus by id

## How Focus Works

Every frame, the `FocusManager` is cleared and interactive views re-register themselves during rendering. This means focus registrations are always in sync with the current view tree: removed views are automatically unregistered.

The focus order follows the rendering order: the first focusable view rendered is first in the Tab cycle.

## The Focusable Protocol

Views that want to receive focus conform to ``Focusable``:

```swift
public protocol Focusable: AnyObject {
    var focusID: String { get }
    var canBeFocused: Bool { get }
    func onFocusReceived()
    func onFocusLost()
    func handleKeyEvent(_ event: KeyEvent) -> Bool
}
```

- **`focusID`**: Unique identifier for this focusable element
- **`canBeFocused`**: Whether focus can move to this element (default: `true`)
- **`onFocusReceived()`**: Called when this element gains focus (default: no-op)
- **`onFocusLost()`**: Called when this element loses focus (default: no-op)
- **`handleKeyEvent(_:)`**: Handle a key event while focused; return `true` if consumed

A default extension provides sensible defaults for `canBeFocused` (`true`), `onFocusReceived()`, and `onFocusLost()` (both no-ops). Only `focusID` and `handleKeyEvent(_:)` must be implemented.

## Using FocusReference

``FocusReference`` is the imperative API for checking and requesting focus inside a view by id (the declarative `@FocusState` property wrapper is the SwiftUI-style alternative):

```swift
// The environment's focusManager is Optional: it is nil in isolated/measure
// renders and in tests that don't install a focus system.
guard let focusManager = context.environment.focusManager else { return }
let focusRef = FocusReference(id: "my-button", focusManager: focusManager)

// Check if this element is currently focused
if focusRef.isFocused {
    // render with focus indicator
}

// Programmatically request focus
focusRef.requestFocus()
```

Built-in views like ``Button`` and ``Menu`` register their own focus internally: you only need this when building custom focusable views.

## Declarative Focus

For view code, the SwiftUI-shaped API is usually what you want.

``FocusState`` binds a value to *where focus is*, and `focused(_:)` /
`focused(_:equals:)` attach a control to it. `defaultFocus(_:_:)` says what
should start focused when the scope appears:

```swift
enum Field { case username, password }

struct SignIn: View {
    @FocusState private var field: Field?
    @State private var user = ""
    @State private var secret = ""

    var body: some View {
        VStack {
            TextField("Username", text: $user)
                .focused($field, equals: .username)
            SecureField("Password", text: $secret)
                .focused($field, equals: .password)
            Button("Sign in") { submit() }
        }
        .defaultFocus($field, .username)
    }
}
```

Writing to `field` moves focus; reading it tells you where focus is. A `Bool`
`@FocusState` binds a single control the same way, via `focused($isEditing)`.

Two more modifiers shape the ring itself:

- `focusable(_:interactions:)` makes any view a Tab stop — `.activate` also
  makes a click focus it — so a custom view joins the ring without adopting
  ``Focusable``.
- `focusSection(_:)` groups a region. Tab and Shift+Tab move *between*
  sections, entering each at its edge (first element going forward, last going
  back) rather than at whatever was last focused inside it.
- `focusID(_:)` pins an explicit identity on a control, instead of the one
  derived from its position in the tree.

## Navigation Keys

The `FocusManager` responds to these keys during dispatch:

| Key | Action |
|-----|--------|
| Tab | Move focus to the next element |
| Shift+Tab | Move focus to the previous element |
| Arrow Down / Right | Move focus to the next element |
| Arrow Up / Left | Move focus to the previous element |

Inside a `NavigationSplitView`, Arrow Left and Right move focus to the
neighbouring column instead — landing on what was last focused there — while Up
and Down keep stepping within the column. A focused control that uses Left and
Right itself, such as an outline's disclosure or a slider, still gets them first.

## When a Control Loses Focus

A focused control can stop being able to hold the focus without anyone moving
it: it is disabled, hidden with `hidden()`, or removed from the tree. At the end
of that render pass the focus manager finds the focus a new home, in this order:

1. A `defaultFocus(_:_:priority:)` that still wants the focus takes it.
2. Otherwise, if the control declared a **handoff** with
   `focusHandoff(_:_:)`, the control it names (see below).
3. Otherwise the focus goes to the control's **neighbour** in its section's
   ring: the next focusable control, else the previous one. It never wraps
   round the end, so a control at the bottom of a dialog does not send the
   keyboard back to its top.
4. If the control cannot be placed in the ring at all, the section's first
   focusable control.

A control that is still in the tree but can no longer be focused, such as a
disabled `Button`, walks from where it stands. A control that has left the ring
walks from where it stood on the last frame: just after the nearest control
before it that is still there. A disabled `focusable(_:interactions:)` view is
one of these, because it leaves the ring rather than staying in it disabled, and
it lands where a disabled `Button` in its place would. A control that an
`if`/`else` swaps for another hands the focus to its replacement, which stands
in the same place.

This applies only when the focused control lost the ability to hold focus.
Tab, the arrow keys, a click, and writing a `@FocusState` move the focus where
they say. Dismissing a modal returns the focus to the control that held it
before the modal opened, and a menu opened with the pointer may rest with
nothing focused.

### Naming where the focus goes

The neighbour is the wrong answer for controls that mirror each other. A pair
of `◀ ▶` buttons that move a selection wants ▶, disabled at the end, to hand
the focus to ◀ on its left, and ◀, disabled at the start, to hand it to ▶ on
its right. No rule based on position gives both, so each button says where its
focus goes, by `@FocusState` value:

```swift
enum Move: Hashable { case left, right }
@FocusState private var move: Move?

HStack {
    Button("◀") { selection -= 1 }
        .disabled(selection == 0)
        .focused($move, equals: .left)
        .focusHandoff($move, .right)
    Button("▶") { selection += 1 }
        .disabled(selection == last)
        .focused($move, equals: .right)
        .focusHandoff($move, .left)
}
```

`focusHandoff(_:_:)` is TUIkit's own; SwiftUI has no equivalent. It applies
however the control lost the ability to hold focus: its own action, or a change
anywhere else that disabled, hid or removed it. A control that has left the tree
is handed off by what it declared on its last frame.

When the named control cannot take the focus either (it is disabled too, or not
in the tree), the focus follows *that* control's handoff, and so on along the
chain, stopping at the first control that can take it. A chain that comes back
to a control it has already passed through, such as ◀ and ▶ above both being
disabled, stops there, and the focus goes to the original control's neighbour.
A handoff never leaves the focus waiting for a control to appear.

A target in another focus section moves the focus into that section, unless the
section that held the focus is a modal; the rule above then applies inside the
modal. Like `focused(_:equals:)`, a handoff written on a container belongs to the
first focusable control inside it.

## FocusRegistration Helper

Built-in interactive views use the internal `FocusRegistration` helper to avoid boilerplate. It handles three tasks in one call:

1. **Persist a focus ID** via `StateStorage` so it remains stable across renders
2. **Register** the handler with the `FocusManager`
3. **Query** whether this view currently has focus

Custom views that implement ``Focusable`` typically do not need `FocusRegistration` directly. It is used by the framework's `_*Core` views (e.g. `_ButtonCore`, `_ListCore`).

## Focus Indicator

The visual indicator depends on the view type. Buttons and similar controls use a **highlight background bar** for the focused item. Text fields render as a bracketed field (`[ text ]`) and show a **visible text cursor** inside it when focused — block, bar, underscore, or I-beam, with configurable pulsing, via the `.textCursor(_:)` modifier. Lists and tables use a **highlight background** for the focused row, with a **pulsing accent background** when the row is both focused and selected.

The pulse runs on a shared clock so everything on screen breathes together, and
it walks a discrete ramp of shades rather than lerping — the 256-colour cube has
no dark tinted colours, so a continuous fade quantises to grey partway down.

To give **your own** view the same affordance, read the two environment values
the built-in controls read: `\.isFocused` says whether this subtree holds focus,
and `\.selectionEmphasis` carries the current point on the pulse.

### Turning it off

``View/focusEffectDisabled(_:)`` suppresses the indication without
taking the view out of the focus ring — SwiftUI's modifier and SwiftUI's
contract. Tab still reaches the control, it still takes the keys, it simply
stops advertising that it has arrived. Everything goes: the pulse, a `Button`'s
caps and bold, a `Toggle`'s glyph colour, a `Slider`'s and `Stepper`'s arrows,
a `List`'s or `Table`'s cursor-row highlight, a `TabView`'s active-chip
breath, a menu `Picker`'s accent value and breathing caps, the check mark on a
`ColorPicker` grid's cursor swatch, and the breathing scrollbars and "N more"
lines of a `ScrollView` or `TextEditor` (the bars stay, in their resting
colours: where you are in the content is not which control has the keys).

Two things deliberately survive, and the rule behind them is worth stating
because it decides the case this document has not seen:

> Does the cell say **where you are**, or **what you can do**?

A text cursor is the second — it is the insertion point, and it tells you where
typing will go — so it stays and animates as usual. That is the whole of the
exception, and **the test is typing**: a `DatePicker`'s active-field marker
looks like a caret and is not one, because nothing is typed there and the field
is active only because the control is focused. A row highlight, a bold label, a
coloured arrow and that mark are all the first, and go.

If you write your own view, gate its focus styling on
``RenderContext/indicatesFocus(_:)`` rather than on `\.isFocused` directly.
That is the one question every built-in control asks, and it is what stops the
modifier being honoured by six controls and forgotten by two — a partial
suppression reads as a bug in whichever control kept shouting.

**Know what it costs.** A terminal has no pointer to fall back on, so a subtree
with its focus effects off can be genuinely impossible to navigate by keyboard.
That is the same trade SwiftUI's modifier makes, and it is the caller's to make.

## Focus in the Event Loop

Focus dispatch happens in Layer 3 of the key event pipeline (see <doc:AppLifecycle> for the whole ladder, including the ESC pre-route and Layer 3.5):

1. A key event arrives from stdin
2. Layer 0: text input, when `focusManager.hasTextInputFocus` — mutually exclusive with Layer 3
3. Layer 1 (status bar) gets first chance at everything else. A presented alert or modal publishes its own `⎋ dismiss` item here, which is what stops a page's `⎋ back` from firing underneath it
4. Layer 2: `KeyEventDispatcher` dispatches `.onKeyPress` handlers (deepest view first)
5. Layer 3: `FocusManager` delegates to the focused view's `handleKeyEvent(_:)`, then handles Tab/Shift+Tab and arrow key fallback
6. Layer 3.5: semantic shortcut actions — `.defaultAction` (Return) and `.cancelAction` (Escape) — so a default button fires only once the focused control has let the key through
7. Layer 4 (default bindings) handles quit, theme cycling, etc.
