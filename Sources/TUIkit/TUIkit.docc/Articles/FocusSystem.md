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

The visual indicator depends on the view type. Buttons and similar controls use a **highlight background bar** for the focused item. Text fields render as a bracketed field (`[ text ]`) and show a **visible text cursor** inside it when focused — a block, bar or underscore that pulses unless the `.textCursor(_:)` modifier says to blink or hold still. Lists and tables **breathe the background of the cursor row**: the accent when that row is selected, the neutral focus wash (``Palette/focusWashPulse()``) when it is not.

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
Handles and sections go the same way: the ● an active focus section or
`NavigationSplitView` column draws in its border, the breathing background of
a split's divider or edge column, and the breath of a `userResizable` view's
grip. The divider's dots, its ◀ and the grip's marks stay, in their resting
ink.

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

**It is additive.** A `true` anywhere above a control suppresses that control's
indication, and a nested ``View/focusEffectDisabled(_:)`` with `false` does not
put it back — SwiftUI's own rule ("the higher views in a view hierarchy can
override the value you set on this view"), and the rule ``View/disabled(_:)``
already follows here. So `false` adds no suppression rather than lifting one,
which is what makes `.focusEffectDisabled(isQuiet)` on a leaf behave: the flag
decides whether this subtree adds its own, and an ancestor's decision stands
either way. ``EnvironmentValues/appearsActive`` is not a suppression at all —
an inactive view keeps its indication and holds it still (below) — and it is a
plain value, so a subtree that sets it back to `true` gets its breath back.

**Know what it costs.** A terminal has no pointer to fall back on, so a subtree
with its focus effects off can be genuinely impossible to navigate by keyboard.
That is the same trade SwiftUI's modifier makes, and it is the caller's to make.

### When the view does not appear active

A view whose ``EnvironmentValues/appearsActive`` is `false` keeps its focus
indication on screen, and holds it still. That is the case whenever the scene
is not ``ScenePhase/active``: while the terminal window, tab or pane the app
runs in has lost focus, and on the frame rendered on the way into a suspend. It
is also the case inside any subtree that sets
`.environment(\.appearsActive, false)`.

The focus has not gone anywhere. It is parked on the control the user left it
on, and the keys reach that control again the moment the window comes back — so
the indication says where it is, and stops saying "now": motion is what means
the keys go here right now, and right now they do not. An indication that
vanished with the window read as the focus having been lost.

- **Anything that breathes or blinks holds still, half-way between its two
  ends**: a `Button`'s caps, a `Toggle`'s glyph, a radio button's bullet, a
  `TabView`'s chip, a scroll bar and its "N more" lines, the ● of an active
  focus section or split column, a split divider's or resize grip's breath, a
  hovered divider, an open menu's frame. Whatever the indicator style — under
  `.selectionIndicatorStyle(.none)` too, since an indication that never moved
  still has to say "not now". Half-way, because indications rest at both
  ends: a `Toggle`'s mark and a radio button's bullet breathe down from the
  colour they have unfocused, a tab chip and the "N more" lines up from
  theirs, so held at either end one pair looked exactly as if the focus had
  gone. Half-way is the resting look of nothing that rests at an end, and it
  is short of the peak. Under `.pulse` it is a shade every breath passes
  through; under `.blink` and `.none` it is one the indication never showed
  while active. Below truecolor it is taken on the shades the terminal can
  show between the ends, and where there are none — the ends one step apart,
  as close ends can be in 256 colours, and more readily in sixteen — it is the
  bright end, and a `Toggle`'s mark or a radio bullet then looks as it does
  unfocused. ``EnvironmentValues/selectionEmphasis`` gives a focused element
  that one still frame (``SelectionEmphasis/isHeld``, reporting the style in
  force as its ``SelectionEmphasis/animation``) and reads no clock, so an
  inactive window does not keep the run loop waking to animate it. A view
  that asks it for its own emphasis holds still the same way.
- **A highlighted row** — a `List`'s or `Table`'s cursor row on a selected
  row, the highlighted row of a `Menu` (inline or pop-up), a `Picker`'s
  drop-down or a field's suggestions — takes the still tint a `List` gives a
  selection it does not hold the keys for: the look an unfocused list already
  has, which is what makes it read as "here, but not now". A selected cursor
  row keeps its ● at full strength, which still tells it from a selection the
  list merely remembers.
- **A cursor row that is not selected** holds still in the plain focus wash,
  ``Palette/focusBackground`` — the bottom of the breath it draws while the
  window is active (``Palette/focusWashPulse()``), and the look it has always
  had.
- **Nothing else changes.** The bold, the recoloured arrows and values: they
  were still to begin with, and they stay.

``View/unfocusedSelectionVisibility(_:)`` with `.hidden` does not hide an
inactive list's cursor row: the list still holds the focus, so it is not the
unfocused selection that modifier is about. The rest of its selection follows
the modifier as it does whenever the list is unfocused.

Losing focus is noticed only where the terminal reports it. While an app runs,
TUIkit turns on the terminal's focus reporting (DEC private mode 1004). A
terminal without that mode never reports focus, tmux reports it only when its
`focus-events` option is on before the client attaches, and a report sent as
reporting is turned on can be lost among the startup queries. So treat the
inactive look as a courtesy that may never arrive, and do not build behaviour
on it. ``ScenePhase`` has the details.

What stays exactly as it was:

- **The focus itself.** `\.isFocused` is still `true`, Tab and the keys behave
  as before, and the focus is where the user left it when input returns.
- **Selection.** Being selected is not being focused. A `List`'s or `Table`'s
  selected rows the cursor is not on are drawn exactly as they are whenever the
  list is unfocused.
- **A text cursor**, for the same reason it survives `focusEffectDisabled`. It
  stops moving: whatever its animation, it holds still at the dim end of its
  pulse, the cell-drawn counterpart of the hollow cursor a terminal draws in a
  window without focus. It picks its animation up again when the view appears
  active. Under `focusEffectDisabled` alone it animates as usual.

Progress does not stop. An unfocused terminal window is still on screen, so
spinners, indeterminate progress bars and a refresh's indicator go on
animating, where SwiftUI advises pausing timers in an inactive scene.

This is not ``View/focusEffectDisabled(_:)``: that modifier removes the
indication, and ``RenderContext/indicatesFocus(_:)`` answers `false` under it
and only under it. A view that asks that function keeps drawing its indication
while inactive, and a view that reads `\.isFocused` in its `body` and colours
itself through `\.selectionEmphasis` holds still with no change at all.

## Focus in the Event Loop

Focus dispatch happens in Layer 3 of the key event pipeline (see <doc:AppLifecycle> for the whole ladder, including the ESC pre-route and Layer 3.5):

1. A key event arrives from stdin
2. Layer 0: text input, when `focusManager.hasTextInputFocus` — mutually exclusive with Layer 3
3. Layer 1 (status bar) gets first chance at everything else. A presented alert or modal publishes its own `⎋ dismiss` item here, which is what stops a page's `⎋ back` from firing underneath it
4. Layer 2: `KeyEventDispatcher` dispatches `.onKeyPress` handlers (deepest view first)
5. Layer 3: `FocusManager` delegates to the focused view's `handleKeyEvent(_:)`, then handles Tab/Shift+Tab and arrow key fallback
6. Layer 3.5: semantic shortcut actions — `.defaultAction` (Return) and `.cancelAction` (Escape) — so a default button fires only once the focused control has let the key through
7. Layer 4 (default bindings) handles quit, theme cycling, etc.
