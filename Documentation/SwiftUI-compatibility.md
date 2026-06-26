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
| **A value in your data model** — a `Stepper`'s count, a `ProgressView`'s fraction, a `Slider`'s position | **floating-point–capable** (generic over the value type, exactly like SwiftUI) | The number means something in *your* domain (a temperature, a price, a ratio). The renderer's cell-grid nature must not leak into your model. TUIkit should be a faithful pass-through here. |

So: `.padding(8)` is `Int` and always will be; `Stepper(value: $temperature℃)`
must accept a `Double`. Keep these two ideas separate while reading the rest.

---

## Categories

1. [**Match** — ports cleanly, same API](#1-match)
2. [**Intentional divergence** — different on purpose; keep as-is](#2-intentional-divergence)
3. [**Unintentional divergence** — partial/accidental mismatch; should change](#3-unintentional-divergence)
4. [**No overlap** — one framework has it, the other doesn't](#4-no-overlap)
   - [4a. SwiftUI has it, TUIkit should add it](#4a-swiftui-has-it--tuikit-should-add-it)
   - [4b. SwiftUI has it, TUIkit won't (bitmap vs. text-cell)](#4b-swiftui-has-it--tuikit-wont-bitmap-vs-text-cell)
   - [4c. TUIkit-only (no SwiftUI equivalent)](#4c-tuikit-only)
5. [Recommended changes, prioritized](#5-recommended-changes-prioritized)

---

## 1. Match

These port with no source change (modulo the `Int`-measurement rule in §2.1).
Code that uses them compiles and behaves the same.

| Area | API | TUIkit | Notes |
|---|---|---|---|
| Core | `View`, `some View`, `@ViewBuilder`, `ViewModifier` | ✓ | identity & composition match |
| State | `@State`, `@Binding` (`init(get:set:)`, `.constant`), `@Environment(\.key)` | ✓ | `@State` lacks `init(initialValue:)` → §3.7; `@Binding` lacks dynamic-member lookup → §3.2 |
| Observation | `@Observable` + `@Environment(Type.self)` + `.environment(obj)` | ✓ | modern reference-type state ports as-is |
| Env / prefs | `EnvironmentKey`, `EnvironmentValues`, `PreferenceKey`, `.environment(_:_:)`, `.preference`/`.onPreferenceChange` | ✓ | custom keys work the SwiftUI way |
| Stacks | `VStack` / `HStack` / `ZStack` / `LazyVStack` / `LazyHStack` | ✓ | `spacing:` is `Int` → §2.1; default spacing → §2.1 note |
| Iteration | `ForEach` (`id:` keypath, `Identifiable`, `Range<Int>`), `Section` (header/footer/title), `Group` | ✓ | all three `ForEach` forms present |
| Scrolling | `ScrollView(_:content:)` | ✓ | the `showsIndicators:` variant mirrors a soft-deprecated SwiftUI init |
| Adaptive | `ViewThatFits(in:content:)` | ✓ | |
| Nav | `NavigationSplitView` (2/3-column, `columnVisibility:`) | ✓ | |
| Lifecycle | `onAppear`, `onDisappear`, `task` (no `id:` → §3.9), `onChange(of:initial:_:)` (both current forms), `onHover` | ✓ | matches the *current* `onChange`; the deprecated `perform:` form is correctly absent |
| Controls | `Toggle`, `Slider`, `ProgressView`, `TextField`, `SecureField`, `Picker`, `Divider`, `Spacer`, `EmptyView`, `AnyView`, `ContentUnavailableView` | ✓ | label/value details below; `Slider`/`ProgressView` already floating-point ✓ |
| Modifiers | `padding`, `frame`, `overlay(alignment:content:)`, `fixedSize`, `foregroundStyle(.color)`, `tag`, `zIndex`, `badge`, `listStyle`, `disabled` (on controls), `lineLimit` (on `Text`) | ✓ | units are `Int` → §2.1; `frame` default alignment → §3.6 |
| App | `App`, `Scene`, `WindowGroup`, `SceneBuilder`, `@main`, `@AppStorage`, `@Environment(\.dismiss)` | ✓ | `@AppStorage` is *enhanced* (pluggable backend) |
| Color values | `Color.red`/`.green`/`.primary`/`.secondary`/… and `.opacity(_:)` | ✓ | *constructing* a Color differs → §3 (Color) |

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
.onTapGesture(count: 2) { p in p.x }    // p: CGPoint                 // count: → §3.13
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
keep one clear way to do it, not an omission. (Note these SwiftUI wrappers are
*not* deprecated — they coexist — so this is a deliberate non-support, not a
"correctly omitted deprecated API.")

### 2.4 `Image` is text/ASCII, not bitmaps or SF Symbols

```swift
// SwiftUI                              // TUIkit
Image(systemName: "star.fill")          // no SF Symbols
Image("Logo")        // asset catalog   Image(.file("logo.png"))   // rasterised → ASCII art
                                        Image(.url("https://…/x.png"))
```

**Why it's intentional / should NOT change (mostly):** a cell grid can't blit a
bitmap or render a vector glyph. TUIkit converts a raster source to ASCII/ANSI
art with its own controls (`.imageCharacterSet`, `.imageColorMode`,
`.imageDithering`). *Caveat:* a curated `systemName:` → Unicode-glyph mapping
(e.g. `"star.fill"` → `★`) would be a reasonable future addition — tracked in
§4a — but bitmap/vector `Image` itself stays out.

### 2.5 Theming is `palette` / `appearance`, not `colorScheme` / `tint`

```swift
// SwiftUI                              // TUIkit
.tint(.blue)                            .palette(SystemPalette(.blue))     // View or Scene
@Environment(\.colorScheme) var scheme  .appearance(.rounded)              // border/figure set
```

**Why it's intentional / should NOT change:** a terminal's "look" is a small set
of ANSI palette tokens and box-drawing styles, not a light/dark bitmap theme
with arbitrary tints. The palette/appearance model maps cleanly to that reality
and themes out-of-tree surfaces (status bar, app header) too. (Light/dark *can*
be expressed as palettes if desired.)

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

---

## 3. Unintentional divergence

TUIkit has an equivalent that *should* line up with current SwiftUI but doesn't,
through oversight or incompleteness. **These are the candidates to fix.** Each
entry: the mismatch, whether to change (in plain terms), a design sketch, and
trade-offs.

### 3.1 `Stepper` is `Int`-only — should be generic over the value

```swift
// SwiftUI                                          // TUIkit (today)
Stepper("Qty", value: $count, in: 0...10)           Stepper("Qty", value: $count, in: 0...10)   // count: Int only
Stepper("°C", value: $celsius, step: 0.5)           // ❌ won't compile — Binding<Double> rejected
```

- **TUIkit:** all `Stepper` inits take `Binding<Int>`, `step: Int`
  ([Stepper.swift:108](../Sources/TUIkit/Views/Stepper.swift)). The generics
  present are over the *title* `StringProtocol`, not the value.
- **SwiftUI:** generic over `V: Strideable` (covers `Int`, `Double`, `Float`, …).
- **Should it change? Yes.** A `Stepper`'s value is *data-model* data (a price, a
  temperature, a rating), not an interface measurement — so the §"measurement vs.
  data" rule says it must not be pinned to `Int`. This is the one data-model
  control that's inconsistent: `Slider` and `ProgressView` already use
  `BinaryFloatingPoint` correctly.
- **Proposal:** genericize as `Stepper<Label>` with
  `init(_:value: Binding<V>, in: ClosedRange<V> = …, step: V.Stride = 1, …)`
  where `V: Strideable`, mirroring SwiftUI. Keep an `Int`-defaulted convenience so
  existing call sites are unchanged. Clamp/step in `V`'s arithmetic.
- **Trade-offs / side-effects:** `Stepper` renders a *label* + `[- +]`, not the
  numeric value itself, so there's no display-formatting fallout. Minor: bounds
  clamping in floating-point needs the usual care at the range ends; `V.Stride`
  vs `V` for `step`. Low risk, additive.

### 3.2 `Binding` has no dynamic-member lookup or `init(projectedValue:)`

```swift
// SwiftUI                              // TUIkit (today)
TextField("Name", text: $user.name)     // ❌ $user.name — no nested Binding
Toggle("On", isOn: $settings.enabled)   // ❌
```

- **TUIkit:** `Binding` exposes `init(get:set:)` + `.constant`
  ([State.swift:264](../Sources/TUIkitView/State/State.swift)) — but not
  `@dynamicMemberLookup` nor `init(projectedValue:)`.
- **Should it change? Yes.** Deriving a binding to a sub-property (`$model.field`)
  is everyday SwiftUI; without it, forms over an `@Observable`/struct model are
  far clumsier than they should be. Pure ergonomics, no terminal reason to omit.
- **Proposal:** mark `Binding` `@dynamicMemberLookup` and add
  `subscript<Subject>(dynamicMember: WritableKeyPath<Value, Subject>) -> Binding<Subject>`
  plus `init(projectedValue:)`. Both are mechanical, matching SwiftUI verbatim.
- **Trade-offs:** none of substance — purely additive; no rendering or layout
  impact. High value-to-cost ratio.

### 3.3 `disabled()` is per-control, not a `View` modifier

```swift
// SwiftUI                              // TUIkit (today)
VStack { … }.disabled(isLocked)         // ❌ disabled only exists on Button/Toggle/…
Text("x").disabled(true)                // ❌
```

- **TUIkit:** `disabled(_:)` is defined on each control type (Button, Toggle,
  Slider, …) and returns that concrete type — there is no `View.disabled(_:)`.
- **SwiftUI:** `View.disabled(_ disabled: Bool)` disables an entire subtree via
  the environment.
- **Should it change? Yes.** Disabling a *group* ("grey out this whole panel
  while saving") is a basic need and currently impossible without touching every
  child.
- **Proposal:** add an `\.isEnabled` environment value that ANDs down the tree,
  plus `extension View { func disabled(_:) }` that clears it; interactive views
  read `environment.isEnabled` in their existing disabled check + skip focus
  registration when disabled. (This also delivers the `\.isEnabled` env value
  from §4a for free.)
- **Trade-offs:** must audit every interactive control to consult the inherited
  flag (several already gate on a local `isDisabled`); the per-control
  `disabled(_:)` methods stay as sugar. Medium effort, well-contained.

### 3.4 `List` has no data-driven initializer

```swift
// SwiftUI                              // TUIkit (today)
List(items) { item in Text(item.name) } // ❌ no data-driven form
List(items, id: \.id, selection: $sel)   // ❌
                                        // must write:
                                        List(selection: $sel) {
                                          ForEach(items) { item in Text(item.name) }
                                        }
```

- **TUIkit:** `List` is content-closure only
  ([List.swift:58](../Sources/TUIkit/Views/List.swift)); data goes through an
  explicit `ForEach`.
- **SwiftUI:** ships ~50 data-driven `List(_:…rowContent:)` overloads.
- **Should it change? Yes (convenience).** It's the most common `List` spelling
  in SwiftUI tutorials and code; its absence is a visible papercut even though
  the `ForEach` form is equivalent.
- **Proposal:** add `List(_ data:, id:, selection:, rowContent:)` overloads that
  internally construct the existing `ForEach` + windowed row path — no new
  rendering, just initializer sugar.
- **Trade-offs:** keep the overload count sane (mirror SwiftUI's selection
  variants only); ensure the sugar routes through the same windowed extractor so
  large lists keep their O(visible) cost. Low-medium effort.

### 3.5 `sheet` lacks `onDismiss:` and the `item:` overload

```swift
// SwiftUI                                        // TUIkit (today)
.sheet(isPresented: $show, onDismiss: cleanup){…} // ❌ no onDismiss
.sheet(item: $editing) { row in EditView(row) }   // ❌ no item:
.sheet(isPresented: $show) { … }                  // ✓ this form works
```

- **Should it change? Yes.** `onDismiss` (run cleanup when closed) and `item:`
  (present *for* a selected value) are standard; both map cleanly to a terminal
  modal.
- **Proposal:** add `onDismiss: (() -> Void)? = nil` to the existing
  `sheet`/`modal` modifiers (fire it when the overlay tears down), and add
  `sheet(item: Binding<Item?>, …)` for `Item: Identifiable`.
- **Trade-offs:** the modal teardown path must reliably invoke `onDismiss` on
  every dismissal route (key, action, programmatic). Low-medium.

### 3.6 Fixed-`frame` default alignment is `.topLeading`, SwiftUI's is `.center`

```swift
// Both compile; result differs:
Text("hi").frame(width: 20, height: 3)   // SwiftUI: centered    TUIkit: top-left
```

- **TUIkit:** `frame(width:height:alignment:)` defaults `alignment` to
  `.topLeading`; SwiftUI defaults to `.center` (`SwiftUICore` `frame` decl).
- **Should it change? Probably yes — reconcile to `.center`.** This is a *silent*
  divergence: ported code lays out differently with no error. Unlike §2 there's
  no terminal reason for it — both alignments are expressible. (If the top-left
  default was a deliberate "text reads from the top-left" choice, document it as
  §2 instead; absent that rationale, match SwiftUI.)
- **Proposal:** change the default to `.center`.
- **Trade-offs:** **behavioral** — existing TUIkit layouts relying on the current
  default shift. Requires a sweep of the example app + updating any golden
  snapshots. Worth doing once, early.

### 3.7 `@State` lacks `init(initialValue:)`

- **TUIkit:** `init(wrappedValue:)` only; **SwiftUI:** also `init(initialValue:)`.
- **Should it change? Yes (cheap).** Rarely written by hand, but some generic
  code and macros use it.
- **Proposal:** add the `init(initialValue:)` alias. **Trade-offs:** none.

### 3.8 `task` lacks the `id:` overload

```swift
// SwiftUI                              // TUIkit (today)
.task(id: query) { await search(query) } // ❌ no id: → can't restart on change
.task { await load() }                    // ✓
```

- **Should it change? Yes.** Re-running an async task when an input changes is a
  core `.task` use; without it you hand-roll `onChange` + cancellation.
- **Proposal:** add `task(id:priority:_:)` that folds `id` into the lifecycle
  token and restarts when it changes — small extension of the existing
  identity-keyed lifecycle mechanism.
- **Trade-offs:** none beyond the token bookkeeping already in place. Low.

### 3.9 `Button`/style labels are `String`, not views

```swift
// SwiftUI                              // TUIkit (today)
Button { save() } label: {              Button("Save", action: save)   // String only
  Label("Save", systemImage: "tray")    // ❌ no @ViewBuilder label
}
```

- **TUIkit:** `Button(_ label: String, action:)` only
  ([Button.swift:103](../Sources/TUIkit/Views/Button.swift)); consequently
  `ButtonStyle.Configuration.label` is a `String`, and `ToggleStyle`/`PickerStyle`
  are empty marker protocols (built-in styles only).
- **Should it change? Partially.** A terminal *can* render a composed label (icon
  glyph + styled text), so a `@ViewBuilder label:` form is reasonable and unlocks
  authoring custom styles. Lower priority than 3.1–3.5.
- **Proposal:** add `Button(action:label:)` with a `@ViewBuilder` label; make the
  style `Configuration.label` an opaque rendered view; give `ToggleStyle`/
  `PickerStyle` a `makeBody(configuration:)` requirement.
- **Trade-offs:** non-trivial — the style pipeline currently assumes string
  labels; touches Button/Toggle/Picker rendering and the style configuration
  types. Medium-high; stage after the quick wins.

### 3.10 `navigationTitle` takes `String` only

- **TUIkit:** `navigationTitle(_ title: String)`; **SwiftUI:** also `Text`,
  `LocalizedStringKey`, and `Binding<String>` overloads.
- **Should it change? Minor yes.** Add a `StringProtocol` (and optionally `Text`)
  overload. **Trade-offs:** trivial; full localization is a separate §4a item.

### 3.11 `foregroundStyle` takes `Color?`, not `some ShapeStyle`

- **TUIkit:** `foregroundStyle(_ style: Color?)`; **SwiftUI:** `foregroundStyle<S: ShapeStyle>(_:)`.
- **Should it change? No (for now) — borderline §2.** `.foregroundStyle(.red)`
  already works. The only thing lost is non-color `ShapeStyle`s — gradients,
  materials — which are bitmap concepts that don't render in cells (see §4b). If
  a terminal-meaningful `ShapeStyle` (e.g. a 2-color gradient approximated per
  cell) is ever wanted, widen then. Documented here so the divergence is known.

---

## 4. No overlap

### 4a. SwiftUI has it · TUIkit should add it

Possible in a terminal, just not built yet. **Verdict: add over time**, roughly
in this priority order. (Proposals are one-liners; trade-offs noted where
non-obvious.)

> **Since shipped** (now built; removed from the list below): `TabView` / `Tab`,
> `ColorPicker` (with a full modal `ColorPickerPanel`), and the `.tint(_:)` modifier.

| Feature | Why it matters | Design sketch / trade-off |
|---|---|---|
| **`NavigationStack` + `NavigationLink` + `navigationDestination(for:)` + `NavigationPath`** | Push/pop navigation is the backbone of most apps; TUIkit only has split-view. | Model a path stack of type-erased destinations; render the top of stack full-screen; back = pop. Biggest single gap. |
| **Presentation: `confirmationDialog`, `popover`, `fullScreenCover`, `presentationDetents`** | Common modal patterns. | `confirmationDialog` ≈ an action-list `alert`; `popover`/`fullScreenCover` ≈ `modal` variants; detents → fractional-height modal. |
| **`ScrollViewReader` / `ScrollViewProxy.scrollTo` / `.scrollPosition`** | Programmatic scrolling. | Expose the existing internal scroll-offset state through a proxy keyed by row id. |
| **`@FocusState` as a property wrapper** *(also a §3-style fix)* | SwiftUI's focus is `@FocusState var x` + `.focused($x)`; TUIkit's `FocusState` is a manually-constructed class — source-incompatible. | Wrap the existing `FocusManager` in a `@propertyWrapper struct FocusState<Value: Hashable>` + `.focused(_:)`/`.focused(_:equals:)`. Trade-off: reconcile with the imperative manager API. |
| **`.keyboardShortcut`** | Bind a key to any action, not just status-bar items. | A modifier registering an action with the key dispatcher for the view's focus scope. |
| **Controls: `Label`, `Link`, `DatePicker`, `Gauge`, `TextEditor`, multi-select `Picker`** | Everyday building blocks. | `Label`/`Gauge`/`TextEditor` are straightforward; `Link` opens via `openURL`; `DatePicker` is bigger. |
| **`Image(systemName:)` → glyph map** *(see §2.4)* | Lets common SF Symbol names render as Unicode. | Curated `String → Character` table; falls back to a placeholder. |
| **List editing: `onDelete`/`onMove`, `EditButton`/`editMode`, `.listRowInsets`/`.listRowBackground`/`.listSectionSeparator`** | Editable lists. | Wire into the existing selection/row model; key-driven move/delete. |
| **Common modifiers: `.id`, `.opacity`(View), `.multilineTextAlignment`, `.truncationMode`(View), `.onSubmit`/`.submitLabel`, `.focusable`, `.searchable`, `.refreshable`, `.contextMenu`, `.onReceive`** | Frequently used; each terminal-expressible. | `.id` (identity reset) and `.searchable` are the highest-value. `.opacity` → dim/blend approximation only. |
| **Scoped wrappers: `@Bindable`, `@SceneStorage`, `@FocusedValue`** | `@Bindable` pairs with `@Observable`; the others are niche. | `@Bindable` is the useful one (binding into an `@Observable`); `@SceneStorage` ≈ `@AppStorage` for a single scene. |
| **Env values: `\.isEnabled`, `\.locale`, `\.layoutDirection`, `\.dynamicTypeSize`, `\.openURL`, `\.scenePhase`** | Standard environment reads. | `\.isEnabled` comes with §3.3; `\.openURL`/`\.locale`/`\.scenePhase` are independently useful; size-class concepts map loosely to terminal dimensions. |
| **Text richness: `Text(_:format:)`, `LocalizedStringKey`, `AttributedString`, Markdown, `Text + Text`** | Formatting & localization. | `Text + Text` concatenation and `Text(_:format:)` are tractable; full `AttributedString`/Markdown is larger. TUIkit has a localization service to build `LocalizedStringKey` on. |

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
| `RadioButton`/`RadioButtonGroup`, `Spinner`, `Menu` (keyboard-driven), `TrackStyle`, `IndeterminateStyle` | terminal-idiomatic controls/styles |
| `.navigationSplitViewResizable`, `.navigationSplitViewColumnWidth`, `.fixedSize` on `List`, `.listEmptyPlaceholder` | terminal split/list affordances |
| `.maxFrameRate` (App) | cap redraw rate |

---

## 5. Recommended changes, prioritized

Only §3 (unintentional) and §4a (addable) warrant change. Suggested order —
quick, high-value ergonomics first; large subsystems last:

| # | Change | Category | Effort | Why first/last |
|---|---|---|---|---|
| 1 | `Binding` dynamic-member lookup + `init(projectedValue:)` (§3.2) | 3 | low | unblocks forms over models; purely additive |
| 2 | `Stepper` generic over value type (§3.1) | 3 | low | correctness — data-model values must allow float |
| 3 | `View.disabled(_:)` + `\.isEnabled` env (§3.3) | 3 / 4a | medium | basic capability; also delivers an env value |
| 4 | `task(id:)` (§3.8), `@State.init(initialValue:)` (§3.7) | 3 | low | small, mechanical |
| 5 | `sheet(onDismiss:)` + `sheet(item:)` (§3.5) | 3 | low-med | standard presentation ergonomics |
| 6 | Data-driven `List(_:id:selection:rowContent:)` (§3.4) | 3 | low-med | the most-missed `List` spelling |
| 7 | `frame` default alignment → `.center` (§3.6) | 3 | medium\* | removes a silent layout divergence (*behavioral — do early) |
| 8 | `@FocusState` property wrapper + `.focused` (§4a) | 4a | medium | source-compatible focus; reconcile with `FocusManager` |
| 9 | `NavigationStack`/`NavigationLink`/`navigationDestination` (§4a) | 4a | high | biggest structural gap |
| 10 | `confirmationDialog`/`popover`, `ScrollViewReader`, `.id`/`.searchable`/`.keyboardShortcut`, controls (`Label`/`Gauge`/`TextEditor`/`Link`) | 4a | mixed | fill out breadth incrementally |
| 11 | `Button(action:label:)` + custom `ToggleStyle`/`PickerStyle` (§3.9) | 3 | med-high | view labels; unlock custom styles |

Everything in §2 and §4b is intentional and should **not** change: the `Int`
measurement model, integer geometry, `@Observable`-only state, and the absence of
fonts/animation/shapes/sub-cell-geometry are the honest consequences of
rendering to a grid of character cells rather than a bitmap.
