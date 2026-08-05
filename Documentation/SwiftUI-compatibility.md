# SwiftUI Compatibility

A guide for porting SwiftUI code to TUIkit, and a record of **where** TUIkit's
public API matches or diverges from SwiftUI, **why**, and **whether the
divergence should change**.

TUIkit's stated rule (see `.claude/CLAUDE.md` → *SwiftUI API Parity*): public
APIs match SwiftUI signatures exactly **unless terminal constraints require
deviation**, and any deviation is documented. This file is that documentation.

---

## How this was determined

- **TUIkit side:** read from source (`Sources/…`, cited as `file:line`).
- **SwiftUI side:** the installed SDK's authoritative module interfaces —
  `SwiftUI.swiftinterface` **and** `SwiftUICore.swiftinterface` (most everyday
  `View` modifiers, `Color`, `Font`, layout, and `onChange` live in
  **`SwiftUICore`**) — with `@available(… deprecated:)` declarations excluded,
  and existence/deprecation confirmed by a `swiftc -typecheck` probe.
- **Version pinned:** Xcode 26.3 · Swift 6.2.4 · SwiftUI module 7.2.5 ·
  macOS 26.2 SDK. SwiftUI evolves; re-run against the current SDK when revising.

> A note on "deprecated": SwiftUI marks superseded API two ways — a real version
> (`deprecated: 14.0`, which the compiler warns on) and a "soft" forever-marker
> (`deprecated: 100000.0`, often with `renamed:`, no warning yet). **Both** mean
> "not the current spelling," so TUIkit omitting them is correct, not a gap.
> Examples correctly omitted: `foregroundColor` (→ `foregroundStyle`),
> `cornerRadius` (→ `clipShape`), `NavigationView` (→ `NavigationStack`/
> `NavigationSplitView`), `onChange(of:perform:)`, the old
> `ScrollView(_:showsIndicators:content:)` initializer.

---

## The guiding principle: measurement vs. data

The single most common divergence — `Int` instead of `CGFloat` — follows one
rule that resolves most of the numeric differences below:

| Kind of number | Type in TUIkit | Why |
|---|---|---|
| **An interface measurement** — a width, an x/y position, padding, spacing, a tap location | **`Int`** (and integer geometry, never `CGPoint`/`CGSize`) | A terminal is a grid of whole character cells. There is no "half a column." Floating-point here is not just unnecessary, it is *meaningless*, and inviting it leads to rounding bugs at every boundary. **Intentional divergence.** |
| **A value in your data model** — a `Stepper`'s count, a `ProgressView`'s fraction, a `Slider`'s position | **floating-point–capable** (generic over the value type, exactly like SwiftUI) | The number means something in *your* domain (a temperature, a price, a ratio). The renderer's cell-grid nature must not leak into your model. TUIkit is a faithful pass-through here. |

So: `.padding(8)` is `Int` and always will be; `Stepper(value: $temperature℃)`
accepts a `Double`. Keep these two ideas separate while reading the rest.

---

## Categories

