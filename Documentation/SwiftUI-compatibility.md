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
3. [**Remaining divergences** — most resolved; the rest deferred or intentional](#3-remaining-divergences)
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
| State | `@State` (`init(wrappedValue:)` + `init(initialValue:)`), `@Binding` (`init(get:set:)`, `.constant`, `init(projectedValue:)`, **dynamic-member lookup**), `@Environment(\.key)` | ✓ | `$model.field` and `initialValue:` now match (was §3.2/§3.7) |
| Observation | `@Observable` + `@Environment(Type.self)` + `.environment(obj)` | ✓ | modern reference-type state ports as-is |
| Env / prefs | `EnvironmentKey`, `EnvironmentValues`, `PreferenceKey`, `.environment(_:_:)`, `.preference`/`.onPreferenceChange` | ✓ | custom keys work the SwiftUI way |
| Stacks | `VStack` / `HStack` / `ZStack` / `LazyVStack` / `LazyHStack` | ✓ | `spacing:` is `Int` → §2.1; default spacing → §2.1 note |
| Iteration | `ForEach` (`id:` keypath, `Identifiable`, `Range<Int>`), `Section` (header/footer/title), `Group` | ✓ | all three `ForEach` forms present |
| Data | `List` — content-closure **and** data-driven `List(_:id:selection:rowContent:)`, `Table` | ✓ | data-driven `List` routes through the windowed `ForEach` path, O(visible) (was §3.4) |
| Scrolling | `ScrollView(_:content:)` | ✓ | the `showsIndicators:` variant mirrors a soft-deprecated SwiftUI init |
| Adaptive | `ViewThatFits(in:content:)` | ✓ | |
| Nav | `NavigationSplitView` (2/3-column, `columnVisibility:`), `navigationTitle` (`StringProtocol` / `Text`) | ✓ | title overloads added (was §3.10) |
| Presentation | `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)`, `alert` | ✓ | `onDismiss:`/`item:` added (was §3.5); presented as a centred, dimming overlay |
| Lifecycle | `onAppear`, `onDisappear`, `task` (incl. `task(id:)`), `onChange(of:initial:_:)` (both current forms), `onHover` | ✓ | `task(id:)` added (was §3.8); matches the *current* `onChange`; deprecated `perform:` correctly absent |
| Controls | `Button` (string **and** `Button(action:label:)`), `Toggle`, `Slider`, `Stepper`, `ProgressView`, `TextField`, `SecureField`, `Picker`, `Divider`, `Spacer`, `EmptyView`, `AnyView`, `ContentUnavailableView` | ✓ | `Slider`/`ProgressView`/`Stepper` are floating-point-capable (generic over the value); custom `ButtonStyle`/`ToggleStyle` via `makeBody` (was §3.1/§3.9) |
| Modifiers | `padding`, `frame`, `overlay(alignment:content:)`, `fixedSize`, `foregroundStyle(.color)`, `disabled` (on any `View`), `tag`, `zIndex`, `badge`, `listStyle`, `lineLimit` (on `Text`) | ✓ | units are `Int` → §2.1; `disabled` cascades via `\.isEnabled`; `frame` default alignment is `.topLeading` → §2.7 |
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
silently shift every such column and surprise TUI authors (their text would
suddenly centre). The default is therefore `.topLeading`; pass an explicit
`alignment:` when you do want centring. (The *flexible* `frame(maxWidth:…,
alignment:)` **does** default to `.center`, matching SwiftUI, because slack-space
distribution is exactly when centring makes sense.)

> Previously listed as an unintentional divergence (old §3.6) to reconcile to
> `.center`. On review the top-left default proved **load-bearing** — e.g.
> `ColorPicker`'s per-channel `Slider.frame(width:)` relies on left alignment, and
> changing the default broke it — and it is the better terminal default, so it is
> reclassified here as intentional.

---

## 3. Remaining divergences

Every item once listed here has been **resolved** — TUIkit now matches SwiftUI
for them (they moved up to §1 Match) — except one borderline item deliberately
kept as-is (3.11). Each fix was verified against the installed SDK
(Swift 6.2.4 · SwiftUI 7.2.5) before landing.

### Resolved (now in §1 Match)

| Was | What shipped |
|---|---|
| **3.1** `Stepper` was `Int`-only | Generic over `V: Strideable` (`value: Binding<V>`, `step: V.Stride`, optional `in:`), with the value type **erased** into closures so `Stepper<Label>` keeps SwiftUI's exact shape. `Int` call sites are unchanged; `Double`/`Float` now work. |
| **3.2** `Binding` had no dynamic-member lookup | Marked `@dynamicMemberLookup` with `subscript(dynamicMember: WritableKeyPath<Value, Subject>)` and added `init(projectedValue:)`. `$model.field` works. |
| **3.3** `disabled()` was per-control | **Already shipped** (the entry was stale): `View.disabled(_:)` plus a cascading `\.isEnabled` environment value that every interactive control already reads. |
| **3.4** `List` had no data-driven init | Added `List(_:rowContent:)` / `List(_:id:selection:rowContent:)` overloads (Identifiable + explicit `id:`, across no-/single-/multi-selection) that build the existing windowed `ForEach` path — initializer sugar only, O(visible) preserved. |
| **3.5** `sheet` lacked `onDismiss:`/`item:` | Added `onDismiss:` to `modal`/`sheet` (fires on the presented→dismissed transition, covering button/key/programmatic dismissal) and `sheet(item:)` for `Identifiable`. |
| **3.6** fixed-`frame` default alignment | **Reclassified** as an intentional terminal deviation → see **§2.7** (top-left is load-bearing and the right TUI default). |
| **3.7** `@State` lacked `init(initialValue:)` | Added the `init(initialValue:)` alias. |
| **3.8** `task` lacked `id:` | Added `task(id:priority:_:)`. The `id`'s textual form folds into the lifecycle token, so a changed `id` makes the old token "disappear" (cancelling its task) while the new one starts — reusing the existing appear/disappear machinery. |
| **3.9** `Button`/style labels were `String`-only | `Button(action:label:)` / `Button(role:action:label:)` added — the label is erased to an optional `AnyView`, so `Button` stays **non-generic** and `ButtonRow`/`Alert`'s `[Button]` arrays keep working (a generic `Button<Label>` would break them); built-in styles render a view label via composition, string labels keep their procedural path (zero churn). `ButtonStyleConfiguration` gains `labelView`; `ToggleStyle` gains `makeBody` + `ToggleStyleConfiguration` (custom toggle styles; built-ins stay procedural). **`PickerStyle` is intentionally left a marker** — SwiftUI's `PickerStyle` has no public `makeBody` (only underscore SPI), so TUIkit already matches it; the original §3.9 note claiming otherwise was inaccurate. |
| **3.10** `navigationTitle` took `String` only | Added `StringProtocol` and `Text` overloads (the `Text`'s styling isn't carried — the title renders as a plain string — but the spelling resolves). |

Regression tests for the above live in
`Tests/TUIkitTests/SwiftUICompatFixesTests.swift`.

### 3.11 `foregroundStyle` takes `Color?`, not `some ShapeStyle`

- **TUIkit:** `foregroundStyle(_ style: Color?)`; **SwiftUI:** `foregroundStyle<S: ShapeStyle>(_:)` (re-verified against the SDK — still `ShapeStyle`).
- **Should it change? No — borderline §2.** `.foregroundStyle(.red)`
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
> `ColorPicker` (with a full modal `ColorPickerPanel`), the `.tint(_:)` modifier,
> and `View.disabled(_:)` + the `\.isEnabled` environment value (the §3.3 fix).

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
| **Env values: `\.locale`, `\.layoutDirection`, `\.dynamicTypeSize`, `\.openURL`, `\.scenePhase`** | Standard environment reads. | `\.isEnabled` already shipped (§3.3); `\.openURL`/`\.locale`/`\.scenePhase` are independently useful; size-class concepts map loosely to terminal dimensions. |
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

## 5. Status

All of §3 is now resolved, except **3.6**, which was reclassified to §2.7
(intentional terminal deviation) rather than changed. The remaining roadmap is
§4a (additive features).

| # | Change | Status |
|---|---|---|
| 1 | `Binding` dynamic-member lookup + `init(projectedValue:)` (§3.2) | ✅ done |
| 2 | `Stepper` generic over value type (§3.1) | ✅ done |
| 3 | `View.disabled(_:)` + `\.isEnabled` env (§3.3) | ✅ already shipped |
| 4 | `task(id:)` (§3.8), `@State.init(initialValue:)` (§3.7) | ✅ done |
| 5 | `sheet(onDismiss:)` + `sheet(item:)` (§3.5) | ✅ done |
| 6 | Data-driven `List(_:id:selection:rowContent:)` (§3.4) | ✅ done |
| 7 | `frame` default alignment (§3.6) | ↪︎ reclassified intentional (§2.7) |
| 8 | `navigationTitle` overloads (§3.10) | ✅ done |
| 9 | `Button(action:label:)` + custom `ToggleStyle` (§3.9) | ✅ done (`PickerStyle` left a marker — already matches SwiftUI) |
| — | `@FocusState`, `NavigationStack`, `confirmationDialog`/`popover`, `ScrollViewReader`, `.searchable`/`.keyboardShortcut`, `Label`/`Gauge`/`TextEditor`/`Link`, … | §4a roadmap |

Everything in §2 and §4b is intentional and should **not** change: the `Int`
measurement model, integer geometry, top-left fixed-`frame` alignment,
`@Observable`-only state, and the absence of fonts/animation/shapes/sub-cell-
geometry are the honest consequences of rendering to a grid of character cells
rather than a bitmap.
