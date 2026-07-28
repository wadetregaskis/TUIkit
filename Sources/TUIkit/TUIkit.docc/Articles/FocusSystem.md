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

## Focus in the Event Loop

Focus dispatch happens in Layer 3 of the key event pipeline (see <doc:AppLifecycle> for the whole ladder, including the ESC pre-route and Layer 3.5):

1. A key event arrives from stdin
2. Layer 0: text input, when `focusManager.hasTextInputFocus` — mutually exclusive with Layer 3
3. Layer 1 (status bar) gets first chance at everything else. A presented alert or modal publishes its own `⎋ dismiss` item here, which is what stops a page's `⎋ back` from firing underneath it
4. Layer 2: `KeyEventDispatcher` dispatches `.onKeyPress` handlers (deepest view first)
5. Layer 3: `FocusManager` delegates to the focused view's `handleKeyEvent(_:)`, then handles Tab/Shift+Tab and arrow key fallback
6. Layer 3.5: semantic shortcut actions — `.defaultAction` (Return) and `.cancelAction` (Escape) — so a default button fires only once the focused control has let the key through
7. Layer 4 (default bindings) handles quit, theme cycling, etc.
