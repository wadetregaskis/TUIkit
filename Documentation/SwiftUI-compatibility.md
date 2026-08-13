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
| Iteration | `ForEach` (`id:` keypath, `Identifiable`, `Range<Int>`, and over a `Binding` to a collection — `ForEach($items) { $item in … }`, with and without `id:`), `Section` (header/footer/title), `Group` | ✓ | all five `ForEach` forms present. The binding forms hand each row a `Binding<Element>`, which is what a row of editable controls needs — a `Toggle` binds to `$item.enabled` rather than to an index-keyed lookup. Note that `$dictionary[key]` is a `Binding<Value?>` and `$dictionary[key, default: x]` does not compile at all (the `default:` autoclosure cannot form a key path) — both are equally true of SwiftUI. TUIkit adds `Binding.defaulted(to:)` for that case (§4c); SwiftUI's answer is an explicit `Binding(get:set:)` |
| Data | `List` — content-closure **and** data-driven `List(_:id:selection:rowContent:)`, `Table` | ✓ | data-driven `List` routes through the windowed `ForEach` path (O(visible)) |
| Scrolling | `ScrollView(_:content:)`, `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)`, `defaultScrollAnchor(_:)` | ✓ | the `showsIndicators:` variant mirrors a soft-deprecated SwiftUI init; `scrollTo` targets `ForEach` row identities (no `.id(_:)` tagging yet) and vertical-only scroll views, resolving in O(window) even at millions of rows |
| Adaptive | `ViewThatFits(in:content:)` | ✓ | |
| Layout | `GeometryReader` / `GeometryProxy` / `CoordinateSpace`, `AlignmentID` / `ViewDimensions` / `HorizontalAlignment(_:)` / `VerticalAlignment(_:)`, `.alignmentGuide(_:computeValue:)` | ✓ | sizes are whole cells → §2.2 (`CellSize`/`CellRect`, no `CGSize`); `GeometryProxy` omits `safeAreaInsets` and the `Anchor` subscript (§4b), and `frame(in: .global)` falls back to the local frame where the renderer does not know the on-screen position — `hasGlobalPosition` says which. Guide *values* are `Double` even though sizes are `Int`, because a guide is only ever subtracted from another guide and then floored; see `AlignmentID`. Read `.alignmentGuide` as the **outermost** modifier on a child, as with `.zIndex` |
| Grid | `Grid(alignment:horizontalSpacing:verticalSpacing:)`, `GridRow(alignment:)`, `.gridCellColumns(_:)`, `.gridCellAnchor(_:)`, `.gridColumnAlignment(_:)` | ✓ | spacings are `Int` cells and default to **1 column / 0 rows** rather than SwiftUI's platform metrics — a zero column gap would run adjacent text together, while rows are already separated by being different lines. A non-`GridRow` child spans every column (which is how a `Divider` between rows works). **Omitted**: `.gridCellUnsizedAxes(_:)` — it exists in SwiftUI so a `Divider` does not force its ideal length onto a column, and the full-width spanning above already covers that case |
| Custom layout | `Layout` (+ `Cache`, `makeCache`/`updateCache`, `sizeThatFits`, `placeSubviews`, `callAsFunction`), `LayoutSubviews` / `LayoutSubview`, `LayoutValueKey` + `.layoutValue(key:value:)`, `.layoutPriority(_:)`, `AnyLayout` | ✓ | integer geometry throughout → §2.2: `placeSubviews(in: CellRect …)`, `sizeThatFits` answers `ViewSize`. `LayoutSubview.sizeThatFits` returns `ViewSize` (a superset of `CGSize` — it carries the flexibility SwiftUI makes you infer by probing with `.infinity`, which `ProposedSize` therefore has no need to encode). The cache lives one pass, not across them (`updateCache` still runs, so conformances behave identically). **Omitted**, each for a stated reason on `Layout`: `ViewSpacing`/`spacing(subviews:cache:)`, `LayoutProperties`, `explicitAlignment(of:in:…)`, `Animatable`. **Added**: `LayoutSubview.place(in:anchor:proposal:)` — the region form, which resolves the anchor in a single flooring step (see §2.2) |
| Nav | `NavigationStack` (+ `NavigationLink`, `navigationDestination(for:)`, `NavigationPath`), `NavigationSplitView` (2/3-column, `columnVisibility:`), `navigationTitle` (`StringProtocol` / `Text`) | ✓ | a `Text` title renders as a plain string (its styling isn't carried). `NavigationStack` draws a **two-row** bar (the path, then a rule) whose height never varies — chrome that grows with its content cannot be laid out in one pass. The path is a **breadcrumb trail** (`Planets  ›  Mars  ›  Deimos`) where every crumb but the last is a `Button` — a Tab stop, and a click pops straight to that depth. It degrades with the terminal: the full trail, then the middle elided (`Planets  ›  …  ›  Deimos`), then **‹ Back** + the truncated title when even that will not fit. TUI-specific: SwiftUI has no breadcrumb, but a terminal has no swipe-back gesture either, and one Back button at depth 4 is four presses and no idea where you are. Back is also **Escape** or `\.dismiss` (which pops inside a stack instead of quitting). The root keeps rendering while a screen is pushed — isolated from focus and key events like a modal's backdrop, and off-screen — which is what keeps its `@State` alive to come back to and its `navigationDestination` closures current. `NavigationPath` has no `CodableRepresentation` (§4b-adjacent: it needs a runtime type-name lookup TUIkit does not have everywhere). `NavigationLink(destination:)` pushes a token keyed on the link's identity, so it needs a path that can hold one — the default stack or a `NavigationPath`; a *typed* path binding can only carry its own element type, so use `NavigationLink(value:)` with those |
| Containers | `TabView` / `Tab`, `Form`, `LabeledContent`, `Label` (incl. `Label(_:systemImage:)`), `DisclosureGroup`, `OutlineGroup` | ✓ | `Label(_:systemImage:)` renders an SF Symbol glyph on Apple terminals → §2.4; `formStyle(.columns)` (default) / `.grouped`. `DisclosureGroup` has all four SwiftUI initializers (custom label / `Text` title, each with and without an `isExpanded:` binding) and draws `▶`/`▼` before the label, with the content indented to start in the label's own column so nesting draws a tree. The header is one control — Tab stop, Return/Space, or a click anywhere on the row — because a terminal has no separate triangle to hit. `content` is `@escaping () -> Content` as it is in SwiftUI, and a collapsed group never calls it, so a closed section costs nothing per frame. **Omitted: `DisclosureGroupStyle`** — a terminal disclosure is a triangle and an indent, so there is no second geometry for a style to express. `OutlineGroup` has all four initializers (a root element or a collection, each with `Identifiable` ids or an explicit `id:` key path). Its branch rows disclose from the **triangle** rather than from the whole row — an outline row's text has to stay free for whatever contains the outline to claim, which is what will let a list select the node whose triangle just opened it; the keyboard follows the same division: standing alone each branch's triangle is a Tab stop that Return or Space toggles, while inside a `List` the ROW is the focusable — Space selects it, Return activates it (disclosing a branch, unless the app claims Return with `.onRowActivate`), and Right / Left open and close it either way — and ⌥Right / ⌥Left do the same to the whole subtree at once, the Finder's gesture (a recursive collapse folds the descendants too, so re-opening shows the branch as it was left). A second focus stop per branch would have taken the row's Space with it. One cell is a poor mouse target, so the triangle's button covers the blank cell either side of it as well. It emits one row per **visible** node to whatever contains it, exactly as `ForEach` emits one per element: the depth is each row's leading padding, not a nest of views, so a closed branch's descendants are neither built nor measured and a deep tree is not a deep view hierarchy. (Like `ForEach`, it therefore has no `body` of its own — it is a run of views, not one.) `List(_:children:)` and `List(_:children:selection:)` follow from that in six initializers, so a list's cursor, selection binding and scrolling address **nodes**. SwiftUI's `Parent` and `Subgroup` generic parameters are dropped along with the `OutlineSubgroupChildren` marker they exist to name — `Parent` is always `Leaf` and `Subgroup` has exactly one possible value, so all three are phantom (the same call `Gauge` makes about its fourth parameter); the initializers are SwiftUI's exactly. The `Binding`-of-collection initializers are absent |
| Presentation | `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)`, `alert`, `confirmationDialog(_:isPresented:titleVisibility:actions:message:)` | ✓ | presented as a centred, dimming overlay. An `alert`/`confirmationDialog` dismisses when any of its actions is chosen (SwiftUI's behaviour — the action closure does not flip the binding itself), and claims Escape on the status bar while it is up, so a page's own `⎋ back` cannot navigate out from under it. Escape *is* the `.cancel`-role button (macOS gives Cancel the Escape key equivalent): it runs that action if there is one — a disabled one is skipped — and closes the dialog either way. A `sheet`/`modal` deliberately does NOT auto-dismiss: its content owns its own close button. |
| Lifecycle | `onAppear`, `onDisappear`, `task` (incl. `task(id:)`), `onChange(of:initial:_:)` (both current forms), `onHover` | ✓ | matches the *current* `onChange`; deprecated `perform:` correctly absent |
| Controls | `Button` (string **and** `Button(action:label:)`), `Toggle`, `Slider`, `Stepper`, `ProgressView`, `Gauge`, `TextField`, `SecureField`, `TextEditor`, `Picker`, `DatePicker`, `Link`, `ColorPicker`, `Divider`, `Spacer`, `EmptyView`, `AnyView`, `ContentUnavailableView` | ✓ | `Slider`/`ProgressView`/`Stepper`/`Gauge` are floating-point-capable; `Gauge` takes `.gaugeStyle(_:)` with terminal-native `.linearCapacity`/`.accessoryLinear`/`.accessoryLinearCapacity`/`.accessoryCircular`/`.accessoryCircularCapacity`/`.accessoryCircularTiny` (a closed set — a terminal can't host user-defined gauge geometries; the `Capacity` styles fill min→value cumulatively, the others mark only the value's position; circular styles draw a ring dial, `…Tiny` a single pie glyph); custom `ButtonStyle`/`ToggleStyle` via `makeBody`; `PickerStyle` is a marker protocol, matching SwiftUI; `Link` opens via `@Environment(\.openURL)` (no OSC 8 — §2.4-style deviation); `TextEditor` scrolls to follow the cursor (no soft-wrap yet); `DatePicker` is an inline numeric field (no calendar popup, fixed numeric format; Left/Right pick a component, Up/Down adjust it by one, Page Up/Down by a coarse step — a decade, a quarter, a week — and Home/End send it to the ends of its own range; the wheel steps whichever field it is pointing at — the one thing the keyboard cannot do without first walking to that field — in the framework's usual direction, wheel-up towards earlier); multi-selection is `List(selection: Binding<Set<…>>)` (SwiftUI has no multi-select `Picker`) |
| Modifiers | `padding`, `frame`, `overlay(alignment:content:)`, `fixedSize`, `foregroundStyle(.color)`, `disabled` (on any `View`), `tint`, `tag`, `zIndex`, `badge`, `listStyle`, `formStyle`, `lineLimit` (on `Text` **and** on any `View`), `truncationMode`, `multilineTextAlignment`, `opacity` | ✓ | units are `Int` → §2.1; `lineLimit`/`truncationMode` on a `View` cascade to every `Text` below, and one written on a `Text` wins there — `.lineLimit(nil)` means *unlimited*, so it is also how a branch opts out of an inherited cap; `disabled` cascades via `\.isEnabled`; `tint` overrides the accent role (§2.5); `frame` default alignment is `.topLeading` → §2.7; `multilineTextAlignment` aligns a wrapped `Text`'s lines within its own block width (single-line text unaffected); **`opacity` is a colour blend, not compositing** — a cell has no alpha channel, so the subtree's colours are moved toward the palette background by `1 - opacity`, which preserves hue (a red heading at `0.5` still reads red) and reaches the background exactly at `0`, leaving the view invisible but still occupying its space and still hit-testable, as in SwiftUI. It blends toward the palette background rather than toward whatever is behind the view, a terminal having no layer below the cell; the two agree except over a non-background fill. It works by rewriting the colours each rendered run names — every run names its own and ends reset, a renderer property `OpacityTests` pins — so no colour is injected and nothing bleeds into a sibling |
| App | `App`, `Scene`, `WindowGroup`, `SceneBuilder`, `@main`, `@AppStorage`, `@Environment(\.dismiss)` | ✓ | `@AppStorage` is *enhanced* (pluggable backend) |
| Text | `Text(_:)` (`LocalizedStringKey` **and** `StringProtocol`), `Text(verbatim:)`, `Text(_:format:)`, `Text + Text` | ✓ | a literal is a localization key, a computed `String` is not — SwiftUI's rule, and §4a records what it took to reproduce |
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

The same rule shapes the layout read-back API: `GeometryProxy.size` is a
`CellSize` of `Int` cells and `frame(in:)` returns a `CellRect`, not `CGSize`
and `CGRect`. A custom `Layout` sees the same pair — `placeSubviews(in:)` takes
a `CellRect`. Two consequences a layout author should know, both of which
floating point used to hide:

- **Divide last.** `let each = total / count` then `i * each` silently drops up
  to `count - 1` cells (2 of them for an ordinary 80-wide, 3-column split);
  `i * total / count` drops none and stays within one cell of even.
- **`CellRect` has no `midX` / `midY`.** A midpoint is fractional whenever the
  extent is odd, so flooring it to a cell *before* subtracting the subview's
  half-size floors twice — and that moves a centred placement by a cell in
  **210 of 861** (extent, size) combinations. `place(in:anchor:proposal:)` does
  the whole thing in one step instead.

The one deliberate exception is an **alignment guide's value**, which is
`Double`. A guide is not a size — it is a reference line *inside* a view, and it
only ever appears subtracted from another guide before being floored to a cell.
That distinction is load-bearing rather than pedantic: centring a 3-cell view in
10 cells has always placed it at `(10 - 3) / 2 == 3`, whereas whole-cell guides
would compute `10/2 - 3/2 == 4`, because flooring does not distribute over
subtraction. **190 of 820** width combinations would have shifted by a cell.
Fractional guides reproduce today's arithmetic in all 820. The fraction exists
only between two guides and never survives to a coordinate.

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

**`.onReceive(_:perform:)` follows from this, and from where TUIkit runs.**
Its signature is `onReceive<P: Publisher>(_ publisher: P, perform:)` — the
parameter type IS a Combine protocol, so there is no version of that function
to write on a platform without Combine, and TUIkit's CI builds and tests on
Linux with Windows a port in progress. The three ways to ship it anyway are all
worse than not:

- `#if canImport(Combine)` would make it exist on Apple platforms only. That is
  worse than absent, not better: source that compiles on a Mac would fail on
  Linux, which is the exact portability trap a cross-platform package exists to
  prevent. (The `#if canImport` rule of thumb is for *choosing an
  implementation* of something that works everywhere — `NSImage` vs `stb_image`
  — not for making public API appear and disappear.)
- An `AsyncSequence` overload under the same name would be a different API
  wearing SwiftUI's, which the parity rule forbids. The deviations TUIkit does
  take are ones a *terminal* forces; Combine's absence is not one of them.
- Reimplementing Combine is not a terminal UI kit's job.

What replaces it is already here, cross-platform, and is what modern SwiftUI
would use anyway — `task(id:)` with `for await`:

```swift
// SwiftUI, Combine                     // TUIkit (and modern SwiftUI)
.onReceive(model.events) { e in         .task {
    handle(e)                               for await e in model.events { handle(e) }
}                                       }

.onReceive(timer) { _ in tick() }       .task {
                                            while !Task.isCancelled {
                                                try? await Task.sleep(for: .seconds(1))
                                                tick()
                                            }
                                        }
```

The `.task` is cancelled when the view disappears, which is the lifetime
`onReceive`'s subscription had — so the thing being replaced is the spelling,
not the behaviour. For "a value changed", `onChange(of:initial:_:)` already
covers it (§1).

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


**Why `pinnedViews:` is not just an init parameter.** A pinned section header
has to keep drawing at the viewport top while its section scrolls under it, so
the stack must know three things it currently cannot see:

1. **Where the sections are.** `Section` renders through a *private*
   `_SectionCore` that composes header + content + footer into one buffer, so
   an enclosing stack sees one child of some height and cannot say which rows
   are header. Pinning needs a channel out of that core carrying the header's
   own buffer and height.
2. **Which section owns the viewport top.** That is a function of the scroll
   offset and the section ranges, and the offset lives in the `ScrollView` —
   the lazy stack windows against a slice the scroll machinery hands it
   (`ScrollContentWindow`), it does not own the offset.
3. **Where to composite.** The header has to be drawn over the slice's first
   row *after* windowing, without changing the slice's height — the same
   overlay-don't-inset rule `.refreshable`'s spinner follows, and for the same
   reason: anything that changes height while scrolling reflows the content
   under the cursor.

So it touches `Section`, the windowing path in `VStack`, and `ScrollView` /
`ScrollContentWindow` together. That is the scroll subsystem, which is under a
standing no-speculative-changes rule here, so it wants a session of its own with
a PTY sweep rather than a corner of one — not because the feature is large, but
because the places it reaches are load-bearing for everything else that scrolls.

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
| **Presentation: `popover`, `fullScreenCover`, `presentationDetents`** | Common modal patterns. | **All shipped.** `popover(isPresented:attachmentAnchor:arrowEdge:content:)` is an ANCHORED presentation, not another centred sheet: a bordered panel beside the view that presented it, over an undimmed page, closed by Escape or a click outside — the same presentation `.contextMenu` and the `Picker` drop-down use, with your content instead of menu rows. `arrowEdge` picks the side (a terminal draws no arrow); `attachmentAnchor` takes `.rect(.bounds)` (centred on the view) or `.point(_:)`, SwiftUI's `Anchor<CGRect>.Source` being §4b geometry. `fullScreenCover(isPresented:onDismiss:content:)` fills the content area, dims nothing (there is nothing showing through) and cannot be dragged. `presentationDetents(_:)` / `(_:selection:)` size a sheet: `.medium`, `.large`, `.fraction(_:)`, and `.height(_:)` in **Int rows** (a terminal has no `CGFloat`); the fraction is floored, once. Read off the sheet content's **outermost** view — the same rule as `.alignmentGuide`, and for a harder reason: the detent IS the height being rendered into, so it has to be known before the subtree renders, which rules a preference out. **A terminal has no grabber to drag**, so a multi-detent sheet moves between its detents through the `selection:` binding; without one the smallest applies, which is SwiftUI's own initial state. That makes the detent SET inert for anything past the first — every extra detent is unreachable unless the app builds its own control — so this is currently a parity shim rather than a feature. `Documentation/Drawers-sheets-and-slideovers.md` drafts the way out (a grabber that snaps to detents, and a resizable drawer built on the split-view machinery) and is awaiting decisions. `confirmationDialog` **shipped** — an action sheet (centred dimming overlay, ESC-dismiss, `titleVisibility`) with **vertically-stacked** buttons and the `.cancel` role sorted last; it reuses the alert host via a `verticalButtons` flag + a new `AlertButtonColumn`. `popover`/`fullScreenCover` ≈ `modal` variants; detents → fractional-height modal. |
| **`.scrollPosition` (bindable scroll state)** | Observable/bindable scroll position. | **Shipped**, both directions. `ScrollPosition` + `.scrollPosition(_:anchor:)` and `.scrollPosition(id:anchor:)`; `scrollTo(id:anchor:)` / `(edge:)` / `(y:)`, `viewID(type:)`, `edge`, `isPositionedByUser`. Writing rides the same seek machinery `ScrollViewProxy.scrollTo` drives, so a row request lands the frame it is made; an edge or offset moves the view before the content renders (`.bottom` via the tail-seek flag the End key raises, so the glue pins it against the real height). **Reading needed a new channel**: a seek matches on a stringified key, which is one-way — so `ForEach` now publishes the id VALUE alongside the key (`ChildViewCollection.anyID(at:)`), and the windowed stacks report the row under the anchor. The sample is the first row a person can actually SEE, not the one the "N more above" indicator is covering. A request is acted on once (a token, or the value differing from what was last reported), so scrolling away by hand sticks; the write-back only fires when the row changed, or a render-time write would re-trigger itself every frame. `ScrollPosition` is not `Sendable` (an `AnyHashable` is whatever the app's id type is) and has no `CGPoint` form — `scrollTo(y:)` takes `Int` rows, and there is no horizontal seek (the machinery rides the vertical row-windowing handshake). Remaining: `.id(_:)`-tagged arbitrary (non-`ForEach`) targets. |
| **Viewport windowing for a nested `LazyVStack` + `pinnedViews:`** | A `LazyVStack` that is the *direct* content of a `ScrollView` now windows to the viewport (§2.8) — the offset-publishing + render-only-visible policy landed. Remaining: a `LazyVStack` nested *below* other scroll content isn't at the content origin so it can't map the offset yet, and `pinnedViews:` is still absent from the lazy inits. | Thread the stack's own y-offset within the scroll content so a non-top stack can window too; `pinnedViews` then composites the active `Section` header over the viewport top. |
| **`@FocusState` as a property wrapper** | *(shipped)* `@FocusState var x: Bool` / `var f: Field?` + `.focused($x)` / `.focused($f, equals:)` + `.defaultFocus($f, value)`, matching SwiftUI. The value is derived from the persistent `FocusManager`; the imperative handle formerly called `FocusState` is now `FocusReference`. Remaining: `@FocusState` on multiple focusables in one `.focused` (SwiftUI binds a single control), and re-applying a default when a dismissed focus scope re-appears. |
| **`.keyboardShortcut` (general key equivalents)** | Bind an arbitrary key to any action. | The SEMANTIC actions shipped: `.keyboardShortcut(.defaultAction)` makes a Button the default (Return/Enter fires it whenever the focused control lets the key fall through — a `TextEditor` keeps its newline, a list keeps its row activation, a submit-less `TextField` lets Return through) and `.cancelAction` binds Escape. Arbitrary equivalents **shipped** too: `.keyboardShortcut("s", modifiers:)` with `KeyEquivalent` and `EventModifiers`. A terminal reports Control, Option and Shift but never ⌘, so the SwiftUI default `modifiers: .command` is remapped at registration to whatever the TUI-specific `.commandKey(_:)` names — `.control` (default), `.option`, `.bare`, or `.unavailable` — which is what lets one `View` source carry ⌘-shortcuts under both frameworks. Shift on a printable key is the character's CASE, not a modifier bit (that is all a terminal sends), and Control shortcuts on `c i j m z [` are undeliverable because the C0 range spends those bytes on Tab/Return/Escape and job control — see `KeyboardShortcut.isDeliverableInTerminal`. |
| **List editing: `onDelete`/`onMove`, `.listRowInsets`/`.listRowBackground`/`.listSectionSeparator`** | Editable lists. | `EditMode` + `\.editMode` + `EditButton` **shipped**, and `ForEach.onMove(perform:)` / `onDelete(perform:)` now **shipped**: attach the actions to a `ForEach` inside a `List` and press **Delete**/**Backspace** on the focused row to delete it, or drag a row with the mouse to reorder it (mirroring SwiftUI's drag trigger; `.rowReorderFeedback(_:)` chooses live-shuffle / dimmed-at-the-slot / row-on-the-pointer feedback). `move(fromOffsets:toOffset:)` / `remove(atOffsets:)` collection helpers ship alongside (constrained `Self.Index == Int` so they beat the Foundation⇄SwiftUI cross-import overlay's own unlinkable copies). Wired for a homogeneous all-content `List { ForEach … }` (a Section-nested ForEach is the known follow-up). **`.listRowInsets(_:)` and `.listRowBackground(_:)` shipped.** Insets are padding around the row's content (`nil` = the list's default, i.e. the identity — NOT zero), and the rest of the list still sees a full-width row. A background fills the **row**, not the text: the full width offered, every line of a multi-line row, with the content composited over it and the content's hit regions kept, so a button in a backed row is still clickable. There are two overloads because **TUIkit's `Color` is a value, not a `View`** (a palette is a table of them; cells are painted with them, not composed of them) — the generic `<V: View>` one SwiftUI has, plus a `Color?` one so `listRowBackground(Color.red)` compiles and means the same thing, exactly as `background(_:)` already does. A selected row still draws the selection highlight over the background, as in SwiftUI. `.listRowSeparator` / `.listSectionSeparator` remain inert stubs: the terminal `List` draws no per-row rules to show or hide. |
| **Common modifiers: `.opacity`(View), `.truncationMode`(View), `.onSubmit`/`.submitLabel`, `.refreshable`, `.contextMenu`** | Frequently used; each terminal-expressible. | `.id(_:)`, `.focusable(_:interactions:)`, `.searchable(text:placement:prompt:)`, `.onSubmit(of:_:)`/`.submitLabel(_:)`, and `.contextMenu(menuItems:)` **shipped** — `.contextMenu` is a right-click (or Ctrl-click, where a terminal swallows right-click) pop-up of `Button`s anchored at the click point, dismissed by selection, Escape, or an outside click; a right-click bubbles to an ancestor menu when a child doesn't handle it (the input dispatcher was extended to bubble the secondary button like the wheel), and reliable right-click needs Apple Terminal / Ghostty / Warp (iTerm2 claims it by default — see Terminal-compatibility.md); the TUI-specific `.onMenuOpen(_:)` reports a pop-up (a `contextMenu` or a `Menu`) OPENING to any view above it, which is how an app clears whatever the last choice left on screen so choosing the same item twice reads as two choices — SwiftUI has no equivalent, its menus being system-drawn. — `.id` splices a keyed identity step (resets `@State`, re-fires `onAppear`/`task`, drops the cached buffer); `.focusable` makes any view a Tab stop + click-to-focus (`.activate`) and lets `.focused($x)` bind to a plain view; `.searchable` composes a glyph + bound `TextField` above the content (filtering is app-driven; `placement` is inert in a terminal, but the TUI-specific `.searchFieldIconPlacement(.leading/.trailing)` moves the magnifier and swaps it 🔎↔🔍 so its lens faces the field); `.onSubmit(of:)` cascades a submit action through the environment (`.text` for `TextField`/`SecureField`, `.search` for the `.searchable` field) and composes additively with a field's own `.onSubmit(_:)` closure — the combined action stays nil when empty so Return still falls through to a default button, and `TextEditor` doesn't submit (Return = newline); `.submitLabel` is stored for parity (no on-screen Return key). **`.truncationMode(_:)` on `View` shipped** — the cascading one; `Text` and `TableColumn` had their own all along, and a `Text`'s own still wins inside a subtree that cascaded a different mode (`TextStyle.truncationMode` became Optional so "this view was told" and "nobody said" stay distinguishable). It applies wherever text is clipped, not only under a line limit. **`.lineLimit(_:)` on `View` shipped** — the cascading one, alongside `Text`'s own. It needed a decision `.truncationMode` did not: SwiftUI's `.lineLimit(nil)` means *unlimited*, which a plain `Int?` cannot distinguish from *unset*, and getting that wrong makes an inherited limit unresettable. So what is stored is a `LineLimit` (`.unlimited` / `.lines(_:)`) and the `Optional` around it carries "was one stated" — the modifiers still take `Int?`, matching SwiftUI. Both passes resolve it the same way, so a cascaded limit caps the measured height as well as the rendered one. SwiftUI's range forms (`lineLimit(_:reservesSpace:)` and the `PartialRangeFrom` / `PartialRangeThrough` / `ClosedRange` overloads) are omitted: they exist to make a growing `TextField`/`TextEditor` reserve space between a minimum and a maximum, and a terminal text control is laid into the rows its frame gives it. A `Table` column keeps its own `lineLimit` — its cells are values, not views, so nothing cascades into them. **`.opacity(_:)` on `View` shipped** — see §1. **`.refreshable(action:)` shipped**, with `RefreshAction` and `\.refresh`. SwiftUI triggers it by pulling the content past its top edge; a terminal reports discrete wheel clicks rather than a continuous rubber-banded drag, so "how far past the top" is not a quantity that exists and the trigger is <kbd>Ctrl</kbd>-<kbd>R</kbd> instead — Control being the only modifier a terminal reports on a letter. A second <kbd>Ctrl</kbd>-<kbd>R</kbd> during a refresh is consumed rather than queued, as SwiftUI likewise will not start one over another. While it runs, an unlabelled ``Spinner`` **overlays** the content's top row rather than insetting it: `.overlay` sizes to the larger of the two, so a labelled spinner would widen narrow content the instant a refresh began — the reflow the overlay exists to avoid. It is drawn with one blank cell either side, so it reads as a badge sitting on the content rather than as a glyph that has collided with the word beside it. WHICH spinner is a subtree setting, through the TUI-specific `.refreshIndicator(style:color:)` — SwiftUI's indicator is not configurable, but there its look is a platform given, whereas here a spinner is a handful of glyphs whose legibility depends on the terminal's font: the `.dots` default is Braille, and a font without that coverage wants `.line`, which is pure ASCII. The action is published to the subtree as `\.refresh`, so a "Reload" button anywhere inside runs the same refresh, and `nil` is how a view tells it is not inside anything refreshable. `RefreshAction` is `Equatable` by the action's reference identity — closures cannot be compared, but two handles to the same `.refreshable` are the same thing, which is what makes `onChange(of:)` on it mean anything. (`.multilineTextAlignment` shipped — §1.) |
| **Scoped wrappers: `@SceneStorage`, `@FocusedValue`** | binding into scoped state. | `@Bindable` **shipped** (derives a `Binding` into an `@Observable` reference you already own; not a source of truth, so it holds no storage and takes no part in render-identity binding). **`@SceneStorage` shipped.** SwiftUI draws the line by scope — one value per app vs one per window — which is real with several scenes and meaningless with one, and a terminal app has exactly one. So the two differ here in the single respect that survives that: the **namespace**. Scene state is written under a `scene.` prefix, so `@SceneStorage("tab")` and `@AppStorage("tab")` are different values rather than the same one under two names, and choosing between them stays a statement of intent — "where the user was" vs "what the user chose". SwiftUI does not promise scene storage survives a relaunch (the system may discard restoration state); TUIkit's does, because it shares `@AppStorage`'s backend — relying on that is still unwise, for SwiftUI's own reason. `@FocusedValue` is niche. |
| **Env values: `\.layoutDirection`, `\.dynamicTypeSize`, `\.scenePhase`** | Standard environment reads. | `\.openURL` (via `Link`) and `\.locale` **shipped** — `\.locale` is a stored, settable key populated each frame from the app language (single source of truth), so overriding it with `.environment(\.locale, _)` re-locales the number chrome in `Table`/`List`/`ScrollView`. **`\.scenePhase` shipped**, published each frame from the run loop's own state (the `\.locale` treatment: one source of truth, not a value each view guesses). One transition is real in a terminal and it is the one worth having: **suspend**. <kbd>Ctrl</kbd>-<kbd>Z</kbd> / `SIGTSTP` renders a frame at `.background` BEFORE stopping — so an `onChange(of: scenePhase)` observer runs while the process is still alive, which is an app's only chance to save on the way down — and `.active` again on resume. **`.inactive` is never reported**: detecting "visible but not focused" needs the terminal's focus-reporting mode (`CSI ?1004h`), which TUIkit does not enable, and a value that could only be guessed at is worse than one that never appears. The case exists so a `switch` written against SwiftUI compiles. Size-class concepts map loosely to terminal dimensions. (`\.isEnabled` present — §1.) |
| **Text richness: `LocalizedStringKey`, `AttributedString`, Markdown, `Text + Text`** | Formatting & localization. | `Text(_:format:)` **shipped** (formats eagerly with the format style's own locale — env-`\.locale` re-resolution is a separate, tracked item below). **`LocalizedStringKey` shipped**, with SwiftUI's rule intact: a string *literal* is a lookup key, a `String` you computed is content, and `Text(verbatim:)` opts out. That split is not magic — it is overload resolution, and it needs `@_disfavoredOverload` on the `StringProtocol` initializer to work, because `String` is a string literal's default type and would otherwise always win. (SwiftUI marks its own the same way; without it a literal is simply never looked up, which is what the first draft here did.) Lookup goes through `LocalizationService`, which falls back to English and then to the key itself, so adopting this changed nothing measurable: all 1170 registered keys are dot-separated, none of the 210 `Text("…")` literals in the shipped sources collides with one, and the three Stress scenarios render byte-identical checksums before and after at no measurable cost. An interpolated literal becomes one key with `%@` per value (`"Moved \(n) rows"` → `"Moved %@ rows"`), which a translation can reorder with `%2$@`; values are stringified **eagerly**, as `Text(_:format:)` formats eagerly, and `\(value, format: .percent)` works. A key with no interpolations is never scanned for placeholders, so `Text("100% done")` says exactly that. SwiftUI's `tableName:bundle:comment:` are absent — TUIkit's localization is a registered dictionary with no bundles or tables to name. **`Text + Text` shipped.** A concatenation is ONE `Text`, so it wraps, truncates, aligns and measures as a single piece of text — the fragments are styling, not layout, which is exactly what distinguishes it from an `HStack` of Texts. Each fragment keeps its own attributes and a modifier applied to the result becomes the base beneath them (`(Text("a").bold() + Text("b")).italic()` → both italic, only "a" bold), matching SwiftUI's precedence. A `Text` that was never concatenated stores `nil` rather than a one-element list and takes the original render path untouched: the three Stress scenarios render byte-identical checksums and sit inside run-to-run noise. **The interesting part is that the styling has to be re-applied AFTER the wrap** — wrapping must see the whole plain string or a break either side of a fragment boundary is chosen blind — so the render walks a cursor back through the source to re-attribute each wrapped line. That is only sound because the wrap preserves every non-whitespace character in order (it picks break points and drops whitespace at them; it never reorders, substitutes or invents), which is now a property test over ~5000 random strings × 7 widths rather than an assumption. Inserted chrome — a truncation ellipsis — is kept with the fragment being cut. Full `AttributedString`/Markdown is larger and remains out. |

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
| **Click a column header to sort** a `Table` | a `sortOrder` binding of `KeyPathComparator`s; header click toggles asc/desc | **shipped.** `Table(_:selection:sortOrder:columns:)` takes SwiftUI's own `Binding<[KeyPathComparator<Value>]>` (Foundation's comparator, not SwiftUI's — the same modern-Foundation generation `Text(_:format:)` already depends on), and its presence is what makes the headers clickable at all, as it is in SwiftUI. A column is sortable when it came from a KEY PATH: `TableColumn("Name", value: \.name)` sorts by what it shows, and `TableColumn("Size", value: \.byteCount) { "\($0.byteCount) B" }` — the counterpart of SwiftUI's `TableColumn(_:value:content:)`, with a string in place of the view builder, because a `Table`'s cells are values here — sorts by one property and displays another. A closure column cannot sort: nothing in it says how to order the rows, which is SwiftUI's rule too. Clicking the sorted column reverses it; clicking another promotes that one to primary ascending and keeps the displaced comparator behind it as the tie-break, so a two-key sort is reachable by clicking two headers in turn. The table **publishes** the order and the app applies it (`.onChange(of: sortOrder) { data.sort(using: $0) }`) — SwiftUI's division of labour, not a shortcut. Every sortable column reserves the `▲`/`▼` slot rather than only the sorted one: a glyph that appeared and disappeared would re-measure `.fit` columns on each click, so the table would change width as you sorted it. When a column ends up too narrow for both, the TITLE gives way and the indicator stays — `Tra… ▼`, not `Track…` — because the arrow is the part a reader cannot reconstruct, and a cramped table is exactly when it matters which column the rows are ordered by. **Mouse only so far** — SwiftUI has no keyboard route either, but a terminal wants one; a chord in the spirit of the row-move shortcuts is the obvious follow-up and is not shipped. |
| **Swipe actions** on a `List` row | `.swipeActions { … }` reveals buttons | no swipe in a terminal — surface as a per-row action menu (key, or drag the row aside) |
| **Clear button** in a `TextField` | some field styles show an "✕" while editing a non-empty field | optional trailing clear affordance on a focused, non-empty field |
| **Auto-scroll to keep selection/focus visible** | the list scrolls so the active row stays on-screen | *largely shipped* (selection-reveal + follow-margin) — audit remaining edge cases |
| **Expand/collapse hierarchy** (`DisclosureGroup`/`OutlineGroup`) | click a disclosure triangle to expand a node | **Shipped**: `DisclosureGroup`, `OutlineGroup`, and `List(_:children:)` (§1, Containers). ▶/▼ toggled by Return or Space on the focused branch — except a hierarchical `List`'s rows, where Space is the row's selection and the disclosure is Return's (and Right / Left's, or ⌥Right / ⌥Left for the whole subtree); with the mouse, a `DisclosureGroup` takes the whole row while an outline row takes only the **triangle** — because in a list the rest of the row is the selection's, and the two gestures cannot share it. A one-cell target being unkind, the triangle's button covers the blank cell either side, making it four cells wide. Content is indented into the label's column, so nesting draws a tree either way |
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
| **Pixel filters** (`.blur`, `.shadow`, `.brightness`/`.contrast`/`.saturation`/`.hueRotation`, `.colorInvert`, `.clipShape`/`.mask`) | These are per-pixel compositing ops. A cell is one glyph + fg/bg color; there's nothing to blur or feather. (`.colorInvert` ≈ TUIkit's `.inverted()` on `Text` is the closest analog.) **`.opacity` is the exception and shipped** (§1): alpha is the one filter a cell can express, because the colour it would composite toward is known — the palette background — so the blend can be done on the colour instead of on pixels. |
| **`GeometryProxy.safeAreaInsets` and its `Anchor` subscript** | The reader itself and custom alignment guides *did* transfer (§1, Layout) — in whole cells. These two parts did not: a terminal has no safe area (the whole grid is addressable, and TUIkit's chrome is already subtracted from what a view is offered), and anchor geometry resolves points against a coordinate space that does not exist here. A constant zero would be answering a question the caller should not be asking. |
| **Accessibility (VoiceOver/traits/rotors)** | Not bitmap-inherent, but tied to GUI a11y services; a terminal-native a11y story would be a separate design, not the SwiftUI API. Low priority. |

### 4c. TUIkit-only (no SwiftUI equivalent)

Things a terminal needs that SwiftUI has no concept of. **Verdict: keep** —
these are the value-add of a TUI framework. Keep them clearly *named apart* from
SwiftUI API (the CLAUDE.md rule).

| API | Purpose |
|---|---|
| `.onKeyPress`, `.onMouseEvent`, `.onScrollGesture`, `.onDragGesture` | raw terminal input events (integer coords) |
| `Binding.defaulted(to:)` | substitutes a value for `nil`, turning a `Binding<T?>` into the `Binding<T>` a control can take. The case that needs it is a dictionary entry — `$flags[key]` is a `Binding<Bool?>`, and `$flags[key, default: false]` cannot be written at all because an autoclosure argument cannot form a key path (§1, Iteration). Not a terminal constraint, so it is a deliberate divergence: SwiftUI's answer is an explicit `Binding(get:set:)`, and this is the same thing under a name. Writing through it **creates** the entry, including a write of the fallback — see its doc comment for why it does not delete instead |
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
fixed-`frame` alignment, `@Observable`-only state (and with it `.onReceive`,
whose parameter type is a Combine protocol — §2.3), the `palette`/`appearance`
theming model, and the absence of fonts/animation/shapes/sub-cell-geometry are
the honest consequences of rendering to a grid of character cells rather than a
bitmap. §3 is the one remaining documented divergence (`foregroundStyle`), kept
deliberately. §4a — additive SwiftUI features a terminal can express — is now
**clear on the API side but for one item**: `pinnedViews:` on the lazy stacks.
It reads like an init parameter and is not one — see §2.8 for what it actually
costs.
Everything else there has shipped, `Text + Text` and `LocalizedStringKey`
included. What is deliberately NOT coming back is recorded where the reason
lives: `.onReceive` in §2.3 (its parameter type is a Combine protocol, and CI
builds on Linux), full `AttributedString`/Markdown in §4a, and the bitmap-bound
set in §4b.

The roadmap's centre of gravity has therefore moved to the *implicit-behaviour*
side (the behaviours SwiftUI's built-in views perform on their own, not just the
API you call). Its two flagships — drag-to-reorder rows and
click-a-column-header-to-sort — now both ship, the latter with the keyboard
route still open. Hierarchical data followed them —
`DisclosureGroup`, `OutlineGroup` and `List(_:children:)` all ship. What remains
there is smaller and more scattered: swipe actions, a `TextField` clear
button, and type-ahead selection.