1. [**Match** — ports cleanly, same API](#1-match)
2. [**Intentional divergence** — different on purpose; keep as-is](#2-intentional-divergence)
3. [**Open divergence** — known, documented, currently kept](#3-open-divergence)
4. [**No overlap** — one framework has it, the other doesn't](#4-no-overlap)
   - [4a. SwiftUI has it, TUIkit should add it](#4a-swiftui-has-it--tuikit-should-add-it)
   - [4b. SwiftUI has it, TUIkit won't (bitmap vs. text-cell)](#4b-swiftui-has-it--tuikit-wont-bitmap-vs-text-cell)
   - [4c. TUIkit-only (no SwiftUI equivalent)](#4c-tuikit-only)
5. [Summary](#5-summary)

---

## 1. Match

These port with no source change (modulo the `Int`-measurement rule in §2.1).
Code that uses them compiles and behaves the same.

| Area | API | TUIkit | Notes |
|---|---|---|---|
| Core | `View`, `some View`, `@ViewBuilder`, `ViewModifier` | ✓ | identity & composition match |
| State | `@State` (`init(wrappedValue:)` + `init(initialValue:)`), `@Binding` (`init(get:set:)`, `.constant`, `init(projectedValue:)`, **dynamic-member lookup**), `@Environment(\.key)` | ✓ | `$model.field` and `initialValue:` both work |
| Observation | `@Observable` + `@Environment(Type.self)` + `.environment(obj)` | ✓ | modern reference-type state ports as-is |
| Env / prefs | `EnvironmentKey`, `EnvironmentValues`, `PreferenceKey`, `.environment(_:_:)`, `.preference`/`.onPreferenceChange` | ✓ | custom keys work the SwiftUI way |
| Stacks | `VStack` / `HStack` / `ZStack` / `LazyVStack` / `LazyHStack` | ✓ | `spacing:` is `Int` → §2.1; default spacing → §2.1 note; lazy-stack semantics differ → §2.8 |
| Iteration | `ForEach` (`id:` keypath, `Identifiable`, `Range<Int>`), `Section` (header/footer/title), `Group` | ✓ | all three `ForEach` forms present |
| Data | `List` — content-closure **and** data-driven `List(_:id:selection:rowContent:)`, `Table` | ✓ | data-driven `List` routes through the windowed `ForEach` path (O(visible)) |
| Scrolling | `ScrollView(_:content:)`, `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)`, `defaultScrollAnchor(_:)` | ✓ | the `showsIndicators:` variant mirrors a soft-deprecated SwiftUI init; `scrollTo` targets `ForEach` row identities (no `.id(_:)` tagging yet) and vertical-only scroll views, resolving in O(window) even at millions of rows |
| Adaptive | `ViewThatFits(in:content:)` | ✓ | |
| Nav | `NavigationSplitView` (2/3-column, `columnVisibility:`), `navigationTitle` (`StringProtocol` / `Text`) | ✓ | a `Text` title renders as a plain string (its styling isn't carried) |
| Containers | `TabView` / `Tab`, `Form`, `LabeledContent`, `Label` (incl. `Label(_:systemImage:)`) | ✓ | `Label(_:systemImage:)` renders an SF Symbol glyph on Apple terminals → §2.4; `formStyle(.columns)` (default) / `.grouped` |
| Presentation | `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)`, `alert`, `confirmationDialog(_:isPresented:titleVisibility:actions:message:)` | ✓ | presented as a centred, dimming overlay. An `alert`/`confirmationDialog` dismisses when any of its actions is chosen (SwiftUI's behaviour — the action closure does not flip the binding itself), and claims Escape on the status bar while it is up, so a page's own `⎋ back` cannot navigate out from under it. Escape *is* the `.cancel`-role button (macOS gives Cancel the Escape key equivalent): it runs that action if there is one — a disabled one is skipped — and closes the dialog either way. A `sheet`/`modal` deliberately does NOT auto-dismiss: its content owns its own close button. |
| Lifecycle | `onAppear`, `onDisappear`, `task` (incl. `task(id:)`), `onChange(of:initial:_:)` (both current forms), `onHover` | ✓ | matches the *current* `onChange`; deprecated `perform:` correctly absent |
| Controls | `Button` (string **and** `Button(action:label:)`), `Toggle`, `Slider`, `Stepper`, `ProgressView`, `Gauge`, `TextField`, `SecureField`, `TextEditor`, `Picker`, `DatePicker`, `Link`, `ColorPicker`, `Divider`, `Spacer`, `EmptyView`, `AnyView`, `ContentUnavailableView` | ✓ | `Slider`/`ProgressView`/`Stepper`/`Gauge` are floating-point-capable; `Gauge` takes `.gaugeStyle(_:)` with terminal-native `.linearCapacity`/`.accessoryLinear`/`.accessoryLinearCapacity`/`.accessoryCircular`/`.accessoryCircularCapacity`/`.accessoryCircularTiny` (a closed set — a terminal can't host user-defined gauge geometries; the `Capacity` styles fill min→value cumulatively, the others mark only the value's position; circular styles draw a ring dial, `…Tiny` a single pie glyph); custom `ButtonStyle`/`ToggleStyle` via `makeBody`; `PickerStyle` is a marker protocol, matching SwiftUI; `Link` opens via `@Environment(\.openURL)` (no OSC 8 — §2.4-style deviation); `TextEditor` scrolls to follow the cursor (no soft-wrap yet); `DatePicker` is an inline numeric field (no calendar popup, fixed numeric format; Left/Right pick a component, Up/Down adjust it by one, Page Up/Down by a coarse step — a decade, a quarter, a week — and Home/End send it to the ends of its own range; the wheel steps whichever field it is pointing at — the one thing the keyboard cannot do without first walking to that field — in the framework's usual direction, wheel-up towards earlier); multi-selection is `List(selection: Binding<Set<…>>)` (SwiftUI has no multi-select `Picker`) |
| Modifiers | `padding`, `frame`, `overlay(alignment:content:)`, `fixedSize`, `foregroundStyle(.color)`, `disabled` (on any `View`), `tint`, `tag`, `zIndex`, `badge`, `listStyle`, `formStyle`, `lineLimit` (on `Text`), `multilineTextAlignment` | ✓ | units are `Int` → §2.1; `disabled` cascades via `\.isEnabled`; `tint` overrides the accent role (§2.5); `frame` default alignment is `.topLeading` → §2.7; `multilineTextAlignment` aligns a wrapped `Text`'s lines within its own block width (single-line text unaffected) |
| App | `App`, `Scene`, `WindowGroup`, `SceneBuilder`, `@main`, `@AppStorage`, `@Environment(\.dismiss)` | ✓ | `@AppStorage` is *enhanced* (pluggable backend) |
| Color values | `Color.red`/`.green`/`.primary`/`.secondary`/… and `.opacity(_:)` | ✓ | *constructing* a Color differs → §3 |

The parity surface above is regression-tested in
`Tests/TUIkitTests/SwiftUICompatFixesTests.swift`.

---

## 2. Intentional divergence

TUIkit provides the capability but deliberately shapes it differently because of
what a terminal *is*. **Verdict for every item here: keep as-is.**

### 2.1 Interface measurements are `Int`, not `CGFloat`

```swift
// SwiftUI                              // TUIkit
VStack(spacing: 8) { … }                VStack(spacing: 1) { … }
Text("Hi").padding(12)                  Text("Hi").padding(1)
.frame(width: 120, height: 44)          .frame(width: 20, height: 3)
.frame(maxWidth: .infinity)             .frame(maxWidth: .infinity)   // also supported
```

**Why it's intentional / should NOT change:** a terminal addresses whole
character cells — columns and rows — not points on a bitmap. `0.5` of a column
cannot be drawn. Using `CGFloat` would imply a precision the medium does not
have and would push rounding decisions onto every call site. `Int` says exactly
what it means: *N cells*. This is the canonical example of "terminal constraints
require deviation."

**Porting note:** integer literals just work (`.padding(8)`). What changes is
fractional/`CGFloat` values (`.padding(geo.size.width * 0.1)`) and
`.frame(maxWidth: 200)` — the fixed maximum is `FrameDimension` in TUIkit, so
write `.frame(maxWidth: .fixed(200))`; `.frame(maxWidth: .infinity)` is
unchanged.

**One sub-point worth knowing (not a defect):** stacks need a *concrete* default
where SwiftUI uses an adaptive system metric. TUIkit chose `VStack` spacing `0`
and `HStack` spacing `1` (terminals are dense; one blank column reads as a word
gap, zero blank rows reads as contiguous lines). Pass an explicit `spacing:` for
SwiftUI-like air.

### 2.2 Geometry is integer, never `CGPoint`/`CGSize`/`CGRect`/`UnitPoint`

```swift
// SwiftUI                              // TUIkit
.onTapGesture { /* () */ }              .onTapGesture { x, y in … }   // (Int, Int) cell coords
.onTapGesture(count: 2) { /* () */ }    .onTapGesture(count: 2) { … } // count: matched (perform: () -> Void)
DragGesture().onChanged { $0.location } // CGPoint                    .onDragGesture { e in (e.x, e.y) }  // Int
```

**Why it's intentional / should NOT change:** the same cell-grid reasoning as
§2.1, applied to composite values. A tap or drag resolves to a `(column, row)`
cell, full stop. Surfacing a `CGPoint` of `Double`s would be a fiction. TUIkit
deliberately exposes integer coordinates (`x`/`y` ints, `DragGestureEvent` with
integer fields). The same goes for `UnitPoint` anchors — there is no sub-cell
anchor to express.

### 2.3 Reactive model is `@Observable` only (no `ObservableObject` family)

```swift
// SwiftUI (legacy, Combine)            // TUIkit (and modern SwiftUI)
class M: ObservableObject {             @Observable class M {
  @Published var count = 0                var count = 0
}                                       }
@StateObject var m = M()                @State var m = M()
@ObservedObject var m: M                 // pass via @Environment(M.self) / init
@EnvironmentObject var m: M             @Environment(M.self) var m
```

**Why it's intentional / should NOT change:** `ObservableObject`/`@Published`/
`@StateObject`/`@ObservedObject`/`@EnvironmentObject` are the older,
Combine-based paradigm. Apple's own guidance is to use the Observation framework
(`@Observable`) for new code. TUIkit is new code with no legacy burden, so it
supports **only** the modern, best-practice path. This is a conscious choice to
keep one clear way to do it, not an omission. (These SwiftUI wrappers are
*not* deprecated — they coexist — so this is a deliberate non-support, not a
"correctly omitted deprecated API.")

### 2.4 `Image` is text/ASCII; SF Symbols render as glyphs, in narrow circumstances

```swift
// SwiftUI                              // TUIkit
Image("Logo")        // asset catalog   Image(.file("logo.png"))   // rasterised → ASCII art
                                        Image(.url("https://…/x.png"))
Label("Star", systemImage: "star.fill") Label("Star", systemImage: "star.fill")  // glyph, Apple only
```

**Bitmap / vector `Image` stays out.** A cell grid can't blit a bitmap or render
a vector glyph, so TUIkit converts a raster source to ASCII/ANSI art with its own
controls (`.imageCharacterSet`, `.imageColorMode`, `.imageDithering`). There is
no `Image(systemName:)`: an SF Symbol is not a resizable image in a terminal, only
a character, so it is modelled as text.

**SF Symbols DO render as glyphs — but only in very limited circumstances.**
`Label(_:systemImage:)` matches SwiftUI's signature, and `SFSymbol.glyph(named:)`
/ `SFSymbol.all` expose the mapping directly. Each SF Symbol lives in the
Plane-16 Private Use Area, so it renders **only** where a font supplies its
glyphs: an **Apple platform**, in a terminal using a font that has them
(**Terminal.app with SF Mono**, with the **SF Symbols font installed** — not the
default). Everywhere else — Linux, or a terminal without the font —
`Label(_:systemImage:)` shows just its title and `SFSymbol` resolves nothing, so
code stays correct; the glyph simply appears only where it can. The name →
codepoint table is Apple's own, extracted deterministically from the SF Symbols
app (`Tools/GenerateSFSymbols`), and the Private-Use width/advance is handled the
same way as VS-16 emoji. See `SFSymbol` for the full rules.

### 2.5 Theming is `palette` / `appearance`; there is no `colorScheme`

```swift
// SwiftUI                              // TUIkit
@Environment(\.colorScheme) var scheme  .palette(SystemPalette(.blue))     // View or Scene — ANSI colour roles
                                        .appearance(.rounded)              // border/figure set
.tint(.blue)                            .tint(.blue)                       // supported, matches (→ §1)
```

**Why it's intentional / should NOT change:** a terminal's "look" is a small set
of ANSI palette tokens and box-drawing styles, not a light/dark bitmap theme.
There is no `\.colorScheme`; the `.palette` (colours) and `.appearance` (border/
figure style) model maps cleanly to that reality and themes out-of-tree surfaces
(status bar, app header) too. Light/dark *can* be expressed as palettes if
desired. SwiftUI's `.tint(_:)` itself **is** supported and matches — it overrides
the accent role for the subtree (§1); `.palette` is the broader, TUI-only
superset (§4c).

### 2.6 Chrome is the status bar, not toolbars/commands

```swift
// SwiftUI                              // TUIkit
.toolbar { Button("Save"){…} }          .statusBarItems { StatusBarItem(shortcut:"s", label:"save"){…} }
.keyboardShortcut("s", modifiers:.command)  // shortcut lives in the StatusBarItem
```

**Why it's intentional / should NOT change:** terminals have no title bar or menu
bar; the universal idiom is a one-line status/shortcut bar at the bottom. TUIkit
models that directly. (A `keyboardShortcut`-style modifier for non-status-bar
actions is a fair §4a request, but the toolbar *container* concept does not
transfer.)

### 2.7 Fixed-`frame` default alignment is `.topLeading`, not `.center`

```swift
// Both compile; result differs:
Text("hi").frame(width: 20, height: 3)   // SwiftUI: centered    TUIkit: top-left
```

**Why it's intentional / should NOT change:** SwiftUI centres content in a larger
fixed frame because that's the GUI norm. A terminal reads from the top-left, and
in practice a fixed `.frame(width:)` is used to build a **left-aligned,
fixed-width column** — a label gutter, a channel slider, a table cell — far more
often than to centre something in slack space. Defaulting to `.center` would
silently shift every such column and surprise TUI authors. The default is
therefore `.topLeading`; pass an explicit `alignment:` when you do want centring.
(`ColorPicker`'s per-channel `Slider.frame(width:)` relies on this left
alignment.) The *flexible* `frame(maxWidth:…, alignment:)` **does** default to
`.center`, matching SwiftUI, because slack-space distribution is exactly when
centring makes sense.

### 2.8 Lazy stacks window the render; `List` is the scalable container

SwiftUI's lazy stacks (per the `LazyVStack` docs and the WWDC26 session
"Dive into lazy stacks and scrolling") are defined by **deferred view
creation inside a scroll view**: "the stack view doesn't create items until
it needs to render them onscreen"; scrolled-off views are released after a
few updates; the stack's main-axis extent is *estimated* ("based on the
average size of views that have been placed before, and the estimated number
of remaining subviews") and corrected as real views scroll in; the ideal
cross-axis size is **that of the first subview**; and `pinnedViews:` pins
section headers/footers.

TUIkit re-renders the tree every frame and retains no view objects, so
"creation cost" *is* render cost — and its lazy stacks are a **render
window**, not a deferred-creation machine:

- **Standalone** (the stack itself is the clipping container), they are
  genuinely lazy: whole children render top-down until the next would
  overflow `availableHeight`, and children past the fold are *never
  rendered* (so their `onAppear`/`task` correctly never fire). `VStack`
  instead distributes and clips at the cell.
- **Inside a `ScrollView`** (as the *direct* content), a `LazyVStack` now
  **windows to the visible viewport**: the ScrollView publishes its scroll
  slice and the stack renders only the rows intersecting it (into a
  full-height buffer, off-window rows blank), so `onAppear`/`task` fire on
  visibility — matching SwiftUI's model rather than materialising everything.
  A `LazyVStack` nested *below* other scroll content (not at the content
  origin) is left un-windowed, and `pinnedViews:` is still absent.
- **Cross-axis sizing** hugs the widest *placed* child (identical to
  `VStack`), which is stabler than SwiftUI's first-subview ideal — TUIkit
  has rendered every visible child anyway, so it knows the real width.
- **`pinnedViews:` does not exist** (→ §4a).

**Practical guidance (differs from SwiftUI's):** for large scrollable data
sets use `List` — its row materialisation is windowed to the viewport
(O(visible) row boxes per frame, id resolution included), making it TUIkit's
actual lazy container. Reach for `LazyVStack`/`LazyHStack` when the *stack
itself* is the clipped region (a fixed-height pane showing "as many whole
rows as fit"). Viewport-driven lazy rendering inside `ScrollView` now works
for a `LazyVStack` that is the direct scroll content; the remaining gaps
(windowing a stack nested below other content, and `pinnedViews:`) are → §4a.

---

## 3. Open divergence

One divergence is known and documented but currently kept as-is.

### `foregroundStyle` takes `Color?`, not `some ShapeStyle`

- **TUIkit:** `foregroundStyle(_ style: Color?)`; **SwiftUI:**
  `foregroundStyle<S: ShapeStyle>(_:)`.
- **Status — borderline §2, kept.** `.foregroundStyle(.red)` already works. The
  only thing lost is non-colour `ShapeStyle`s — gradients, materials — which are
  bitmap concepts that don't render in cells (see §4b). If a terminal-meaningful
  `ShapeStyle` (e.g. a 2-colour gradient approximated per cell) is ever wanted,
  widen the signature then. Documented here so the divergence is known.

---

## 4. No overlap

### 4a. SwiftUI has it · TUIkit should add it

Possible in a terminal, just not built yet. **Verdict: add over time**, roughly
in this priority order. (Proposals are one-liners; trade-offs noted where
non-obvious.)

| Feature | Why it matters | Design sketch / trade-off |
|---|---|---|
| **`NavigationStack` + `NavigationLink` + `navigationDestination(for:)` + `NavigationPath`** | Push/pop navigation is the backbone of most apps; TUIkit only has split-view. | Model a path stack of type-erased destinations; render the top of stack full-screen; back = pop. Biggest single gap. |
| **Presentation: `popover`, `fullScreenCover`, `presentationDetents`** | Common modal patterns. | `confirmationDialog` **shipped** — an action sheet (centred dimming overlay, ESC-dismiss, `titleVisibility`) with **vertically-stacked** buttons and the `.cancel` role sorted last; it reuses the alert host via a `verticalButtons` flag + a new `AlertButtonColumn`. `popover`/`fullScreenCover` ≈ `modal` variants; detents → fractional-height modal. |
| **`.scrollPosition` (bindable scroll state)** | Observable/bindable scroll position. (`ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` **shipped** — targets `ForEach` row identities, all anchor semantics, O(window) via the seek machinery; remaining: `.id(_:)`-tagged arbitrary targets, horizontal seeks.) | Grow the bindable `ScrollPosition` object out of the proxy registry; `.id` tagging folds into the identity system. |
| **Viewport windowing for a nested `LazyVStack` + `pinnedViews:`** | A `LazyVStack` that is the *direct* content of a `ScrollView` now windows to the viewport (§2.8) — the offset-publishing + render-only-visible policy landed. Remaining: a `LazyVStack` nested *below* other scroll content isn't at the content origin so it can't map the offset yet, and `pinnedViews:` is still absent from the lazy inits. | Thread the stack's own y-offset within the scroll content so a non-top stack can window too; `pinnedViews` then composites the active `Section` header over the viewport top. |
| **`@FocusState` as a property wrapper** | *(shipped)* `@FocusState var x: Bool` / `var f: Field?` + `.focused($x)` / `.focused($f, equals:)` + `.defaultFocus($f, value)`, matching SwiftUI. The value is derived from the persistent `FocusManager`; the imperative handle formerly called `FocusState` is now `FocusReference`. Remaining: `@FocusState` on multiple focusables in one `.focused` (SwiftUI binds a single control), and re-applying a default when a dismissed focus scope re-appears. |
| **`.keyboardShortcut` (general key equivalents)** | Bind an arbitrary key to any action. | The SEMANTIC actions shipped: `.keyboardShortcut(.defaultAction)` makes a Button the default (Return/Enter fires it whenever the focused control lets the key fall through — a `TextEditor` keeps its newline, a list keeps its row activation, a submit-less `TextField` lets Return through) and `.cancelAction` binds Escape. Arbitrary equivalents **shipped** too: `.keyboardShortcut("s", modifiers:)` with `KeyEquivalent` and `EventModifiers`. A terminal reports Control, Option and Shift but never ⌘, so the SwiftUI default `modifiers: .command` is remapped at registration to whatever the TUI-specific `.commandKey(_:)` names — `.control` (default), `.option`, `.bare`, or `.unavailable` — which is what lets one `View` source carry ⌘-shortcuts under both frameworks. Shift on a printable key is the character's CASE, not a modifier bit (that is all a terminal sends), and Control shortcuts on `c i j m z [` are undeliverable because the C0 range spends those bytes on Tab/Return/Escape and job control — see `KeyboardShortcut.isDeliverableInTerminal`. |
| **List editing: `onDelete`/`onMove`, `.listRowInsets`/`.listRowBackground`/`.listSectionSeparator`** | Editable lists. | `EditMode` + `\.editMode` + `EditButton` **shipped**, and `ForEach.onMove(perform:)` / `onDelete(perform:)` now **shipped**: attach the actions to a `ForEach` inside a `List` and press **Delete**/**Backspace** on the focused row to delete it, or drag a row with the mouse to reorder it (mirroring SwiftUI's drag trigger; `.rowReorderFeedback(_:)` chooses live-shuffle / dimmed-at-the-slot / row-on-the-pointer feedback). `move(fromOffsets:toOffset:)` / `remove(atOffsets:)` collection helpers ship alongside (constrained `Self.Index == Int` so they beat the Foundation⇄SwiftUI cross-import overlay's own unlinkable copies). Wired for a homogeneous all-content `List { ForEach … }` (a Section-nested ForEach is the known follow-up). `.listRow*` modifiers TBD. |
| **Common modifiers: `.opacity`(View), `.truncationMode`(View), `.onSubmit`/`.submitLabel`, `.refreshable`, `.contextMenu`, `.onReceive`** | Frequently used; each terminal-expressible. | `.id(_:)`, `.focusable(_:interactions:)`, `.searchable(text:placement:prompt:)`, `.onSubmit(of:_:)`/`.submitLabel(_:)`, and `.contextMenu(menuItems:)` **shipped** — `.contextMenu` is a right-click (or Ctrl-click, where a terminal swallows right-click) pop-up of `Button`s anchored at the click point, dismissed by selection, Escape, or an outside click; a right-click bubbles to an ancestor menu when a child doesn't handle it (the input dispatcher was extended to bubble the secondary button like the wheel), and reliable right-click needs Apple Terminal / Ghostty / Warp (iTerm2 claims it by default — see Terminal-compatibility.md); the TUI-specific `.onMenuOpen(_:)` reports a pop-up (a `contextMenu` or a `Menu`) OPENING to any view above it, which is how an app clears whatever the last choice left on screen so choosing the same item twice reads as two choices — SwiftUI has no equivalent, its menus being system-drawn. — `.id` splices a keyed identity step (resets `@State`, re-fires `onAppear`/`task`, drops the cached buffer); `.focusable` makes any view a Tab stop + click-to-focus (`.activate`) and lets `.focused($x)` bind to a plain view; `.searchable` composes a glyph + bound `TextField` above the content (filtering is app-driven; `placement` is inert in a terminal, but the TUI-specific `.searchFieldIconPlacement(.leading/.trailing)` moves the magnifier and swaps it 🔎↔🔍 so its lens faces the field); `.onSubmit(of:)` cascades a submit action through the environment (`.text` for `TextField`/`SecureField`, `.search` for the `.searchable` field) and composes additively with a field's own `.onSubmit(_:)` closure — the combined action stays nil when empty so Return still falls through to a default button, and `TextEditor` doesn't submit (Return = newline); `.submitLabel` is stored for parity (no on-screen Return key). `.opacity` → dim/blend approximation only. (`.multilineTextAlignment` shipped — §1.) |
| **Scoped wrappers: `@SceneStorage`, `@FocusedValue`** | binding into scoped state. | `@Bindable` **shipped** (derives a `Binding` into an `@Observable` reference you already own; not a source of truth, so it holds no storage and takes no part in render-identity binding). `@SceneStorage` ≈ `@AppStorage` for a single scene; `@FocusedValue` is niche. |
| **Env values: `\.layoutDirection`, `\.dynamicTypeSize`, `\.scenePhase`** | Standard environment reads. | `\.openURL` (via `Link`) and `\.locale` **shipped** — `\.locale` is a stored, settable key populated each frame from the app language (single source of truth), so overriding it with `.environment(\.locale, _)` re-locales the number chrome in `Table`/`List`/`ScrollView`. `\.scenePhase` is independently useful; size-class concepts map loosely to terminal dimensions. (`\.isEnabled` present — §1.) |
| **Text richness: `LocalizedStringKey`, `AttributedString`, Markdown, `Text + Text`** | Formatting & localization. | `Text(_:format:)` **shipped** (formats eagerly with the format style's own locale — env-`\.locale` re-resolution is a separate, tracked item below). `Text + Text` concatenation is tractable but needs a per-run styling model in `Text`; full `AttributedString`/Markdown is larger. TUIkit has a localization service to build `LocalizedStringKey` on. |

#### Implicit / view-internal behaviours (not public API — but SwiftUI does them for you)

Parity isn't only the programmable API surface — the modifiers and initializers
you *call*. It's also the behaviours SwiftUI's built-in views exhibit **on their
own**. A `List` you never configured still lets you drag its rows to reorder them
in edit mode; a `Table` re-sorts when you click a column header; a focused
`TextField` can grow a clear button. Reproducing these is as much a part of
"acting like SwiftUI" as matching a signature — adapting the *gesture* (a terminal
has no swipe) while preserving the *behaviour*. **Verdict: mimic, best-effort**,
tracked here as the behavioural companion to §4a's API gaps.

| Behaviour | SwiftUI does it… | Terminal adaptation |
|---|---|---|
| **Drag-to-reorder rows** in `List`/`Table` | drag a row (edit mode / backed by `.onMove`) to a new slot | **shipped** (List + `ForEach.onMove`): mouse-press picks a row up, and what the drag then shows is chosen by the TUI-specific `.rowReorderFeedback(_:)` — `.live` (the default) reorders as the cursor moves, so the list itself is the preview, at the cost of one `onMove` per slot crossed; `.dimmed` and `.cursor` both take the row OUT of its place — the list closes up behind it and keeps its length — and open a slot where it would land, holding a faint copy of the row (`.dimmed`) or nothing at all (`.cursor`, which floats the row on the pointer instead, above every other view). So the preview IS the result: the mid-drag order is exactly the order the drop produces. Drag out of the list under `.cursor` and the gap goes — the row keeps riding the pointer, so releasing there simply puts it back. Both move the data once, on release. The drag hit-tests against the row geometry the list republishes each render, not a press-frame copy — under `.live` the rows genuinely move out from under it. `Table` takes drops between its rows through a TUI-specific `Table.dropDestination(for:action:)` — same reason, same shape as `ForEach`'s, opening the same landing slot and reporting the index it opened at (one past the end fills an EMPTY table). `Table` has reordering too, via a TUI-specific `Table.onMove(_:)` — a modifier on the table rather than on a `ForEach`, because a `Table`'s rows are values and its cells are not views, so there is no `ForEach` to attach SwiftUI's row-level `onMove` to (SwiftUI's own `Table` has no move at all). One state machine drives both, so all three feedback modes behave identically — except on a MULTI-LINE table, which reorders `.live` only: a drop slot would have to take part in the line-budget arithmetic that lets a tall row be partially clipped. |
| **Press-and-hold menu tracking** on a pop-up `Menu` / `Picker` / combo box / `.contextMenu` | press the control and keep the button down: the menu opens, dragging highlights the row under the pointer, releasing over one chooses it — and a quick click leaves the menu up to be picked from with a second click | **shipped**, both halves. The menu opens on the PRESS and the control then hands the rest of the gesture back to live hit-testing (`MouseEventDispatcher.handOffGesture()`), so the drag and release land on the menu rather than routing back to the button that opened it; a menu row treats a `.dragged` like a hover, because a terminal reports a held move as a drag and never as motion. An ordinary `Button` still fires on RELEASE, and still claims its press, so sliding off one to cancel keeps working. A `.contextMenu` is the same gesture with the RIGHT button — it opens on the right press and tracks with it held — which is why menu rows answer either button; right-clicking OUTSIDE an open menu still closes it and lands on whatever it hit, in the one gesture. |
| **Click a column header to sort** a `Table` | `TableColumn(sortUsing:)` + a `sortOrder` binding; header click toggles asc/desc | clickable header cells that toggle a sort indicator and re-sort the bound order |
| **Swipe actions** on a `List` row | `.swipeActions { … }` reveals buttons | no swipe in a terminal — surface as a per-row action menu (key, or drag the row aside) |
| **Clear button** in a `TextField` | some field styles show an "✕" while editing a non-empty field | optional trailing clear affordance on a focused, non-empty field |
| **Auto-scroll to keep selection/focus visible** | the list scrolls so the active row stays on-screen | *largely shipped* (selection-reveal + follow-margin) — audit remaining edge cases |
| **Expand/collapse hierarchy** (`DisclosureGroup`/`OutlineGroup`) | click a disclosure triangle to expand a node | a disclosure glyph (▶/▼) toggled by click / Enter on the row |
| **Type-ahead selection** in `Picker`/`Menu`/`List` | type a prefix to jump to a matching item | match typed characters against visible item labels to move the selection |

This table will grow as we notice more of SwiftUI's built-in behaviours.

### 4b. SwiftUI has it · TUIkit won't (bitmap vs. text-cell)

These are intrinsic to a *bitmap* renderer and have no faithful meaning in a grid
of character cells. **Verdict: don't add** (or add only a deliberately
reinterpreted, lossy analog, clearly named so no one expects fidelity).

| Feature | Why it can't transfer faithfully |
|---|---|
| **`Font` / `.font` / weights / sizes / designs** | The terminal owns the typeface and size; an app can't set them. Emphasis is limited to ANSI bold/italic/underline (which `Text` already exposes). |
| **Animation & transitions** (`Animation`, `withAnimation`, `.transition`, `AnyTransition`, `matchedGeometryEffect`, `PhaseAnimator`) | Smooth interpolation needs sub-cell/sub-frame precision and a compositor. TUIkit redraws discrete frames on demand; there's no tween space. (Cursor/spinner pulsing is the deliberate exception.) |
| **Shapes & vector drawing** (`Shape`, `Path`, `Rectangle`/`Circle`/`RoundedRectangle`, `Canvas`, `GraphicsContext`, `fill`/`stroke`) | Vectors rasterize to pixels. Cells can only approximate with box-drawing/block glyphs (which `.border` already does for rectangles). |
| **Sub-cell geometry** (`.offset`, `.position`, `.scaleEffect`, `.rotationEffect`, `.rotation3DEffect`) | Positioning/scaling/rotating by fractional points is undefined on a grid. (Integer cell *placement* is done via stacks/frames.) |
| **Pixel filters** (`.blur`, `.shadow`, `.opacity` blending, `.brightness`/`.contrast`/`.saturation`/`.hueRotation`, `.colorInvert`, `.clipShape`/`.mask`) | These are per-pixel compositing ops. A cell is one glyph + fg/bg color; there's nothing to blur or feather. (`.colorInvert` ≈ TUIkit's `.inverted()` on `Text` is the closest analog.) |
| **`GeometryReader` / `GeometryProxy` / coordinate spaces / custom alignment guides** | Point-precise geometry read-back. Cell-grid layout uses integer sizes via the two-pass measure system; a coarse, integer "container size reader" *could* be offered, but not SwiftUI's `CGRect`/coordinate-space model. |
| **Accessibility (VoiceOver/traits/rotors)** | Not bitmap-inherent, but tied to GUI a11y services; a terminal-native a11y story would be a separate design, not the SwiftUI API. Low priority. |

### 4c. TUIkit-only (no SwiftUI equivalent)

Things a terminal needs that SwiftUI has no concept of. **Verdict: keep** —
these are the value-add of a TUI framework. Keep them clearly *named apart* from
SwiftUI API (the CLAUDE.md rule).

| API | Purpose |
|---|---|
| `.onKeyPress`, `.onMouseEvent`, `.onScrollGesture`, `.onDragGesture` | raw terminal input events (integer coords) |
| `.statusBarItems`, system status items | bottom status/shortcut bar |
| `.focusSection`, `.focusID`, `unfocusedSelectionVisibility`, `selectionDisabled` | terminal focus model (Tab/Shift-Tab between sections) |
| `.palette` / `.appearance` (View **and** Scene), `SystemPalette`, `ColorDepth`, `BorderStyle` | ANSI theming + capability tiers |
| `.mouseSupport` (Scene) | opt into terminal mouse tracking modes |
| `.appHeader`, `.notificationHost`, `.modal` | out-of-tree surfaces + terminal modal |
| `.textCursor(_:animation:speed:)` | text-field cursor shape/blink |
| `.dimmed()`, `Text.dim()/.blink()/.inverted()` | ANSI display attributes |
| Image: `.imageCharacterSet`/`.imageColorMode`/`.imageDithering`/… | raster→ASCII conversion controls |
| `Card`, `Panel`, `RadioButton`/`RadioButtonGroup`, `Spinner`, `TrackStyle`, `IndeterminateStyle` | terminal-idiomatic containers/controls/styles |
| `MenuStyle.inline` (+ `.menuStyle(_:)`) | a `Menu` rendered expanded in place under its label, rather than collapsed behind it. SwiftUI has no inline menu style; a terminal app's landing screen often *is* a menu, and making the user open the only thing on the page would be perverse. The rows are the same `Button`s either way, and each prints its `keyboardShortcut` at its trailing edge (`^S` for Control, `M-s` for Option — not ⌃⌥, whose width is ambiguous). A menu taller than its space scrolls inside its border, with the focus reveal following the arrows. |
| `TrackStyle.custom(TrackConfiguration)` | fully-configurable progress/slider/gauge fill (glyphs, sub-cell ramp, solid-background unfilled, gradient); the named styles are presets of it |
| `List`/`Table` `.onRowActivate(_:)`, `MouseEvent.clickCount` | row activation — double-click OR Return/Enter on the focused row (Space keeps selecting); the closest SwiftUI analogue is `contextMenu(forSelectionType:…primaryAction:)`. Terminals report no double-click, so the dispatcher synthesises `clickCount` by timing |
| `.radioButtonGroupEdgeBehavior(_:)` | what an on-axis edge-arrow in a `RadioButtonGroup` does: `.contain` (stay in the group, the default — like `List`/`Table`; use Tab to leave), `.escape` (relinquish to the next control), or `.wrap` (cycle within the group) |
| Image charsets `.ascii(glyphs:)` / `.unicode(glyphs:)` / `.blocks(_:)` / `.customRamp(_:)`, `.imageShapeAware(_:)` | raster→text rendering as three orthogonal choices: the fundamental charset, its size (the `glyphs` count picks the ideal calibrated subset; blocks use a discrete resolution), and shape-aware glyph matching (measured in-cell ink distribution; applies to blocks too via quadrants/halves/corner triangles) |
| `.imageSupersampling(_:)`, `.imageEdgeThreshold(_:)` | image-fidelity knobs: N×N area averaging of every sample for the non-shape renderers (1...4; nil = default; the shape matcher's 96-sample grid needs none), and the shape-aware ascii/unicode edge-glyph gradient threshold (lower = more edges; nil = pure coverage matching) |
| `.tabWidth(_:)` (`TabWidth.periodic`/`.fixed`) | tab-stop layout for literal tabs in `TextEditor` (default: snap to 4-column stops, like the text system's `defaultTabInterval`; SwiftUI exposes no tab control) |
| `.navigationSplitViewResizable`, `.navigationSplitViewColumnWidth`, `.fixedSize` on `List`, `.listEmptyPlaceholder` | terminal split/list affordances |
| `formRowAlignment(_:)` | per-row override of a `Form`'s column alignment |
| `.scrollChainingDelay(_:)` | grace period before wheel ticks blocked at a nested scroller's edge chain to the parent (default 500 ms; `.zero` chains immediately) |
| `.scrollGranularity(_:)` (`ScrollGranularity.line`/`.row`) | how finely `List`/`Table` viewports move through multi-line rows — by terminal line (default: tall rows scroll in gradually, partially clipped at the top) or by whole row (classic TUI jumps). Selection/focus stay row-based; SwiftUI scrolls by pixels so the question doesn't arise there |
| `.scrollExtentPrecision(_:)` (`ScrollExtentPrecision.approximate`/`.exact`) | how precisely a `List`/`Table` measures the rows outside its viewport. Off-screen rows only feed the scroll indicators, so by default they are sampled rather than wrapped (O(1) rather than O(rows) per frame); `.exact` measures every row where a proportionally exact thumb is worth the cost. No effect on single-line rows, where the extent is already exact for free |
| `.onRenderPass(_:)` (`RenderPass.measure`/`.render`) | instrumentation hook: observe a view's participation in measurement vs real rendering (e.g. what a lazy container measures but never draws) |
| `.maxFrameRate` (App) | cap redraw rate |

---

## 5. Summary

The SwiftUI parity surface (§1) ports without source changes, modulo the
`Int`-measurement rule. Everything in §2 and §4b is intentional and should
**not** change: the `Int` measurement model, integer geometry, top-left
fixed-`frame` alignment, `@Observable`-only state, the `palette`/`appearance`
theming model, and the absence of fonts/animation/shapes/sub-cell-geometry are
the honest consequences of rendering to a grid of character cells rather than a
bitmap. §3 is the one remaining documented divergence (`foregroundStyle`), kept
deliberately. The roadmap is §4a — additive SwiftUI features that a terminal can
express but TUIkit hasn't built yet, led by `NavigationStack` on the API side and
by click-a-column-header-to-sort on the *implicit-behaviour* side (the behaviours
SwiftUI's built-in views perform on their own, not just the API you call — that
table's former flagship, drag-to-reorder rows, now ships).
