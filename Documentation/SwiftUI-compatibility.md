# SwiftUI Compatibility

A guide for porting SwiftUI code to TUIkit, and a record of **where** TUIkit's
public API matches or diverges from SwiftUI, **why**, and **whether the
divergence should change**.

TUIkit's stated rule (see `.claude/CLAUDE.md` → *SwiftUI API Parity*): public
APIs match SwiftUI signatures exactly **unless terminal constraints require
deviation**, and any deviation is documented. This file is that documentation.

---

## Two rules that decide every case

**1. The target is _source_ compatibility, not identical signatures.** SwiftUI
source should compile and mean the same thing. The declaration it compiles
against need not be the same declaration: extra *optional* parameters, an added
overload, a TUI-only modifier alongside the SwiftUI one — all fine, because none
of them changes what the SwiftUI spelling does. That is what licenses
`LocalizedStringKey`/`String` overload pairs (§4a), `Int` cell geometry instead
of `CGFloat` points (below), and the TUI-specific knobs that hang off controls
as modifiers rather than initializer arguments.

**2. Anything TUIkit cannot honour must FAIL TO COMPILE.** A stub that accepts a
request and quietly drops it is worse than an absence: the code builds, the
developer never learns the affordance is missing, and the defect surfaces to
their users instead. So an API whose meaning a character grid cannot carry is
removed, not stubbed — the compile error is the notification, and the developer
then decides what to do (drop it, or ask for a terminal-appropriate
substitute). `Font` is the pattern for when a substitute *does* exist: eleven
semantic styles are kept because "this is a heading" survives the medium as
intensity, while `Font.system(size:)` is absent because a point size does not.
`.submitLabel(_:)` was the pattern for when it does not, and was removed once it
was noticed — it stored a value nothing read.

The line between the two is worth stating because it is not "does the parameter
get used": `.monospaced()` and `.autocorrectionDisabled()` ignore their argument
and are correct, because the grid *already guarantees* what they ask for
(`Sources/TUIkit/Modifiers/MediumGuaranteedModifiers.swift`). A guarantee the
medium keeps for free is honoured; a request it silently discards is not.

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

**This file is about vocabulary; behaviour is audited separately.**
[SwiftUI-semantic-audit-2026-08.md](SwiftUI-semantic-audit-2026-08.md) compares
what each shared API *means* against Apple's own doc comments, family by family.
Several rows below are contradicted by it — a ✓ here has never implied that the
semantics were checked, and now there is a place where they were.

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
| State | `@State` (`init(wrappedValue:)` + `init(initialValue:)`), `@Binding` (`init(get:set:)`, `.constant`, `init(projectedValue:)`, **dynamic-member lookup**, `.animation(_:)`, `.transaction` + `.transaction(_:)`, **`Collection` / `BidirectionalCollection` / `RandomAccessCollection` where the value is a `MutableCollection`, and `Identifiable` where the value is**), `@Environment(\.key)` | ✓ | `$model.field` and `initialValue:` both work. A binding's `transaction` is `nil` internally until one is stated, and only then does a write wrap itself: an empty `Transaction` is the statement "this change is not animated", so storing one by default would make every plain binding silently override the `withAnimation` its caller is inside. `.animation(_:)` is the same mechanism under a name — `withAnimation(a)` is `withTransaction(Transaction(animation: a))` — and `.animation(nil)` remains an explicit refusal that survives an enclosing animation. A `Binding` to a collection is a collection OF BINDINGS — `$rows.count`, `for $row in $rows`, `$rows.last` — which is the mapping `ForEach($items)` was already doing privately, now reachable by anything and built from one place. Its element subscript is deliberately not a plain forward: an element binding outlives the frame that made it, so a read past the end answers with the value that was there rather than trapping, and a write past the end is dropped |
| Observation | `@Observable` + `@Environment(Type.self)` + `.environment(obj)` | ✓ | modern reference-type state ports as-is |
| Env / prefs | `EnvironmentKey`, `EnvironmentValues`, `PreferenceKey`, `.environment(_:_:)`, `.preference`/`.onPreferenceChange` | ✓ | custom keys work the SwiftUI way |
| Stacks | `VStack` / `HStack` / `ZStack` / `LazyVStack` / `LazyHStack` | ✓ | `spacing:` is `Int` → §2.1; default spacing → §2.1 note; lazy-stack semantics differ → §2.8 |
| Iteration | `ForEach` (`id:` keypath, `Identifiable`, `Range<Int>`, and over a `Binding` to a collection — `ForEach($items) { $item in … }`, with and without `id:`), `Section` (header/footer/title), `Group` | ✓ | all five `ForEach` forms present. The binding forms hand each row a `Binding<Element>`, which is what a row of editable controls needs — a `Toggle` binds to `$item.enabled` rather than to an index-keyed lookup. Note that `$dictionary[key]` is a `Binding<Value?>` and `$dictionary[key, default: x]` does not compile at all (the `default:` autoclosure cannot form a key path) — both are equally true of SwiftUI. TUIkit adds `Binding.defaulted(to:)` for that case (§4c); SwiftUI's answer is an explicit `Binding(get:set:)`. **SwiftUI's own `Binding(_:)` ships too** — the failable unwrap, `if let name = Binding($profile.nickname)`. The two are the same question answered for different interfaces: `defaulted(to:)` decides what `nil` *draws as* and always shows the control; `Binding(_:)` fails, so the view hierarchy can branch and give the absent case an interface of its own. Emptiness is checked once, at construction: a source emptied afterwards reads back the value it had rather than trapping, and the `if let` re-runs on the next frame — SwiftUI behaves the same way, for the same reason |
| Data | `List` — content-closure **and** data-driven `List(_:id:selection:rowContent:)`, `Table` | ✓ | data-driven `List` routes through the windowed `ForEach` path (O(visible)) |
| Scrolling | `ScrollView(_:content:)`, `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)`, `defaultScrollAnchor(_:)` and `defaultScrollAnchor(_:for:)` | ✓ | the soft-deprecated `showsIndicators:` variant is omitted, per the rule above — `scrollIndicators(_:)` is the current spelling; `scrollTo` targets `ForEach` row identities (no `.id(_:)` tagging yet) and vertical-only scroll views, resolving in O(window) even at millions of rows |
| Adaptive | `ViewThatFits(in:content:)` | ✓ | |
| Layout | `GeometryReader` / `GeometryProxy` / `CoordinateSpace`, `AlignmentID` / `ViewDimensions` / `HorizontalAlignment(_:)` / `VerticalAlignment(_:)`, `.alignmentGuide(_:computeValue:)` | ✓ | sizes are whole cells → §2.2 (`CellSize`/`CellRect`, no `CGSize`); `GeometryProxy` omits `safeAreaInsets` and the `Anchor` subscript (§4b), and `frame(in: .global)` falls back to the local frame where the renderer does not know the on-screen position — `hasGlobalPosition` says which. Guide *values* are `Double` even though sizes are `Int`, because a guide is only ever subtracted from another guide and then floored; see `AlignmentID`. Read `.alignmentGuide` as the **outermost** modifier on a child, as with `.zIndex`. **Gap: a guide does not travel up through a container.** A stack reads the guides of the children it places, so `.alignmentGuide(.decimalPoint)` on a `Text` *inside* a row does not give the row a value for that alignment, and the enclosing `VStack(alignment: .decimalPoint)` falls back to the ID's `defaultValue` — the column comes out left-aligned instead of aligned on the point. SwiftUI resolves a custom alignment recursively through containers, so the same source there works. Put the guide on the view the aligning stack actually places (`.alignmentGuide` on the row, computing the line from the row's own content) — the Layout demo page does exactly that. Closing this needs the guide query to carry a `RenderContext`, since a container cannot locate its children's guides without measuring them |
| Grid | `Grid(alignment:horizontalSpacing:verticalSpacing:)`, `GridRow(alignment:)`, `.gridCellColumns(_:)`, `.gridCellAnchor(_:)`, `.gridColumnAlignment(_:)` | ✓ | spacings are `Int` cells and default to **1 column / 0 rows** rather than SwiftUI's platform metrics — a zero column gap would run adjacent text together, while rows are already separated by being different lines. A non-`GridRow` child spans every column (which is how a `Divider` between rows works). **Omitted**: `.gridCellUnsizedAxes(_:)` — it exists in SwiftUI so a `Divider` does not force its ideal length onto a column, and the full-width spanning above already covers that case |
| Custom layout | `Layout` (+ `Cache`, `makeCache`/`updateCache`, `sizeThatFits`, `placeSubviews`, `callAsFunction`), `LayoutSubviews` / `LayoutSubview`, `LayoutValueKey` + `.layoutValue(key:value:)`, `.layoutPriority(_:)`, `VStackLayout` / `HStackLayout` / `ZStackLayout` (the stacks as Layout VALUES, so `AnyLayout(isWide ? HStackLayout() : VStackLayout())` — the line every adaptive-layout example is built from — compiles and keeps one identity across the switch), `AnyLayout` | ✓ | integer geometry throughout → §2.2: `placeSubviews(in: CellRect …)`, `sizeThatFits` answers `ViewSize`. `LayoutSubview.sizeThatFits` returns `ViewSize` (a superset of `CGSize` — it carries the flexibility SwiftUI makes you infer by probing with `.infinity`, which `ProposedSize` therefore has no need to encode). The cache lives one pass, not across them (`updateCache` still runs, so conformances behave identically). **Omitted**, each for a stated reason on `Layout`: `ViewSpacing`/`spacing(subviews:cache:)`, `LayoutProperties`, `explicitAlignment(of:in:…)`, `Animatable`. **Added**: `LayoutSubview.place(in:anchor:proposal:)` — the region form, which resolves the anchor in a single flooring step (see §2.2) |
| Nav | `NavigationStack` (+ `NavigationLink`, `navigationDestination(for:)` / `(isPresented:)` / `(item:)`, `NavigationPath`), `NavigationSplitView` (2/3-column, `columnVisibility:`), `navigationTitle` (`StringProtocol` / `Text`) | ✓ | a `Text` title renders as a plain string (its styling isn't carried). `NavigationStack` draws a **two-row** bar (the path, then a rule) whose height never varies — chrome that grows with its content cannot be laid out in one pass. The path is a **breadcrumb trail** (`Planets › Mars › Deimos`) where every crumb but the last is a `Button` — a Tab stop, and a click pops straight to that depth, drawn as a word rather than as a control: focus is the crumb's own text breathing, not a bullet beside it. It degrades with the terminal: the full trail, then the middle elided (`Planets › … › Deimos`), then **‹ Back** + the truncated title when even that will not fit. TUI-specific: SwiftUI has no breadcrumb, but a terminal has no swipe-back gesture either, and one Back button at depth 4 is four presses and no idea where you are. Back is also **Escape** or `\.dismiss` (which pops inside a stack instead of quitting) — after the screen's own `.onKeyPress`, which hears Escape first, so a screen that must not be left can consume it. A sheet or alert presented from a pushed screen takes Escape to dismiss itself instead, and the status bar says dismiss rather than go back. The root keeps rendering while a screen is pushed — isolated from focus and key events like a modal's backdrop, and off-screen — which is what keeps its `@State` alive to come back to and its `navigationDestination` closures current. **Each depth is its own focus section**, so coming back lands on the control you left rather than on whichever registered first: pushing remembers, popping restores, exactly as a dismissed modal does. `NavigationPath` has no `CodableRepresentation` (§4b-adjacent: it needs a runtime type-name lookup TUIkit does not have everywhere). `NavigationLink(destination:)` pushes a token keyed on the link's identity, so it needs a path that can hold one — the default stack or a `NavigationPath`; a *typed* path binding can only carry its own element type, so use `NavigationLink(value:)` with those. **The binding-driven destinations ship** — `navigationDestination(isPresented:)` for a screen with no value behind it, and `(item:)` for one that is about something. Both push the same identity-keyed token `NavigationLink(destination:)` does, so both need a path that can hold one. The binding is genuinely two-way: clearing it pops, and popping (Back, Escape, a crumb) clears it. That second direction is the whole of the implementation — "the flag is true and the screen is not on the path" means both *the app just asked for this* and *the user just went Back*, so the modifier remembers whether it was the one that pushed; without that a Back press pushes the screen straight back on. Clearing the flag also takes anything the screen pushed ABOVE itself, since popping to the token alone would strand the user on a screen reached through one that is gone. Apply them to a view that stays on screen — the stack's root keeps rendering while a screen is pushed, which is what keeps them live to notice a pop, but a modifier written on a screen that is itself covered has stopped rendering and cannot |
| Containers | `TabView` / `Tab`, `Form`, `LabeledContent`, `Label` (incl. `Label(_:systemImage:)`), `DisclosureGroup`, `OutlineGroup` | ✓ | **`Tab`'s value type is not tied to the `TabView`'s selection type** the way SwiftUI ties them (through `TabContent`'s associated type), so a `TabView(selection:)` bound to an `Optional` while its tabs carry bare values compiles. It is matched by casting the TAB's value into the selection's type — `as?` promotes to Optional as a language rule — rather than by comparing two `AnyHashable`s, which is false whenever the two sides were erased from different static types. That was a real bug until 2026-08-23: the view fell back to tab 0 and drew the wrong body, and the arrow keys stepped from there. Worth knowing generally — `AnyHashable` unwraps Optionals for types carrying an ObjC bridge, so the `Int`-valued spelling of that mistake worked on Apple platforms and would have failed on Linux. `Label(_:systemImage:)` renders an SF Symbol glyph on Apple terminals → §2.4; `formStyle(.columns)` (default) / `.grouped`. `DisclosureGroup` has all four SwiftUI initializers (custom label / `Text` title, each with and without an `isExpanded:` binding) and draws `▶`/`▼` before the label, with the content indented to start in the label's own column so nesting draws a tree. The header is one control — Tab stop, Return/Space, or a click anywhere on the row — because a terminal has no separate triangle to hit; **Right opens it and Left closes it** as well, which is what the `List` form has always done, so the same tree answers the same keys whatever it was put inside (they SET rather than toggle, and a Left with nothing left to close goes back to being ordinary focus movement). `content` is `@escaping () -> Content` as it is in SwiftUI, and a collapsed group never calls it, so a closed section costs nothing per frame. **Deliberate divergence:** a collapsed group RETAINS its content's state — a nested group you opened is still open when you reopen its parent, a field you typed in still has your text — where SwiftUI takes the content out of the hierarchy and its `@State` with it. The retention lasts only while the group itself is on screen and covers what `StateStorage.retainSubtree` covers (`@State`, `onChange` baselines, conditional-branch records), not `.task`s or `onDisappear`. **Omitted: `DisclosureGroupStyle`** — a terminal disclosure is a triangle and an indent, so there is no second geometry for a style to express. `OutlineGroup` has all four initializers (a root element or a collection, each with `Identifiable` ids or an explicit `id:` key path). Its branch rows disclose from the **triangle** rather than from the whole row — an outline row's text has to stay free for whatever contains the outline to claim, which is what will let a list select the node whose triangle just opened it; the keyboard follows the same division: standing alone each branch's triangle is a Tab stop that Return or Space toggles and that Right / Left open and close, while inside a `List` the ROW is the focusable — Space selects it, Return activates it (disclosing a branch, unless the app claims Return with `.onRowActivate`), and Right / Left open and close it either way — and ⌥Right / ⌥Left do the same to the whole subtree at once, the Finder's gesture (a recursive collapse folds the descendants too, so re-opening shows the branch as it was left). A second focus stop per branch would have taken the row's Space with it. One cell is a poor mouse target, so the triangle's button covers the blank cell either side of it as well. It emits one row per **visible** node to whatever contains it, exactly as `ForEach` emits one per element: the depth is each row's leading padding, not a nest of views, so a closed branch's descendants are neither built nor measured and a deep tree is not a deep view hierarchy. (Like `ForEach`, it therefore has no `body` of its own — it is a run of views, not one.) `List(_:children:)` and `List(_:children:selection:)` follow from that in six initializers, so a list's cursor, selection binding and scrolling address **nodes**. SwiftUI's `Parent` and `Subgroup` generic parameters are dropped along with the `OutlineSubgroupChildren` marker they exist to name — `Parent` is always `Leaf` and `Subgroup` has exactly one possible value, so all three are phantom (the same call `Gauge` makes about its fourth parameter); the initializers are SwiftUI's exactly. The `Binding`-of-collection initializers are absent. **`.deleteDisabled(_:)` and `.moveDisabled(_:)` ship** — per-row refusals, written inside the `ForEach`. A locked row leaves Delete alone entirely rather than swallowing it, so the key falls through exactly as it does in a list that is not deletable at all; a pinned row starts no drag, and other rows still move PAST it (`moveDisabled` says this row does not travel, not that its position is fixed — SwiftUI's meaning). The flag is stated inside the row's subtree, so it is reported as the row RENDERS rather than read off the row's structure: `Text(…).deleteDisabled(x).padding()` puts the padding outermost, and a structural read would depend on modifier order. Two consequences worth knowing. A refusing row opts out of the row value-memo — otherwise it would be reported on the frame it appeared and forgotten on every frame after, and the row would quietly become deletable again — while a row refusing NOTHING reports nothing, declares nothing and memoizes exactly as before, which is the case most rows in such a list evaluate to. And only rows that were drawn can report, which is sufficient because only drawn rows can be edited: Delete acts on the focused row and a drag on the grabbed one. `Table` has no counterpart, as in SwiftUI — its rows are values, with no view to write a modifier on. **`ForEach($items, editActions:)` and `EditActions` ship** — the `ForEach` performing the edits on its own binding instead of you writing the two closures that would have contained exactly `move(fromOffsets:toOffset:)` and `remove(atOffsets:)`. `EditActions` is generic over the collection as SwiftUI's is, so `.move` needs a `MutableCollection` and `.delete` a `RangeReplaceableCollection` — the cases are constrained separately, which is what stops `.delete` being offered for a collection that cannot shrink. An action NOT in the set is not merely inert: the `List` is never told the rows can move or be deleted, so no drag-reorder gesture arms and no delete key is claimed. **One deviation:** the collection must be `Int`-indexed. That is not a choice about editing — it is the constraint TUIkit's own `move(fromOffsets:)`/`remove(atOffsets:)` already carry so they out-specialise SwiftUI's overlay versions of those names on Apple platforms; without it this compiles and then fails to LINK against SwiftUI symbols TUIkit does not link |
| Presentation | `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)`, `alert` (Boolean, `presenting:` and `error:` forms), `confirmationDialog` (Boolean and `presenting:` forms) | ✓ | presented as a centred, dimming overlay. An `alert`/`confirmationDialog` dismisses when any of its actions is chosen (SwiftUI's behaviour — the action closure does not flip the binding itself), and claims Escape on the status bar while it is up, so a page's own `⎋ back` cannot navigate out from under it. Escape *is* the `.cancel`-role button (macOS gives Cancel the Escape key equivalent): it runs that action if there is one — a disabled one is skipped — and closes the dialog either way. A `sheet`/`modal` deliberately does NOT auto-dismiss when one of its buttons is pressed: its content owns its own close button. That button reaches for `@Environment(\.dismiss)`, which **means the presentation** — every presentation modifier (`sheet`, `modal`, `fullScreenCover`, `popover`, `alert`, `confirmationDialog`) publishes a `DismissAction` that closes it, the same act as its Escape route, so `onDismiss` fires either way. Previously none of them did, and the presented content inherited the top-level meaning — quitting the app — so a `Button("Done") { dismiss() }` in a sheet terminated the program. **The data-driven `alert` spellings ship too** — `alert(_:isPresented:presenting:actions:)` (with and without `message:`) and `alert(isPresented:error:actions:)` (likewise). What `presenting:` adds over closing over the value is the CONDITION: the alert's buttons act on something, that something is usually the same state its presence is derived from, and taking it as a parameter means `nil` withholds the alert instead of drawing one about nothing. The `error:` forms take the title from `errorDescription` and the message from `recoverySuggestion` — which is what those properties are for — and an error with no suggestion gets no message line rather than a blank one. SwiftUI's asymmetry is kept verbatim: `alert(isPresented:error:actions:)` hands the error to `message` but not to `actions`, while the two-builder form hands it to both. `confirmationDialog` takes `presenting:` on the same terms, `titleVisibility` included. |
| Lifecycle | `onAppear`, `onDisappear`, `task` (incl. `task(id:)`), `onChange(of:initial:_:)` (both current forms), `onHover` | ✓ | matches the *current* `onChange`; deprecated `perform:` correctly absent |
| Controls | `Button` (string **and** `Button(action:label:)`), `Toggle`, `Slider`, `Stepper`, `ProgressView`, `Gauge`, `TextField`, `SecureField`, `TextEditor`, `Picker`, `DatePicker`, `Link`, `ColorPicker`, `Divider`, `Spacer`, `EmptyView`, `AnyView`, `ContentUnavailableView` | ✓ | `Slider`/`ProgressView`/`Stepper`/`Gauge` are floating-point-capable; `Divider` draws across the MINOR axis of the stack containing it, as SwiftUI's does — `─` in a column and anywhere that is not a stack, `│` spanning the height in a row — and it takes one cell across rather than reporting itself width-flexible, which in a row would have made it absorb all the slack and push its siblings to the two ends; `Gauge` takes `.gaugeStyle(_:)` with terminal-native `.linearCapacity`/`.accessoryLinear`/`.accessoryLinearCapacity`/`.accessoryCircular`/`.accessoryCircularCapacity`/`.accessoryCircularTiny` (a closed set — a terminal can't host user-defined gauge geometries; the `Capacity` styles fill min→value cumulatively, the others mark only the value's position; circular styles draw a ring dial, `…Tiny` a single pie glyph); custom `ButtonStyle`/`ToggleStyle` via `makeBody`; **`Stepper` draws its value where SwiftUI's draws nothing**, which makes the `onIncrement:`/`onDecrement:` init — the one whose steps are not arithmetic on a number — the case with a slot and nothing to put in it. It used to fabricate a `0` from the throwaway binding those callbacks never touch, so the read-out sat at 0 however many times you pressed; it now collapses to `◀▶`, which is SwiftUI's own answer (no value, so none shown). TUI-specific **`.stepperValueText(_:)`** fills the slot for a stepper over colours, fonts or enum cases — a plain `String`, re-evaluated every frame like any other body expression, and it overrides a value stepper's formatting too; `PickerStyle` is a marker protocol, matching SwiftUI; **`TextFieldStyle` + `.textFieldStyle(_:)` ship**, with the two names a terminal can tell apart: `.automatic` draws the field — a coloured surface between half-block caps — and `.plain` draws neither, leaving the text on whatever is behind it, which is what an editable value inline in a row or a sentence wants. `.plain` emits **no** background rather than the palette's, so a plain field inside a tinted container picks up that tint the way ordinary text does. The caps are two real cells, so the style changes the field's WIDTH: both passes take that number from one helper (`FieldChrome`), because the arithmetic otherwise appears four times — each of `TextField` and `SecureField`, measure and render — and the leading cap is likewise what the click-to-caret map subtracts, so a plain field's column 0 is its first character. **Omitted: `.roundedBorder` and `.squareBorder`** — each names a shape of border around the same field, and a cell grid draws one rectangle; the spellings would compile and then be indistinguishable. A field wanting a real frame composes one (`TextField(…).border()`). `Link` opens via `@Environment(\.openURL)`, and on a terminal measured to honour them **also emits a real OSC 8 hyperlink**, which tells the host where the label points — so the URL can be shown on hover and copied even though it appears nowhere on screen, which is the one thing neither keyboard nor mouse activation can give a link. Whether the terminal also OPENS it on a modified click is host-specific and partly open (a TUIkit app holds mouse reporting, and iTerm2 is measured to forward ⌘-click to the application instead). TUI-specific `.terminalHyperlinks(false)` turns the escape off for a subtree, and an app that intercepts its own URL scheme should: wherever the terminal opens a link itself it does so over the top of `OpenURLAction`. Which hosts get it is measured, not assumed — `Documentation/Terminal-compatibility.md`, "OSC 8 hyperlinks" — and **`OpenURLAction.Result` ships** with SwiftUI's `(URL) -> Result` initializer beside TUIkit's own `(URL) -> Void` one. The reason a handler returns something is that it can DECLINE: `.systemAction` hands the URL back to the system opener, so an app can intercept its own scheme and leave every other link alone without re-implementing the opener for the ones it never wanted. **The system opener itself is OFF by default** (3a96d8fc): the process may be on the far side of an ssh hop, where `open`/`xdg-open` would run on the wrong machine, and no signal says which side it is on — so a default activation raises the destination popover (and the OSC 8 hyperlink lets the terminal, which IS on the user's machine, open it), and a tool that knows it is local opts in with `TerminalClient.urlOpeningSupport` or the user with `TUIKIT_OPEN_URLS=1`. That is the one accepted-then-inert spelling on this row, and it is deliberate. `.systemAction(_:)` rewrites the URL on the way. **Omitted: `prefersInApp:`** on both the `Result` case and `callAsFunction` — it names an in-app browser view, and a terminal has no window to put one in, so the argument could only ever be ignored; `TextEditor` scrolls to follow the cursor (no soft-wrap yet); `DatePicker` is an inline numeric field (no calendar popup, fixed numeric format; Left/Right pick a component, Up/Down adjust it by one, Page Up/Down by a coarse step — a decade, a quarter, a week — and Home/End send it to the ends of its own range; the wheel steps whichever field it is pointing at — the one thing the keyboard cannot do without first walking to that field — in the framework's usual direction, wheel-up towards earlier; and the field lifts under the pointer like every other control, unless it already holds the focus and is saying so with its pulsing active block); multi-selection is `List(selection: Binding<Set<…>>)` (SwiftUI has no multi-select `Picker`). `ColorPicker`'s swatch does what SwiftUI's does — a click, `Return` or `Space` opens the full colour editor (SwiftUI's platform colour panel; here `ColorPickerPanel`, as a modal on the same binding) — and, because a terminal row has width SwiftUI's control does not, the rest of the row edits R/G/B in place. The swatch marks focus and hover in its CENTRE CELL (a bullet, pulsing while focused) rather than by re-colouring itself, because unlike every other control its colour is its content; the gradient editor's stop chips share that style. TUI-specific `.colorPickerLabelWidth(_:)` sets the label column a stack of pickers lines up on — SwiftUI sizes a picker's label to its text and aligns a column of them with a `Form` or a `Grid`. **`TextField(_:value:format:prompt:)` and its two siblings ship** — a field bound to a typed value rather than a `String`, through a `ParseableFormatStyle`. The substance is the draft: a field cannot format on every keystroke (typing `1` into a `.currency` field would put the caret behind `$1.00` and send the next character somewhere nobody asked for) and cannot parse on every keystroke either (`1.`, `-` and `""` are all things you must be allowed to have typed on the way to a number, and none of them parses). So the field holds the text as typed for exactly as long as it is being typed, and reconciles at the two moments the user says they are finished: Return, and leaving the field — the second is `TextFieldHandler.onFocusLost`, so tabbing away commits what Return would have. Text that does not parse is discarded silently, because a terminal field has nowhere to report an error, and dropping the draft makes the field snap back to what the value actually is; the same mechanism is what makes a *successful* commit visible, since `1e3` in a `.number` field lands as `1,000` once the value is being formatted again. An untouched field never writes to its binding, so focusing and leaving one republishes nothing. The draft lives in a `@State` on a bridging view rather than in `_TextFieldCore`, because `@State` is bound by the view's own identity at render time and that is exactly the lifetime the draft needs; everything below it is the plain string-editing field, unchanged and unaware. **Omitted: the `formatter:` spellings** (and `Text(_:formatter:)`) — `Formatter` is the pre-`FormatStyle` class API, parsing through an untyped `AnyObject` out-parameter and, in SwiftUI's `Text` overloads, constrained to `NSObject`/`ReferenceConvertible`; the typed form is the same feature with the round-trip statically guaranteed, so shipping both would only add the unchecked one. **`.labelsHidden()` and `.labelsVisibility(_:)` ship**, with `\.labelsVisibility`. A control's label is the text it draws BESIDE itself, and hiding it takes the label's CELLS — the row closes up rather than keeping a blank gap where the words were, which is the whole point when a `Form` or a `Grid` is doing the labelling itself. Every labelled control honours it: `Toggle`, `Picker`, `Slider`, `Stepper`, `DatePicker`, `ColorPicker`, `LabeledContent`, `ProgressView`, `Gauge`. Three of those route through the shared `_CollapsingLabel` unit ("label, one separating space, or nothing") and `DatePicker` and `LabeledContent` were moved onto it here, so the meaning of *hidden* lives in one place rather than in each control's stack. A `Form` loses the label PILLAR, not just the captions — a column sized to labels nobody draws would indent every control by the width of the longest invisible one. **Deliberate split:** it takes the caption and leaves the READOUT, so a `ProgressView`'s or `Gauge`'s `currentValueLabel`, and a gauge's bound labels, stay — they state the value the control is showing rather than name the control. Ordinary content is untouched: a `Text` sitting beside a control in a stack is content, not that control's label. SwiftUI keeps the hidden label for accessibility; a terminal has no separate accessibility tree, so here it is simply not drawn — write one anyway and the same source reads correctly on both |
| Modifiers | `padding`, `frame`, `overlay(alignment:content:)`, `fixedSize`, `foregroundStyle` (any `ShapeStyle` → §3), `background` (any style, or none — §3), `backgroundStyle`, `disabled` (on any `View`), `tint`, `tag`, `zIndex`, `badge`, `listStyle`, `formStyle`, `lineLimit` (on `Text` **and** on any `View`), `truncationMode`, `multilineTextAlignment`, `opacity` | ✓ | units are `Int` → §2.1; `lineLimit`/`truncationMode` on a `View` cascade to every `Text` below, and one written on a `Text` wins there — `.lineLimit(nil)` means *unlimited*, so it is also how a branch opts out of an inherited cap; `disabled` cascades via `\.isEnabled`; `tint` overrides the accent role (§2.5); `frame` default alignment is `.topLeading` → §2.7; `multilineTextAlignment` aligns a wrapped `Text`'s lines within its own block width (single-line text unaffected); **`opacity` is real compositing** — the subtree renders to its own layer and each of its cells is resolved against the cell beneath where the layer lands, so a view fading over a coloured panel moves toward the panel's colour rather than the page's, and nesting multiplies as in SwiftUI (`0.5` inside `0.5` is `0.25`). Hue is preserved (a red heading at `0.5` still reads red), and the view keeps its space and its hit-test regions at every alpha. **The mix is in encoded sRGB, matching SwiftUI** — measured through `ImageRenderer`, which composites `Color.opacity(a)` over a ground to the same byte an encoded lerp gives at every alpha tried and never to the linear-light one. TUIkit blended in linear light until 2026-09-04 on the argument that it is physically what a translucent layer does; it is, and it is also 22× more sensitive near transparent than near opaque, which showed up as a spring transition whose fade-out visibly bounced and whose fade-in did not. See `Documentation/Opacity as composition.md`, rule 5. Colours compose exactly at every alpha; **characters cannot** — two cannot share a cell at half strength each — so alpha is a decision for the glyph, taken only where two characters contest a cell: **over anything blank the subtree's characters draw at every alpha and fade all the way out; where a character sits underneath, the subtree's draws at or above `0.5` and the one behind shows below it**, keeping its own foreground while its field carries the veil (matching characters never snap — they cross-fade exactly). Text over different text therefore swaps characters at the midpoint instead of dissolving, which is the one visible departure from a graphical compositor; in exchange `opacity(0)` genuinely reveals what it covers rather than painting an invisible-coloured rectangle over it. Two rules make fading a container behave: a source SPACE composites its background and keeps what is behind it (so fading a `VStack` does not blank its rectangle), and the destination's foreground is never tinted (a translucent pane over text leaves the text legible). A repeating fade still costs no render passes — the compositor colours every phase of the cycle once and the run loop replays them |
| App | `App`, `Scene`, `WindowGroup`, `SceneBuilder`, `@main`, `@AppStorage`, `@Environment(\.dismiss)` | ✓ | `@AppStorage` is *enhanced* (pluggable backend). `\.isPresented` says whether a view is inside something presented (a sheet, modal, cover, popover, alert or dialog) — `false` for a pushed `NavigationStack` screen, which was navigated to rather than presented. `\.dismiss` means the nearest thing that can be dismissed: a presentation closes, a pushed `NavigationStack` screen pops, and only at the top level — where a terminal app has nothing enclosing it — does dismissing mean quitting |
| Text | `Text(_:)` (`LocalizedStringKey` **and** `StringProtocol`), `Text(verbatim:)`, `Text(_:format:)`, `Text + Text` | ✓ | a literal is a localization key, a computed `String` is not — SwiftUI's rule, and §4a records what it took to reproduce. **Every control and modifier that takes a title takes one too** — `Button`, `Toggle`, `TextField`, `Section`, `navigationTitle`, `alert`, … — as does the TUI-specific chrome (`Dialog`, `Alert`, `Card`, `StatusBarItem`, notifications); see §4a |
| Color values | `Color.red`/`.green`/`.primary`/`.secondary`/… and `.opacity(_:)` | ✓ | *constructing* a Color differs → §2.5. `Color.opacity(_:)` mixes toward black and shadows `ShapeStyle.opacity(_:)` for a `Color` receiver, as it does in SwiftUI; the two coincide on a dark palette |

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
Image(systemName: "star.fill")          Image(systemName: "star.fill")            // the glyph alone
Button("Save", systemImage: "tray") { } Button("Save", systemImage: "tray") { }   // and on the controls
```

**A raster `Image` renders as text everywhere, and as REAL PIXELS where the
terminal has a graphics protocol.** The glyph renderer is the universal path and
the one this section used to describe as the only one: a raster source converted
to ASCII/ANSI art with its own controls (`.imageCharacterSet`, `.imageColorMode`,
`.imageDithering`). On a terminal that answers TUIkit's startup handshake — it
will place an image in its **cell grid**, through the Kitty protocol's Unicode
placeholders — the same `Image` draws the actual picture instead, at roughly
fifty times the pixels and in full colour, with no palette quantisation and no
contrast floor. Nothing else changes: the picture occupies the same cells, in the
same place, measured by the same function, so a layout does not move when the
renderer does. Detection is a handshake rather than a host table, and `false` is
the default before one answers, so an unmeasured terminal draws glyphs. TUI-specific
`.terminalGraphics(false)` keeps the glyphs on a terminal that could draw a
photograph, which an app built around a ramp genuinely wants — see
`Documentation/Terminal graphics protocols.md`.

**`.mono` plays the template image's part.** SwiftUI tints a template image with
`foregroundStyle`. TUIkit has no `renderingMode(_:)`; `.imageColorMode(.mono)` draws
a picture in two tones instead, and its ink is the view's `foregroundStyle`, so it is
re-inked wherever `Text` would be (a button's label, a menu row's highlight). Its
paper is the view's `backgroundStyle`, which is TUI-specific: a template image's
unlit pixels are transparent, but a half-block cell's unlit half is the cell's
background colour and has to be stated.

A cell grid still cannot blit a bitmap *itself*, which is why this is a protocol
and not a drawing API: TUIkit hands the terminal an image and a rectangle of
cells, and the terminal draws. Vector glyphs are unchanged — see below.

**`Image(systemName:)` now ships**, reversing what this section used to say. The
old reasoning — an SF Symbol is a character rather than a resizable image, so it
is modelled as text — describes the value correctly and was the wrong conclusion
to draw from it: that a symbol cannot be scaled is a property to document, not a
reason to withhold the spelling every ported SwiftUI file uses. It draws exactly
the glyph `Label(_:systemImage:)` draws, under the same conditions, and the
raster rendering modifiers simply have nothing to do to a character. Where the
symbol would not really draw it renders **nothing** — the honest output, since
there is no title to fall back to, and the one place `Label` still does better:
it can close the gap it was going to leave, and a bare `Image` in an `HStack`
cannot, the spacing being the stack's.

**SF Symbols DO render as glyphs — but only in very limited circumstances.**
`Label(_:systemImage:)` matches SwiftUI's signature, and `SFSymbol.glyph(named:)`
/ `SFSymbol.all` expose the mapping directly. Each SF Symbol lives in the
Plane-16 Private Use Area, so it renders **only** where a font supplies its
glyphs: an **Apple platform**, in a terminal using a font that has them
(**Terminal.app with SF Mono**, with the **SF Symbols font installed** — not the
default). Everywhere else — Linux, or a terminal without the font —
`Label(_:systemImage:)` shows just its title, `Image(systemName:)` shows nothing,
and `SFSymbol` resolves nothing, so code stays correct; the glyph simply appears only where it can. The name →
codepoint table is Apple's own, extracted deterministically from the SF Symbols
app (`Tools/GenerateSFSymbols`), and the Private-Use width/advance is handled the
same way as VS-16 emoji. See `SFSymbol` for the full rules.

**The `systemImage:` shorthand now reaches the controls**, not just `Label`:
`Button(_:systemImage:action:)` and `Button(_:systemImage:role:action:)`,
`Toggle(_:systemImage:isOn:)`, `Picker(_:systemImage:selection:content:)` and
`ContentUnavailableView(_:systemImage:description:)` (Sources/TUIkit/SFSymbols/
`ControlSymbolInitializers.swift`). Each builds the `Label` the long spelling
would have built, so each inherits the fallback above whole — an unresolvable
name renders the plain control, byte for byte, which is what the tests pin
rather than a glyph they could only see on some hosts. `Button` is the one that
had to adapt: it is not generic over its label, so the icon reaches it through
the composed-label path (`ButtonStyleConfiguration.labelView`) rather than the
string one — the two paths are otherwise interchangeable, which that byte
comparison now also proves.

**The `image:` spelling of all five stays out**, and is the clearer half of the
rule: it names an `ImageResource` — a constant Xcode generates from an asset
catalogue, whose value is a bitmap at some scale factor. A terminal app has
neither the catalogue nor anywhere to put a bitmap, so there is no honest
implementation, and by the second of the two rules at the top of this document
the call must therefore fail to compile rather than quietly drop the icon.
Recorded as a family in `parity-map.json`. The difference
between the two spellings is exactly the difference between a *character* and a
*picture*: an SF Symbol is the former, and that is the whole reason it can be in
a terminal at all.

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

`.toolbar(removing: .sidebarToggle)` is the one `toolbar`-spelled API TUIkit has,
and it is a **removal**, not a container: it takes away `NavigationSplitView`'s
own toggle handles (the ◀ on the leftmost divider and the ▶ edge column), which
stand in for SwiftUI's toolbar sidebar button. `ToolbarDefaultItemKind.title` is
not provided, because TUIkit draws no default title item to remove.

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
  genuinely lazy: children render top-down until the next would overflow
  `availableHeight`; the first child that does not fit whole renders
  **clipped at the cell** — the same overflow picture as the eager
  stacks — and children past it are *never rendered* (so their
  `onAppear`/`task` correctly never fire; a child that would show zero
  lines is not rendered either). A saturated stack measures as the
  limit, exactly as `VStack`'s `min(total, proposal)` does — a
  row-boundary measure used to end the natural-extent ladder early and
  silently truncate scrollable content.
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
  "Placed" is what a walk at the given height budget reaches: a stack asked
  how wide it would be in eight lines answers for the rows those eight lines
  hold, not for one far below the fold. A **windowed** stack cannot measure
  every row (that is the point), so beyond the fold this is a heuristic — the
  widest row it has ever drawn or sampled — but it is one heuristic, shared by
  every path that answers, and it never shrinks while the content is
  unchanged. It is also never narrower than the band on screen: a stack
  scrolled to a wide row reports that row, however narrow the first rows are.
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

### 2.9 What clips a floating layer, and how far a spring may carry a view

A view's drawing can leave its own bounds three ways here: `.offset`,
`.position`, and — since a spring goes past its target — a `.move` / `.offset`
transition on the way back. All three become a **non-opaque overlay layer**:
the view's own cells, floating, with nothing painted where they came from
(a terminal has no transparency, so an in-place blank box would erase the page).

**Which containers clip one is SwiftUI's answer, not a terminal's.** Two doc
comments in the SDK settle it:

- `View.clipped(antialiased:)` — a view's bounding frame is used only for
  layout, and content extending beyond it is still visible. So a plain
  `VStack`/`HStack`/`ZStack` clips nothing, and neither does `.frame()` alone.
- `View.scrollClipDisabled(_:)` — a scroll view clips its content to its bounds
  by default, which is what the modifier exists to turn off.

TUIkit clipped **none** of them until now: `.offset(x: 7)` on a row of a
12-wide `ScrollView` painted three columns of the page beside the viewport, and
the same row in a 14-wide `List` painted over the list's own right border. Both
now clip a layer that is a piece of their content (`ScrollView`'s viewport,
`List`'s bounds), and a plain stack still does not. `.scrollClipDisabled(_:)`
itself is **not** implemented; if it is ever wanted, the clip is one call in
`ScrollView`'s windowing.

**A presentation is not content and is never clipped.** A menu, a drop-down, a
dialog or a toast is a window over the page — the layer flag is `isOpaque` —
and clipping one to the scroller its trigger happens to sit in is how a picker
on the last visible row loses every option. SwiftUI does not clip its
presentations to a scroll view either.

**Overshoot.** `Animation.bouncy` peaks at phase **1.0460**, `.snappy` at
**1.0063**, `.smooth` at exactly 1 (measured from `Animation.fraction(at:)`).
Past 1, `.move`/`.offset` transitions draw the view a whole number of cells
clear of the slot it has just arrived in; `.opacity` and `.scale` stop at 1,
because nothing is more opaque than opaque and `.scale` uncovers a buffer that
IS the slot. There is deliberately **no minimum**: `.snappy`'s 0.13 of a cell
across a twenty-cell view draws no bounce, matching a SwiftUI snappy that does
not visibly bounce, and a bounce needs a panel eleven rows tall before it moves
vertically at all.

Ordering is **relative**, and the compositor already expressed it: layers sort
by level (`popover < modal < alert < notification`), so an overshoot on the page
draws under a dialog, while an overshoot INSIDE that dialog rides in the
dialog's own buffer and is drained in the next compositing pass — above it. The
only thing that had to be added was a sub-level ordinal: displaced drawing takes
a negative `zIndex` (`OverlayLayer.displacedDrawingZIndex`), so a bouncing label
sorts under an anchored drop-down at the same level instead of under whatever
the tree happened to emit first. No case of the level enum moved.

**Three deviations from SwiftUI inside the overshoot**, each because a cell
grid is not a compositor: hit-test regions stay at the slot for the duration
(moving them would let a bouncing view steal a peer control's clicks, since the
dispatcher takes the last matching region); the floated cells are trimmed of
trailing blanks, because compositing replaces the base cell under every overlay
cell including spaces, and a slot-width row of padding would wipe a column of
its neighbour per cell (leading blanks inside a row that has content still
paint — a layer has one origin, not one per line); and a view bouncing at the
screen edge loses the columns that fall off it rather than sliding back on, as
a menu would.

**While a view is arriving** (phase 0…1) the slot still clips it, which is a
deviation: by the `clipped(antialiased:)` rule above, SwiftUI would let it
cross its siblings. Here crossing them means *erasing* them, one glyph per
cell, so the slot is the boundary until the view has arrived.

## 3. Open divergence

**None.** The one that stood here is closed, and how it fell is the fifth
instance of the pattern §4b warns about, so it stays on the record.

### Closed: `foregroundStyle` takes `some ShapeStyle`

The claim was that the only thing a `Color?` parameter lost was "non-colour
`ShapeStyle`s — gradients, materials — which are bitmap concepts that don't
render in cells". Half of that is true: `Material` and `Shader` genuinely have
no meaning in a cell grid, and they are still absent **as types**, which is what
makes `.foregroundStyle(.thickMaterial)` fail to compile rather than compile and
do nothing. But a gradient is not a bitmap concept. It is a function from a
position to a colour, and a cell has a position — so `t` is answerable per cell
and the ramp is drawable. The row described a real terminal limitation
accurately and then used it to withhold a spelling that did not depend on it.

`foregroundStyle<S: ShapeStyle>(_:)` and `background<S: ShapeStyle>(_:)` now
take any style, with `@_disfavoredOverload` `Color` twins so `.foregroundStyle(.red)`
and `.background(.palette.accent)` still infer (Apple marks `tint` the same
way). What ships:

| | |
|---|---|
| `ShapeStyle` | the protocol, conformable — `resolve(in:)` with public defaults, as since macOS 14. SwiftUI's underscored `_apply`/`_makeView` are omitted: they are over types that exist only inside SwiftUI |
| `Gradient`, `Gradient.Stop` | source-identical, `location` a `Double`. A bare `Gradient` as a style is a **vertical** linear gradient, measured |
| `LinearGradient`, `RadialGradient`, `EllipticalGradient`, `AngularGradient` | all four, with their `colors:`/`stops:` twins and the `.linearGradient(…)` static-member spellings |
| `AnyShapeStyle` | erasure — the runtime style-choice idiom |
| `AnyGradient`, `Color.gradient` | a colour with a little depth in it: `.foregroundStyle(.blue.gradient)`. A derived gradient carries its BASE colour and works its stops out at paint time, because `Color.palette.accent` is a reference with no palette to resolve against until something paints. The lightening is `+0.15` HSL lightness with hue and saturation held — measured against SwiftUI's own renderer and recorded in the API docs, along with the one row it misses (black) |
| `Color.mix(with:by:in:)` | a two-stop gradient evaluated at the fraction, in whichever space you name — default `.perceptual`, as SwiftUI's is |
| `Gradient.ColorSpace` (`.device`/`.perceptual`), `Gradient.colorSpace(_:)`, `AnyGradient.colorSpace(_:)` | both return `AnyGradient`, as SwiftUI's do. **Additive beside them**: the space is also stored on `Gradient` (`init(stops:colorSpace:)`, `init(colors:colorSpace:)`), because in SwiftUI a space can ONLY ride on `AnyGradient` — measured: `LinearGradient(gradient:startPoint:endPoint:)` refuses one — and a terminal's gradients are overwhelmingly directional. SwiftUI's own default asymmetry is kept rather than tidied: a bare `Gradient` is `.device`, `mix` is `.perceptual` |
| `ShapeStyle.opacity(_:)`, `.in(_:)` | `.in(_:)` takes a `CellRect` (§2.2) |
| `Color: View`, and the four gradients too | a style used where a view goes fills the space it is offered — flexible in both axes with a minimum of zero, so it claims slack and never demands any. A bare `Gradient` is deliberately not one, as in SwiftUI |
| `backgroundStyle(_:)`, `background()`, `BackgroundStyle` (`.background`) | one names the surface, the other paints it; with nothing named it is the palette's own background, a cell grid's answer to the system background material. `ignoresSafeAreaEdges:` is omitted — a terminal has no safe area for it to talk about |
| `View.gradientExtent(_:)` | **TUI-specific**, and the reason this was worth doing: SwiftUI has no way to run one ramp across a *set* of views, and a terminal list wants exactly that |

Layering a fill behaves as it does in SwiftUI: `ZStack { Color.red; Text("hi") }`
draws the letters on the red. A cell's glyph and the colour behind it are two
statements, and an overlay cell that names no background has said nothing about
the field it lands on, so it keeps the one that is there; a cell that names its
own background keeps that instead. Compositing is otherwise opaque per cell —
blank cells paint, which is what dialog interiors and the modal dim depend on.

Two deviations, both stated in the API docs. `RadialGradient`'s radii are `Int`
cells like every other dimension here (§2.1), and — because a cell is about
twice as tall as it is wide — a radius is measured along the **horizontal**
axis with the vertical derived through `imageCellAspect`, so a circle looks
like one. `EllipticalGradient` is the geometry that follows the box's own
shape, and takes no such correction for the same reason.

Three spellings stay out, each because a terminal cannot honour them and the
rule is that what cannot be honoured must not compile:

- **`foregroundStyle(_:_:)` and `(_:_:_:)`.** The second and third styles paint
  a symbol's second and third *layers*, and a glyph in a cell has one.
  Accepting them and ignoring them is exactly the silent lie this file
  otherwise exists to prevent.
- **`Text.foregroundStyle<S>` returning `Text`.** A gradient on a `Text` works
  — it returns `some View` through the `View` modifier. What does not compile
  is `Text("a").foregroundStyle(gradient) + Text("b")`. A ramp given to the
  whole concatenation now bands across its fragments, cell by cell, so the
  original reason ("a run carries one colour") no longer holds; what still
  does is that a run's stored attributes name ONE colour, and a ramp on one
  FRAGMENT would need a paint per run rather than a style per run. Until that
  exists, the spelling that would quietly lose the gradient is the one that
  fails.
- **`HierarchicalShapeStyle`.** Its four names are palette roles here, and two
  of them — `Color.primary` and `Color.secondary` — are already spelled on
  `Color`, where SwiftUI spells them too. A second type carrying the same names
  would make `.foregroundStyle(.secondary)` ambiguous for no gain. `.quinary`
  has no counterpart: this palette names four foreground tiers, and a fifth
  spelling painting the fourth's colour would be a lie of a different kind.

`MeshGradient` is declined and recorded: "given a cell, what is `t`?"
generalises to `(u, v)`, so it is not impossible — it is simply not worth it at
80×24.

---

## 4. No overlap

### 4a. SwiftUI has it · TUIkit should add it

Possible in a terminal, just not built yet. **Verdict: add over time**, roughly
in this priority order. (Proposals are one-liners; trade-offs noted where
non-obvious.)

| Feature | Why it matters | Design sketch / trade-off |
|---|---|---|
| **Presentation: `popover`, `fullScreenCover`, `presentationDetents`** | Common modal patterns. | **All shipped.** `popover(isPresented:attachmentAnchor:arrowEdge:content:)` is an ANCHORED presentation, not another centred sheet: a bordered panel beside the view that presented it, over an undimmed page, closed by Escape or a click outside — the same presentation `.contextMenu` and the `Picker` drop-down use, with your content instead of menu rows. `arrowEdge` picks the side (a terminal draws no arrow); `attachmentAnchor` takes `.rect(.bounds)` (centred on the view) or `.point(_:)`, SwiftUI's `Anchor<CGRect>.Source` being §4b geometry. `fullScreenCover(isPresented:onDismiss:content:)` fills the content area, dims nothing (there is nothing showing through) and cannot be dragged. `presentationDetents(_:)` / `(_:selection:)` size a sheet: `.medium`, `.large`, `.fraction(_:)`, and `.height(_:)` in **Int rows** (a terminal has no `CGFloat`); the fraction is floored, once. The height belongs to the sheet's own **box** — SwiftUI's sheet is a card with its own material, so its detent is always visible as that card, whereas a terminal sheet has no material and the content IS the sheet, so the outermost container in it (`Dialog`/`Panel`/`Card`/`.border()`) renders that tall and encloses the slack as empty interior. Fillable content (a `List`, a `Spacer`) fills it as its available height; content with no box keeps its own size, since there is nothing to stretch. Read off the sheet content's **outermost** view — the same rule as `.alignmentGuide`, and for a harder reason: the detent IS the height being rendered into, so it has to be known before the subtree renders, which rules a preference out. **A terminal has no grabber to drag**, so a multi-detent sheet moves between its detents through the `selection:` binding; without one the smallest applies, which is SwiftUI's own initial state. That makes the detent SET inert for anything past the first — every extra detent is unreachable unless the app builds its own control — so this is currently a parity shim rather than a feature. `Documentation/Drawers-sheets-and-slideovers.md` drafts the way out (a grabber that snaps to detents, and a resizable drawer built on the split-view machinery) and is awaiting decisions. `confirmationDialog` **shipped** — an action sheet (centred dimming overlay, ESC-dismiss, `titleVisibility`) with **vertically-stacked** buttons and the `.cancel` role sorted last; it reuses the alert host via a `verticalButtons` flag + a new `AlertButtonColumn`. `popover`/`fullScreenCover` ≈ `modal` variants; detents → fractional-height modal. |
| **`.scrollPosition` (bindable scroll state)** | Observable/bindable scroll position. | **Shipped**, both directions. `ScrollPosition` + `.scrollPosition(_:anchor:)` and `.scrollPosition(id:anchor:)`; `scrollTo(id:anchor:)` / `(edge:)` / `(y:)`, `viewID(type:)`, `edge`, `isPositionedByUser`. Writing rides the same seek machinery `ScrollViewProxy.scrollTo` drives, so a row request lands the frame it is made; an edge or offset moves the view before the content renders (`.bottom` via the tail-seek flag the End key raises, so the glue pins it against the real height). **Reading needed a new channel**: a seek matches on a stringified key, which is one-way — so `ForEach` now publishes the id VALUE alongside the key (`ChildViewCollection.anyID(at:)`), and the windowed stacks report the row under the anchor. The sample is the first row a person can actually SEE, not the one the "N more above" indicator is covering. A request is acted on once (a token, or the value differing from what was last reported), so scrolling away by hand sticks; the write-back only fires when the row changed, or a render-time write would re-trigger itself every frame. `ScrollPosition` is not `Sendable` (an `AnyHashable` is whatever the app's id type is) and has no `CGPoint` form — `scrollTo(y:)` takes `Int` rows, and there is no horizontal seek (the machinery rides the vertical row-windowing handshake). Remaining: `.id(_:)`-tagged arbitrary (non-`ForEach`) targets.

**`defaultScrollAnchor(_:for:)` + `ScrollAnchorRole` ship** beside it, and the pair divides as *where you are* versus *what you are holding onto*. `.scrollPosition` is a POSITION: seek there now, read back where you ended up. An anchor is a POLICY: what survives the data changing underneath you. Reaching for the first when you want the second is the easy mistake, and it is silent — a seek lands once and then the next append walks away from it.

The role names which of two questions an anchor answers: **`.initialOffset`** (where the view opens) and **`.sizeChanges`** (what it holds as its content grows). The unlabelled form answers both, as SwiftUI's does. Splitting them is worth having on its own merits — `.bottom, for: .initialOffset` is "join the log at the end, then leave me alone", which had no spelling — but it had to be done without disturbing `Documentation/Scroll-anchoring.md` §1.1, and the shape of the implementation is a consequence of that. TUIkit's follow is **positional**: being at the tail *is* the engagement, with no stored flag, and the opening placement is that rule's own first frame (a view with no content yet is at its own bottom). So the split is not an extra seek; it is one sentence — *the opening frame consults the opening anchor, every frame after it the standing one* — which for any view that used the unlabelled modifier substitutes a value for itself and cannot change anything. Both the environment key and the handlers' captured mode are **optional-with-a-third-state** for the same reason `Text`'s stated font is: "nobody stated an opening role" must defer to the standing one, or a direct write of `\.defaultScrollAnchor` (the spelling that predates the roles) would silently stop opening at its edge. And `for: .sizeChanges` *transforms* the opening key rather than assigning it — stating "none" only where none was stated — so the two role calls compose in either order.

**Omitted: `ScrollAnchorRole.alignment`** — where content sits when it is *smaller* than the viewport — and deliberately omitted rather than accepted-and-ignored, so SwiftUI source using it fails to compile instead of silently doing nothing. It is **deferred, not refused**: by this file's own test a refusal must name something a cell grid cannot do, and a cell grid can perfectly well align short content. What it needs is a content-placement offset in the render path plus every consumer that maps a screen row back to a data row — hit testing, click-to-select, drop slots, focus reveal — taught about it. That is a feature, not a spelling.

**Two deviations, both from scrolling in rows rather than points.** The anchor **quantises to three edges**: `y ≥ 0.75` is the bottom, `y ≤ 0.25` the top, and anything mid-content anchors *nothing* — SwiftUI's `.center` keeps the centre fixed, here it means "no anchor". And **`x` is ignored**; horizontal scrolling exists, but the anchor modes are defined over rows.

**`.anchorPosition(_:)` is TUI-specific and stays that way** — not a stopgap for something SwiftUI does better, but a capability SwiftUI has no spelling for, in the same category as `MenuStyle.inline` and `.onMenuOpen(_:)`. Two things block folding it into the SwiftUI surface. **Row anchoring is an identity policy and SwiftUI's anchors are positional**: a `UnitPoint` cannot name a row, and the two are provably not interchangeable — on an append `.bottom` re-targets to whatever the last row now is, while `.row(lastID)` pins that row and lets new ones arrive below it; a prepend leaves `.top` on the new first row and `.row(firstID)` on the old one. `ScrollPosition(id:)` does not rescue it either, being a seek rather than a standing hold. **And the anchor mode is BOUND, not merely declared**: `defaultScrollAnchor` is one-way in both frameworks, but §1.2's shadow modes, §1.3's user restore and §1.4's code-side restore all run through the binding — the read-back is what makes "am I still following the log?" answerable as `anchor == nil`, `.window`-vs-`nil` is what makes a release observable, and writing `nil` *is* the restore. SwiftUI offers nothing here; `isPositionedByUser` is one Bool that says the user moved it, not which policy now holds. |
| **Viewport windowing for a nested `LazyVStack` + `pinnedViews:`** | A `LazyVStack` that is the *direct* content of a `ScrollView` now windows to the viewport (§2.8) — the offset-publishing + render-only-visible policy landed. Remaining: a `LazyVStack` nested *below* other scroll content isn't at the content origin so it can't map the offset yet, and `pinnedViews:` is still absent from the lazy inits. | Thread the stack's own y-offset within the scroll content so a non-top stack can window too; `pinnedViews` then composites the active `Section` header over the viewport top. |
| **`@FocusState` as a property wrapper** | *(shipped)* `@FocusState var x: Bool` / `var f: Field?` + `.focused($x)` / `.focused($f, equals:)` + `.defaultFocus($f, value)`, matching SwiftUI. The value is derived from the persistent `FocusManager`; the imperative handle formerly called `FocusState` is now `FocusReference`. Remaining: `@FocusState` on multiple focusables in one `.focused` (SwiftUI binds a single control), and re-applying a default when a dismissed focus scope re-appears. |
| **`.keyboardShortcut` (general key equivalents)** | Bind an arbitrary key to any action. | The SEMANTIC actions shipped: `.keyboardShortcut(.defaultAction)` makes a Button the default (Return/Enter fires it whenever the focused control lets the key fall through — a `TextEditor` keeps its newline, a list keeps its row activation, a submit-less `TextField` lets Return through) and `.cancelAction` binds Escape. Arbitrary equivalents **shipped** too: `.keyboardShortcut("s", modifiers:)` with `KeyEquivalent` and `EventModifiers`. A terminal reports Control, Option and Shift but never ⌘, so the SwiftUI default `modifiers: .command` is remapped at registration to whatever the TUI-specific `.commandKey(_:)` names — `.control` (default), `.option`, `.bare`, or `.unavailable` — which is what lets one `View` source carry ⌘-shortcuts under both frameworks. Shift on a printable key is the character's CASE, not a modifier bit (that is all a terminal sends), and Control shortcuts on `c i j m z [` are undeliverable because the C0 range spends those bytes on Tab/Return/Escape and job control — see `KeyboardShortcut.isDeliverableInTerminal`. |
| **List editing: `onDelete`/`onMove`, `.listRowInsets`/`.listRowBackground`/`.listSectionSeparator`** | Editable lists. | `EditMode` + `\.editMode` + `EditButton` **shipped**, and `ForEach.onMove(perform:)` / `onDelete(perform:)` now **shipped**: attach the actions to a `ForEach` inside a `List` and press **Delete**/**Backspace** on the focused row to delete it, or drag a row with the mouse to reorder it (mirroring SwiftUI's drag trigger; `.rowReorderFeedback(_:)` chooses live-shuffle / dimmed-at-the-slot / row-on-the-pointer feedback). `move(fromOffsets:toOffset:)` / `remove(atOffsets:)` collection helpers ship alongside (constrained `Self.Index == Int` so they beat the Foundation⇄SwiftUI cross-import overlay's own unlinkable copies). Wired for a homogeneous all-content `List { ForEach … }` (a Section-nested ForEach is the known follow-up). **`.listRowInsets(_:)` and `.listRowBackground(_:)` shipped.** Insets are padding around the row's content (`nil` = the list's default, i.e. the identity — NOT zero), and the rest of the list still sees a full-width row. A background fills the **row**, not the text: the full width offered, every line of a multi-line row, with the content composited over it and the content's hit regions kept, so a button in a backed row is still clickable. There are two overloads because **TUIkit's `Color` is a value, not a `View`** (a palette is a table of them; cells are painted with them, not composed of them) — the generic `<V: View>` one SwiftUI has, plus a `Color?` one so `listRowBackground(Color.red)` compiles and means the same thing, exactly as `background(_:)` already does. A selected row still draws the selection highlight over the background, as in SwiftUI. `.listRowSeparator` / `.listSectionSeparator` remain inert stubs: the terminal `List` draws no per-row rules to show or hide. |
| **Common modifiers: `.opacity`(View), `.truncationMode`(View), `.onSubmit`, `.refreshable`, `.contextMenu`** | Frequently used; each terminal-expressible. | `.id(_:)`, `.focusable(_:interactions:)`, `.searchable(text:placement:prompt:)`, `.onSubmit(of:_:)`, `.tag(_:includeOptional:)` and `.contextMenu(menuItems:)` **shipped** — `.contextMenu` is a right-click (or Ctrl-click, where a terminal swallows right-click) pop-up of `Button`s anchored at the click point, dismissed by selection, Escape, or an outside click; a right-click bubbles to an ancestor menu when a child doesn't handle it (the input dispatcher was extended to bubble the secondary button like the wheel), and reliable right-click needs Apple Terminal / Ghostty / Warp (iTerm2 claims it by default — see Terminal-compatibility.md); the TUI-specific `.onMenuOpen(_:)` reports a pop-up (a `contextMenu` or a `Menu`) OPENING to any view above it, which is how an app clears whatever the last choice left on screen so choosing the same item twice reads as two choices — SwiftUI has no equivalent, its menus being system-drawn. **`.menuActionDismissBehavior(_:)` shipped**, with `MenuActionDismissBehavior` (`.automatic`/`.enabled`/`.disabled`) — the switch between a menu of COMMANDS, which closes behind a choice, and a menu of SETTINGS, which should not make you re-open it after every flip. It rides the environment, so it scopes to whatever subtree it is written on: on the `Menu` it governs every item, on one `Button` only that item, which is how a sticky toggle and an ordinary `Done` share a menu. `.automatic` is SwiftUI's deferral to "the policies of the component", and every menu a terminal draws has the same policy, so it resolves to dismissing — but the three spellings stay distinct rather than collapsing `.automatic` into `.enabled`, and the resolution lives in one computed property instead of a `!= .disabled` at the call site. One deviation, deliberate: `.disabled` is `@available(macOS, unavailable)` in SwiftUI — a Mac menu always closes behind a choice — so a desktop terminal has no platform behaviour to copy for the stay-open case, and TUIkit defines one. A **press-and-hold** release closes the menu whatever the behaviour says: `.disabled` keeps a menu up for more CLICKS, and a held gesture has no second act — the button is up, the tracking session that opened the menu is over, which is also how AppKit ends every menu session. A click on a row of an already-open menu still leaves it up. It reaches only menu ITEMS: Escape and an outside click still close an open menu, and an `.alert`'s buttons are unaffected — they answer a question rather than issue a command, and the internal channel `Button` consults happens to be shared by both presentations, so the alert re-asserts `.enabled` on its own subtree. — `.id` splices a keyed identity step (resets `@State`, re-fires `onAppear`/`task`, drops the cached buffer); `.focusable` makes any view a Tab stop + click-to-focus (`.activate`) and lets `.focused($x)` bind to a plain view; `.searchable` composes a glyph + bound `TextField` above the content (filtering is app-driven; `placement` is inert in a terminal, but the TUI-specific `.searchFieldIconPlacement(.leading/.trailing)` moves the magnifier and swaps it 🔎↔🔍 so its lens faces the field). **`.searchSuggestions(_:)` and `.searchCompletion(_:)` ship**, feeding the combo-box drop-down `.textInputSuggestions(_:)` already had — the same `DropdownMenu` the `Picker` uses — so a suggestion is a `Text`, a view carrying a completion, or a `Divider`, and the menu opens on demand (Down at the caret, or the `▾`) rather than on focus. They reach the SEARCH field only: the suggestions arrive on an environment key of their own and are handed to that one field, because sharing `\.textInputSuggestions` would silently arm any `TextField` the caller happens to have in the content. With no `.searchSuggestions` of its own the field inherits an outer `.textInputSuggestions` like any other text field. **Omitted: `searchSuggestions(_:for:)` and `SearchSuggestionsPlacement`** — SwiftUI has two places to put suggestions (a menu, or the content below), so it needs a per-placement visibility; a terminal has the drop-down, and honouring one case of that OptionSet while ignoring the other is the partial-seam shape this file declines elsewhere. And the two companions ship as well: `\.isSearching` is true in the CONTENT while the field holds the keyboard, and `\.dismissSearch` empties the query and hands the keyboard back — SwiftUI's also takes the field away, which here it cannot, the field being part of the layout rather than presented into a navigation bar; `.onSubmit(of:)` cascades a submit action through the environment (`.text` for `TextField`/`SecureField`, `.search` for the `.searchable` field) and composes additively with a field's own `.onSubmit(_:)` closure — the combined action stays nil when empty so Return still falls through to a default button, and `TextEditor` doesn't submit (Return = newline); **`.submitLabel(_:)` is deliberately ABSENT** — it names an on-screen keyboard's Return key, and a terminal has neither. It shipped first as a value stored in the environment that nothing read; that is the stub shape rule 2 forbids, so `SubmitLabel`, the modifier and `\.submitLabel` were all removed and the call now fails to compile. The behaviour it travels with, `.onSubmit`, is fully implemented. **The substitute was evaluated and declined**, so it is settled rather than pending: a status-bar hint ("⏎ Send") while the field holds focus, riding the per-focus-section registration `StatusBarState` already has. It fails on four counts — a `StatusBarItem`'s identity IS its shortcut and the merge drops globals sharing one, so it would evict an app's own "⏎ select" item on focus and restore it on blur; it could lie, because Return only submits when an action exists (`combinedSubmitAction` returns `nil` otherwise, on purpose, so Return reaches a dialog's default button) and a label with no action would advertise "Send" while Return fired "Cancel"; items joining and leaving on every Tab churn the bar and can flip it into compact rendering at narrow widths; and `\.statusBar` is Optional, so it would be inert in an app that does not use the bar. If it is ever wanted, the shape is opt-in app-level chrome — a TUI-specific `.submitLabelHint(_:)`, default off — which makes `.submitLabel` data the app chooses to render and the collision the app's own decision. The full reasoning is the `why` on `SubmitLabel` in `parity-map.json`, where `--stale` keeps it honest. **`.truncationMode(_:)` on `View` shipped** — the cascading one; `Text` and `TableColumn` had their own all along, and a `Text`'s own still wins inside a subtree that cascaded a different mode (`TextStyle.truncationMode` became Optional so "this view was told" and "nobody said" stay distinguishable). It applies wherever text is clipped, not only under a line limit. **`.lineLimit(_:)` on `View` shipped** — the cascading one, alongside `Text`'s own. It needed a decision `.truncationMode` did not: SwiftUI's `.lineLimit(nil)` means *unlimited*, which a plain `Int?` cannot distinguish from *unset*, and getting that wrong makes an inherited limit unresettable. So what is stored is a `LineLimit` (`.unlimited` / `.lines(_:)`) and the `Optional` around it carries "was one stated" — the modifiers still take `Int?`, matching SwiftUI. Both passes resolve it the same way, so a cascaded limit caps the measured height as well as the rendered one. **`Text.bold(_:)`, `.italic(_:)`, `.underline(_:)`, `.strikethrough(_:)` shipped** — and needed a model change first, recorded until now as §9 of `Parity-decisions-pending.md`. `TextStyle`'s emphasis flags were plain `Bool`, so a `Text` could not tell "I said no" from "I said nothing", and the merge against the style cascade could only be an OR — an attribute any layer could turn on and none could turn off. The five flags a cascade can also state are now `Bool?` and the merge is nearest-wins, which is SwiftUI's rule; `isBlink`/`isInverted` stay plain, having no cascade to disagree with. The change was behaviour-neutral on its own (nothing could produce a stated `false` yet), which is what let the parameters follow as a separate step. SwiftUI's `color:`/`pattern:` arguments are omitted: a terminal draws one underline in the text's own colour, so accepting them would be accepting something it cannot honour. `.dim(_:)` takes the parameter too, though SwiftUI has no faint attribute — but note it cannot decline `View.dimmed()`, which is a buffer post-processor rather than a cascade entry. **`Text.font(_:)` and `Text.fontWeight(_:)` shipped** beside them, and they are not redundant with the `View` spellings: `Text + Text` folds both sides into ONE view, so a font that lived only in the environment is gone by the time the joined text renders — `Text(name) + Text(" edited").font(.caption)` needs the caption to travel *with* the fragment. So a font is carried per run and each fragment resolves its own cascade, which is what also lets a theme's `.style(.font(.caption))` reach one half of a concatenation and not the other. It cost the same shape of model change as the flags above: a `Text`'s stated font is `Font??`, because `\.font` is itself `Font?` and "no font" is a value that key can hold — collapsing the two would make `Text(x).font(nil)` indistinguishable from silence, and the existing test that an inherited font can be escaped from is what proves it. `Text.fontWeight(.regular)` is a *statement* and so clears a cascaded bold, which is the tri-state paying for itself; `nil` leaves the inherited weight alone, as in SwiftUI. A fragment's font cannot change the case transform — the wrap runs on the whole string before the styling is re-applied, so `textCase` stays a property of the text. **`.lineLimit(_:reservesSpace:)` shipped** — and it did not belong with the range forms this section used to lump it in with. Reserving space is not about a growing text field: it makes a `Text` occupy its limit whether or not it needs it, which is the fix for a column of rows that shuffles as one subtitle wraps and another does not. `reservesSpace` rides ON the limit (`LineLimit.lines(_:reservesSpace:)`) rather than cascading beside it, so a descendant stating a new limit states a new reservation too; the floor is honoured only as far as the parent allows, so a squeezed text draws what fits rather than spilling out of its box. **The range overloads (`PartialRangeFrom` / `PartialRangeThrough` / `ClosedRange`) remain omitted**, and now for a stated reason rather than by association: SwiftUI documents them as sizing a growing `TextField`/`TextEditor` between a minimum and a maximum, and a terminal text control is laid into the rows its frame gives it — shipping the spelling would compile and then mean something different for the two views it exists for. A `Table` column keeps its own `lineLimit` — its cells are values, not views, so nothing cascades into them. **`.opacity(_:)` on `View` shipped** — see §1. **`.border` reshaped to SwiftUI's spelling** — `border(_ colour: Color, style: BorderStyle? = nil, width: Int = 1)`, so `.border(.red)` compiles and means what it says. The colour used to sit behind a `color:` label with the box-drawing style in the unlabelled slot, which made the one call SwiftUI teaches a compile error. The terminal-only part is ADDED beside it, not substituted: `style:` picks the characters, and `width:` is a count of concentric rings because a cell grid has no fractional stroke (0 draws none). A second overload `border(style:width:)` names no colour and lets the palette decide — no SwiftUI equivalent, since SwiftUI has no palette, and it is what most call sites want. **`.refreshable(action:)` shipped**, with `RefreshAction` and `\.refresh`. SwiftUI triggers it by pulling the content past its top edge; a terminal reports discrete wheel clicks rather than a continuous rubber-banded drag, so "how far past the top" is not a quantity that exists and the trigger is <kbd>Ctrl</kbd>-<kbd>R</kbd> instead — Control being the only modifier a terminal reports on a letter. A second <kbd>Ctrl</kbd>-<kbd>R</kbd> during a refresh is consumed rather than queued, as SwiftUI likewise will not start one over another. While it runs, an unlabelled ``Spinner`` **overlays** the content's top row rather than insetting it: `.overlay` sizes to the larger of the two, so a labelled spinner would widen narrow content the instant a refresh began — the reflow the overlay exists to avoid. It is drawn with one blank cell either side, so it reads as a badge sitting on the content rather than as a glyph that has collided with the word beside it. WHICH spinner is a subtree setting, through the TUI-specific `.refreshIndicator(style:color:)` — SwiftUI's indicator is not configurable, but there its look is a platform given, whereas here a spinner is a handful of glyphs whose legibility depends on the terminal's font: the `.dots` default is Braille, and a font without that coverage wants `.line`, which is pure ASCII. The action is published to the subtree as `\.refresh`, so a "Reload" button anywhere inside runs the same refresh, and `nil` is how a view tells it is not inside anything refreshable. `RefreshAction` is `Equatable` by the action's reference identity — closures cannot be compared, but two handles to the same `.refreshable` are the same thing, which is what makes `onChange(of:)` on it mean anything. **`.transaction(value:_:)` shipped**, beside the unscoped `.transaction(_:)`. SwiftUI applies the transform to updates CAUSED BY the value changing; it can, because its dependency graph knows which node produced the value. This framework re-evaluates bodies each frame and has no such graph, so what it asks is whether the value differs from the last frame's — the same answer whenever the change that moved the value is the change being rendered, which is essentially always. They part only when several changes coalesce into one frame, and **nothing could be exact there**: a frame carries one transaction, and that collision already has a stated rule (the last animated change of a frame is the one that runs). So the extra precision would have nowhere to go even if it were available — an approximation by measurement, not a deferral. The first render applies nothing, as `onChange` without `initial:` reports nothing. **`.onGeometryChange(for:of:action:)` shipped**, in both the one- and two-argument forms. The difference from `GeometryReader` is which view's geometry you get, and it is the whole point: a reader is GREEDY — it fills what it was offered, because it must know its size before it can build the content that would otherwise determine it — so wrapping something in one to measure it changes the layout you were measuring. This reports the size the view actually came out at and leaves it where it was. It fires on the first render as well as on changes, since a report that only ever arrived on the second size would leave an app that never resizes knowing nothing, and only on the render pass. The proxy is the terminal one — `size` and a `.local` frame are exact, `.global` only where the renderer knows where the view sits — so a value derived from a `.global` frame inherits that caveat. **`.tag(_:includeOptional:)`** completes the tag spelling. A container matches a tag by casting it INTO the selection’s type — `as?` promotes a value to its Optional as a language rule — so `.tag(Speed.slow)` has always matched a `Binding<Speed?>`; the parameter defaults to `true` and names that. `false` withholds the promotion, which is what lets a row tagged `nil` mean “no choice” without a bare tag shadowing it, and it withholds only the promotion: an exactly-typed selection still matches. Note the mechanism, because the obvious alternative is wrong — comparing two `AnyHashable`s instead is false whenever the two sides were erased from different static types, and true only by accident for types carrying an ObjC bridge (see the `TabView` note in §1, Containers). (`.multilineTextAlignment` shipped — §1.) |
| **Scoped wrappers: `@SceneStorage`, `@FocusedValue`** | binding into scoped state. | `@Bindable` **shipped** (derives a `Binding` into an `@Observable` reference you already own; not a source of truth, so it holds no storage and takes no part in render-identity binding). **`@SceneStorage` shipped.** SwiftUI draws the line by scope — one value per app vs one per window — which is real with several scenes and meaningless with one, and a terminal app has exactly one. So the two differ here in the single respect that survives that: the **namespace**. Scene state is written under a `scene.` prefix, so `@SceneStorage("tab")` and `@AppStorage("tab")` are different values rather than the same one under two names, and choosing between them stays a statement of intent — "where the user was" vs "what the user chose". SwiftUI does not promise scene storage survives a relaunch (the system may discard restoration state); TUIkit's does, because it shares `@AppStorage`'s backend — relying on that is still unwise, for SwiftUI's own reason. `@FocusedValue` is niche. |
| **Env values: `\.layoutDirection`, `\.dynamicTypeSize`, `\.scenePhase`** | Standard environment reads. | `\.openURL` (via `Link`) and `\.locale` **shipped** — `\.locale` is a stored, settable key populated each frame from the app language (single source of truth), so overriding it with `.environment(\.locale, _)` re-locales the number chrome in `Table`/`List`/`ScrollView`. **`\.verticalScrollIndicatorVisibility` / `\.horizontalScrollIndicatorVisibility` shipped**, with `View.scrollIndicators(_:axes:)` — which REPLACED the old `.scrollbarVisibility(_:)` spelling rather than sitting beside it (pre-1.0, no shims). Two keys because the modifier takes an axis set, and a view scrolling both ways must be able to show one bar and not the other; the modifier TRANSFORMS them rather than setting them, so two axis-specific calls compose instead of the second resetting the first. `ScrollIndicatorVisibility` carries SwiftUI's name and case names, and `.never` was added to it: SwiftUI separates `.hidden` (a request a platform convention may override) from `.never` (unconditional), and since nothing in a terminal can override a hidden bar the two behave identically — the case exists so the source compiles and means what it says. **The default is `.automatic`, as SwiftUI's is.** It once was `.hidden`, because `.automatic` has to MEASURE a view's content to learn whether it overflows and that walk would land on every app that never asked for a bar — but that was answering the wrong question with the visibility. The visibility says WHETHER an indicator is shown; **which one is a separate, TUI-specific setting, `\.scrollIndicatorStyle` / `View.scrollIndicatorStyle(_:)`**, over `ScrollIndicatorStyle.scrollbar` (the default, a column beside the content) and `.text` (the "▲/▼ N more lines above / below" lines, which spend a viewport line instead and have no horizontal form). Only the bar style measures — under the default `.automatic` the text indicators gate themselves after the render on what is actually hidden, and under `.visible` they reserve both lines at every offset instead, so that the content area does not resize as the view scrolls (`d1c54212`, 2026-09-08) — so `.automatic` costs nothing in a subtree that asked for the text form or for nothing at all, and `.hidden` now means no indicator rather than "no bar, fall back to the text". SwiftUI's soft-deprecated `ScrollView(showsIndicators:)` parameter is **not** carried: it was a second, hidden answer to the question the visibility already answers, which is the confusion this split exists to end. **`\.calendar` and `\.timeZone` shipped** beside it — three keys rather than one because they are three questions, and `DatePicker` needs the last two: it does its stepping and clamping through `\.calendar`, in `\.timeZone`, so a subtree can put a field in another calendrical system or another zone and the arithmetic follows. Where a `Calendar`'s own zone and `\.timeZone` disagree the environment's wins, because `\.timeZone` is the value that exists to say which zone the interface is in. `\.locale` deliberately does NOT reach the field: it would reorder the components under the caret, and the typing model depends on the columns holding still. **`.transformEnvironment(_:transform:)` shipped** — the modifier for a value that has to be DERIVED from the inherited one, which `.environment(_:_:)` cannot express: what is inherited is not known where the view is written, so the closure runs when the subtree renders. It resolves to a plain injection at that point and hands the work to the same modifier `.environment` uses, which is what keeps the render cache's environment-change detection working underneath it. It runs on both walks, so the closure has to be a pure function of the value it is handed. **`\.scenePhase` shipped**, published each frame from the run loop's own state (the `\.locale` treatment: one source of truth, not a value each view guesses). One transition is real in a terminal and it is the one worth having: **suspend**. <kbd>Ctrl</kbd>-<kbd>Z</kbd> / `SIGTSTP` renders a frame at `.background` BEFORE stopping — so an `onChange(of: scenePhase)` observer runs while the process is still alive, which is an app's only chance to save on the way down — and `.active` again on resume. **`.inactive` is never reported**: detecting "visible but not focused" needs the terminal's focus-reporting mode (`CSI ?1004h`), which TUIkit does not enable, and a value that could only be guessed at is worse than one that never appears. The case exists so a `switch` written against SwiftUI compiles. Size-class concepts map loosely to terminal dimensions. (`\.isEnabled` present — §1.) |
| **Text richness: `LocalizedStringKey`, `AttributedString`, Markdown, `Text + Text`** | Formatting & localization. | `Text(_:format:)` **shipped** (formats eagerly with the format style's own locale — env-`\.locale` re-resolution is a separate, tracked item below). **`LocalizedStringKey` shipped**, with SwiftUI's rule intact: a string *literal* is a lookup key, a `String` you computed is content, and `Text(verbatim:)` opts out. That split is not magic — it is overload resolution, and it needs `@_disfavoredOverload` on the `StringProtocol` initializer to work, because `String` is a string literal's default type and would otherwise always win. (SwiftUI marks its own the same way; without it a literal is simply never looked up, which is what the first draft here did.) Lookup goes through `LocalizationService`, which falls back to English and then to the key itself, so adopting this changed nothing measurable: all 1170 registered keys are dot-separated, none of the 210 `Text("…")` literals in the shipped sources collides with one, and the three Stress scenarios render byte-identical checksums before and after at no measurable cost. An interpolated literal becomes one key with `%@` per value (`"Moved \(n) rows"` → `"Moved %@ rows"`), which a translation can reorder with `%2$@`; values are stringified **eagerly**, as `Text(_:format:)` formats eagerly, and `\(value, format: .percent)` works. A key with no interpolations is never scanned for placeholders, so `Text("100% done")` says exactly that. SwiftUI's `tableName:bundle:comment:` are absent — TUIkit's localization is a registered dictionary with no bundles or tables to name. **The key overload now reaches every control and modifier that takes display text**, not only `Text` — `Button`, `Toggle`, `TextField`/`SecureField`, `Picker`, `Stepper`, `Slider`, `DatePicker`, `ColorPicker`, `Section`, `Menu`, `Label`, `LabeledContent`, `Link`, `NavigationLink`, `ProgressView`, `Gauge`, `Spinner`, `ContentUnavailableView`, `RadioButtonItem`, `Tab`, `TableColumn`, `List`/`Panel` titles, and `navigationTitle`, `alert`, `confirmationDialog`, `searchable(prompt:)`, `badge` and `listEmptyPlaceholder` — **and the TUI-specific chrome that has no SwiftUI counterpart**: `Dialog(title:)` (including `.doubleLine`/`.heavy`), `Alert(title:message:)`, `Card(title:)`, `StatusBarItem(label:)`, `QuitShortcut(label:)`, `ColorPickerPanel`/`GradientEditorPanel` titles, `imagePlaceholder` and `NotificationService.post`. Until then only `Text` and `DisclosureGroup` took one, which made the documented rule false everywhere else and — worse — made it false SILENTLY: `Button("button.save") { … }` is exactly what SwiftUI source says, it compiled, and it printed the key. **The parity tool cannot see this class of gap**, because it keys on names and argument labels and both spellings are `init(_:action:)`; only the TYPE differed, and types are allowed to differ (a terminal counts cells where SwiftUI counts points). It was found by reading, not by the report. Each control gains a forwarding `LocalizedStringKey` initializer and its `String`/`StringProtocol` one gains `@_disfavoredOverload`. That attribute is load-bearing on BOTH shapes — mutation-tested — which is the part worth knowing: a concrete `String` parameter obviously beats `LocalizedStringKey` for a literal without it, but so does a GENERIC `<S: StringProtocol>` one, because `String` is a string literal's default type and binding `S = String` wins outright. "Concrete beats generic" is not the rule here. **The attribute turned out not to be sufficient either, on a concrete `String`, from Swift 6.3 on.** `Button`, `StatusBarItem` and `QuitShortcut` spelled their disfavoured twin `String` rather than `<S: StringProtocol>`; that shipped green and broke the day CI's Xcode 26 moved 6.2.4 → 6.3.3 — silently, exactly the way the original defect did, with `Button("button.save") { … }` printing the key again. Measured on both toolchains with a standalone probe: with `@_disfavoredOverload` present, a literal binds to the key overload on 6.2.4 in every shape, but on 6.3.3 a **concrete `String`** parameter can win back once the initializer takes another argument. Which shapes lose is not a tidy rule, and the attempt to state one as "any other required argument" is wrong: `Spinner(_:)`, `badge(_:)` and `listEmptyPlaceholder(_:)` are safe because the string is their only required parameter, but `Menu`, `Section`, `Picker`, `TextField`, `Panel`, `Dialog` and `Card` are *also* safe despite a required `@ViewBuilder` tail, because that tail returns a generic the solver must infer. **The worst part is that it is not a property of the declaration at all — it is decided per CALL SITE.** One declaration, `ColorPickerPanel.init(_:selection:isPresented:)`, verified by emitting SIL against the built library and demangling the initializer actually applied:

```
ColorPickerPanel("k", selection: binding,        isPresented: binding)          -> LocalizedStringKey
ColorPickerPanel("k", selection: .constant(.red), isPresented: .constant(true)) -> String        (!)
```

So a caller who changes a `Binding` to `.constant(…)` silently un-localizes a title, in code nobody touched. A **generic `<S: StringProtocol>`** parameter binds to the key overload on both toolchains in every shape and at every call site tested, including that one — which is the argument for spelling every one of these generic rather than auditing which are "currently fine". So the rule to write by is not "add the attribute" but "add the attribute **and** make the parameter generic" — which is also SwiftUI's own signature (`Button.init<S>(_ title: S, action:) where S: StringProtocol`), so the fix moved *toward* parity rather than away. The lesson worth keeping is that this defect class is invisible to the compiler and to the parity tool alike, and is caught only by the round-trip tests in `LocalizedTitleTests` — which is why they check both directions for every control, and why a control missing from them is the real risk. A generic parameter cannot carry a default argument, so `QuitShortcut`'s `label: String = "quit"` split into a separate `init(key:ctrl:shortcutSymbol:)`; its four presets, which spelled that default out as `label: "quit"`, now take it rather than asking for a `"quit"` key that was never in any table. Resolution is **eager**, at construction, exactly as `Text`'s is, so a control keeps storing a plain `String` and nothing about how it measures or renders changes; the tree is rebuilt every frame, so a language switched at runtime is picked up on the next one. Only *display text* is a key. A value being displayed is not: `LabeledContent(_:value:)` looks up the label and prints the value — and its `value:format:` overloads now ship beside it, so a form row showing a NUMBER does not have to interpolate one by hand (which is how a form ends up displaying `0.42857142857142855`); the format style carries its own locale, exactly as `Text(_:format:)`'s does, `Label(_:systemImage:)`'s symbol name is a symbol name, and a `Table`'s cells come from the data. `ContentUnavailableView`'s `description` IS one — an empty state is prose, and so is an `Alert`'s `message`, which is why that one takes two keys rather than a key and a value. Nor is a **glyph**: a `StatusBarItem`'s `shortcut` (`"q"`, `"⎋"`, `"⌃q"`) is the key you press, identical in every language, and the item derives its identity and trigger from it. Several signatures could not be optional or defaulted and stay unambiguous, so `Spinner(_:)`, `badge(_:)`, `Card(title:)`, `imagePlaceholder(_:)`, `ColorPickerPanel`/`GradientEditorPanel` and `QuitShortcut(label:)` take a non-optional, non-defaulted key beside their `String?`-or-defaulted form: `Spinner()`, `badge(nil)`, `Card { … }` and `QuitShortcut(key:shortcutSymbol:)` have nothing to look up. `StatusBarItem` is the case that proves `@_disfavoredOverload` is not merely tidying: it has two initializers reachable through defaults, and Swift's "fewer defaulted arguments wins" tie-break picks the `String` one over the key even so — mutation-tested. `Alert`'s `.warning`/`.error`/`.info`/`.success` presets were the last hold-out: they defaulted their titles to hardcoded English words, so a German app got a "Warning" alert. They now default to the framework's own `label.warning`/`.error`/`.info`/`.success` (the fourth was added to all seven tables), and — because the title is defaulted on BOTH sides of the pair — `Alert.warning(message: "alert.diskFull")` reaches the key overload while `Alert.warning(message: computedString)` reaches the string one and still gets the translated title. (The *mechanism* changed when the twins went generic, because a generic parameter cannot carry a default: the key overload keeps its defaulted title, and the disfavoured side's default moved into a separate titleless overload that forwards it — `QuitShortcut`'s split, eight more times. The behaviour above is identical, and the titleless overload needs `@_disfavoredOverload` of its own, or "fewer defaulted arguments wins" hands it `Alert.warning(message: "alert.diskFull")` and the message goes unlooked-up.) That symmetry is what makes the presets safe; giving only one of the pair a default would either break the computed-message call or leave the literal unlooked-up. Writing the tests for them turned up a separate defect in the same factories, now fixed: `Alert.warning(…) { … }` and `Dialog.doubleLine(…) { … }` did not compile at all. Each declared its OWN generic parameter — `static func warning<A: View>(…) -> Alert<A>` on `extension Alert` — so the *receiver's* `Actions` (or `Dialog`'s `Content`) appeared nowhere in the call and could not be inferred; you had to write an arbitrary `Alert<EmptyView>.warning(…) { Button(…) }`, which is not even well-typed as a statement of intent. They now use the type's own parameter (`actions: () -> Actions` returning `Alert`), so the closure determines it and the natural spelling works. The Example's doc strings had been advertising the spelling that did not compile. Adopting it changed nothing measurable, for the same reason it did for `Text`: keys are dot-separated, prose does not collide with one, and a missing key falls back to itself. An app that resolves its own strings and passes a computed `String` binds to the disfavoured overload and is unaffected — which is every call site in `Example` and `Stress`. **`Text + Text` shipped.** A concatenation is ONE `Text`, so it wraps, truncates, aligns and measures as a single piece of text — the fragments are styling, not layout, which is exactly what distinguishes it from an `HStack` of Texts. Each fragment keeps its own attributes and a modifier applied to the result becomes the base beneath them (`(Text("a").bold() + Text("b")).italic()` → both italic, only "a" bold), matching SwiftUI's precedence. A `Text` that was never concatenated stores `nil` rather than a one-element list and takes the original render path untouched: the three Stress scenarios render byte-identical checksums and sit inside run-to-run noise. **The interesting part is that the styling has to be re-applied AFTER the wrap** — wrapping must see the whole plain string or a break either side of a fragment boundary is chosen blind — so the render walks a cursor back through the source to re-attribute each wrapped line. That is only sound because the wrap preserves every non-whitespace character in order (it picks break points and drops whitespace at them; it never reorders, substitutes or invents), which is now a property test over ~5000 random strings × 7 widths rather than an assumption. Inserted chrome — a truncation ellipsis — is kept with the fragment being cut. Full `AttributedString`/Markdown is larger and remains out. |

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
| **Expand/collapse hierarchy** (`DisclosureGroup`/`OutlineGroup`) | click a disclosure triangle to expand a node | **Shipped**: `DisclosureGroup`, `OutlineGroup`, and `List(_:children:)` (§1, Containers). ▶/▼ toggled by Return or Space on the focused branch, and opened / closed by Right / Left wherever the triangle is — except a hierarchical `List`'s rows, where Space is the row's selection and the disclosure is Return's (and Right / Left's, or ⌥Right / ⌥Left for the whole subtree); with the mouse, a `DisclosureGroup` takes the whole row while an outline row takes only the **triangle** — because in a list the rest of the row is the selection's, and the two gestures cannot share it. A one-cell target being unkind, the triangle's button covers the blank cell either side, making it four cells wide. Content is indented into the label's column, so nesting draws a tree either way |
| **Type-ahead selection** in `Picker`/`Menu`/`List` | type a prefix to jump to a matching item | match typed characters against visible item labels to move the selection |

This table will grow as we notice more of SwiftUI's built-in behaviours.

### 4b. SwiftUI has it · TUIkit won't (bitmap vs. text-cell)

These are intrinsic to a *bitmap* renderer and have no faithful meaning in a grid
of character cells. **Verdict: don't add** (or add only a deliberately
reinterpreted, lossy analog, clearly named so no one expects fidelity).

> **Read these as claims, not settled decisions.** Four refusals in this file
> have now been overturned by examining them — `Image(systemName:)` (§2.4),
> `lineLimit(_:reservesSpace:)` (§1), and the two struck rows below — and every
> one failed the same way: a real terminal limitation, described accurately, then
> used to withhold a spelling it did not actually bar. A row here earns its place
> by naming what the API *would have to do* and why a cell grid cannot do it. If
> the reason is instead a true fact about terminals that the API never depended
> on, the row is wrong. Check before citing one.

| Feature | Why it can't transfer faithfully |
|---|---|
| ~~**`Font` / `.font` / weights**~~ **— WRONG; overturned in-tree** | `Font` **ships**: all eleven `TextStyle` cases, `.weight`/`.bold`/`.italic`/`.monospaced`, and both spellings of the modifiers — `View.font(_:)`/`View.fontWeight(_:)` and `Text.font(_:)`/`Text.fontWeight(_:)`, the `Text` pair being the one that survives a concatenation (§4a). The premise was sound and the conclusion was not — an app genuinely cannot set a typeface or a point size, but `.font(.headline)` never asked to. It asks for EMPHASIS, and the eleven styles collapse onto three intensity tiers a terminal can draw; carrying all eleven is what lets portable source compile unchanged. What does stay out is anything naming a metric: `fontDesign`, `fontWidth`, and any size in points. See §1. |
| ~~**Animation & transitions**~~ **— WRONG for four of the six; overturned in-tree** | `Animation`, `withAnimation`, `.transition` and `AnyTransition` **ship**: an animation is a sequence of discrete frames the run loop replays (`Documentation/withAnimation` design), which is exactly the tween space a cell grid does have — time, not sub-cell position. Still out, on the original reasoning: `matchedGeometryEffect` (sub-cell interpolation of geometry) and `PhaseAnimator`/`KeyframeAnimator` (recorded as a deliberate `notImplemented` in the parity worklog). |
| **Shapes & vector drawing** (`Shape`, `Path`, `Rectangle`/`Circle`/`RoundedRectangle`, `Canvas`, `GraphicsContext`, `fill`/`stroke`) | Vectors rasterize to pixels. Cells can only approximate with box-drawing/block glyphs (which `.border` already does for rectangles). |
| **Sub-cell geometry** (`.scaleEffect`, `.rotationEffect`, `.rotation3DEffect`) | Scaling and rotating by fractional points is undefined on a grid — a cell cannot be half a cell wide or turned 30°. **`.offset` was listed here and should not have been**: displacement is a MEASUREMENT, and this file's own guiding principle says a measurement is `Int` cells. `.offset(x:y:)` and `.offset(_:)` duly ship (whole cells, layout unaffected, as in SwiftUI; the terminal's lack of transparency forces two documented deviations — and the size-taking spelling takes a `CellSize`, the counterpart of the `CGSize` SwiftUI takes). `View.position(_:)` / `.position(x:y:)` are still absent but belong with them rather than here — absolute placement in cells is what the overlay layer already does, and the anchor flooring §2.2 describes is exactly the rounding it needs. |
| **Pixel filters** (`.blur`, `.shadow`, `.clipShape`/`.mask`) | These are per-pixel compositing ops. A cell is one glyph + fg/bg color; there's nothing to blur or feather. **The seven colour effects are NOT on this list any more**: `.brightness`/`.contrast`/`.saturation`/`.hueRotation`/`.colorInvert`/`.grayscale`/`.colorMultiply` **ship** (`ColorEffectModifiers.swift`) — they rewrite the SGR colours of the rendered cells, which is the whole of what those modifiers ask for, so the premise was one of this section's own "true fact about terminals that the API never depended on". **`.opacity` is the exception and shipped** (§1): alpha is the one filter a cell can express, because a cell's colours can be composited even though its glyph cannot — the subtree becomes a layer, and each cell is resolved against the cell beneath it. The glyph is the part that has to be decided rather than mixed, and it is decided by a threshold at ½. |
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
| `.focusHandoff(_:_:)` | where a control's focus goes when it is disabled, hidden or removed while focused, named by `@FocusState` value and followed along a chain. SwiftUI says nothing about where focus goes then; TUIkit's default is the control's neighbour in the ring, which is wrong for mirrored pairs like ◀ ▶ |
| `.palette` / `.appearance` (View **and** Scene), `SystemPalette`, `ColorDepth`, `BorderStyle` | ANSI theming + capability tiers |
| `.mouseSupport` (Scene) | opt into terminal mouse tracking modes |
| `.appHeader`, `.notificationHost`, `.modal` | out-of-tree surfaces + terminal modal |
| `.textCursor(_:animation:)`, `.indicatorAnimationSpeed(_:for:)` | text-field cursor shape/blink; how fast a caret, a focus emphasis, a spinner or an indeterminate bar animates, per kind |
| `.dimmed()`, `Text.dim()/.blink()/.inverted()` | ANSI display attributes |
| `.memoized(id:)` | reuses a subtree's previous *rendering* while a caller-supplied token holds. The token counterpart to `.equatable()`, which SwiftUI does have: `equatable()` PROVES a subtree unchanged with `==`, and this one takes the caller's word, which is the only option open to a view holding a closure (every `Button` action) or an `AnyView`. SwiftUI needs no such escape hatch because its diffing sees through the view graph the compiler builds for it; TUIkit re-runs `body` and compares values, so where equality is undecidable there is nothing to compare. Named apart deliberately — SwiftUI's nearest spelling, `.drawingGroup()`, is about compositing rather than caching. Inherits `EquatableView`'s storability gate, so an interactive or time-varying subtree is refused rather than served wrongly, and one buffer per memoized identity is released when the view leaves the tree |
| Image: `.imageCharacterSet`/`.imageColorMode`/`.imageDithering`/… | raster→ASCII conversion controls |
| `.terminalGraphics(_:)`, `.imageCellPixels(_:)` | whether an `Image` draws with the terminal's OWN graphics protocol (real pixels) rather than glyphs, and what cell size it is resampled to. SwiftUI has no counterpart because it has no fallback renderer to prefer over: here the glyph rendering is a look as well as a fallback, so an app built around `.blocks(_:)` or a `.customRamp` needs a way to keep it on exactly the terminals that could draw a photograph. Availability is a startup handshake, not this modifier — see §2.4 |
| `Card`, `Panel`, `RadioButton`/`RadioButtonGroup`, `Spinner`, `TrackStyle`, `IndeterminateStyle` | terminal-idiomatic containers/controls/styles |
| `MenuStyle.inline` (+ `.menuStyle(_:)`) | a `Menu` rendered expanded in place under its label, rather than collapsed behind it. SwiftUI has no inline menu style; a terminal app's landing screen often *is* a menu, and making the user open the only thing on the page would be perverse. The rows are the same `Button`s either way, and each prints its `keyboardShortcut` at its trailing edge (`^S` for Control, `M-s` for Option — not ⌃⌥, whose width is ambiguous). A menu taller than its space scrolls inside its border, with the focus reveal following the arrows. |
| `TrackStyle.custom(TrackConfiguration)` | fully-configurable progress/slider/gauge fill (glyphs, leading-edge ramp, patterned or solid background, gradient); the named styles are presets of it |
| `List`/`Table` `.onRowActivate(_:)`, `MouseEvent.clickCount` | row activation — double-click OR Return/Enter on the focused row (Space keeps selecting); the closest SwiftUI analogue is `contextMenu(forSelectionType:…primaryAction:)`. Terminals report no double-click, so the dispatcher synthesises `clickCount` by timing. The count keeps climbing while the clicks keep coming (each press extends the window from itself), so a row that has *opened* on its double-click ends the sequence: a burst opens once per PAIR of clicks, which is what drumming double-clicks to climb a directory tree means. `onTapGesture(count:)` sees the raw count, so a triple-tap is still reachable |
| `.radioButtonGroupEdgeBehavior(_:)` | what an on-axis edge-arrow in a `RadioButtonGroup` does: `.contain` (stay in the group, the default — like `List`/`Table`; use Tab to leave), `.escape` (relinquish to the next control), or `.wrap` (cycle within the group) |
| `RadioButtonItem(_:_:content:)` | an option that carries the controls that configure IT — how many greys, which two colours — drawn under its own option and indented to the label. SwiftUI's macOS radio group (`Picker` + `.radioGroup`) has no such thing, and the two ways of drawing it without one both cost something: a control beside the group leaves the reader to work out which option it belongs to, and a group per parameterised option costs the arrow keys that walk the options. Every option's content is DRAWN whether selected or not (so the rows an option occupies do not move as the selection does) but only the SELECTED option's is enabled — which is what makes the keyboard unambiguous: **Right**/**Tab** steps into the chosen option's controls because they are the only ones registered, and **Left**/**Shift-Tab** comes back. Same in-and-out shape as `DisclosureGroup` and `OutlineGroup`. |
| `.toggleContent(_:)` | the controls a `Toggle` GOVERNS, drawn under it and live only while it is on — the switch-plus-its-settings shape, which SwiftUI leaves to the caller to stack. Two things go wrong when it is stacked by hand, and both were live in the Example: the indent has to be the INDICATOR's width, and the indicator is a `ToggleCharacterSet` resolved against the terminal at render time (`■` one cell, `⬛︎` two, `[x]` three), so a hardcoded 2 lines the content up under the box on some terminals and past the label on others; and the content has to be disabled while the toggle is off, or the keyboard walks into settings for something that is not happening. Content is always DRAWN, on or off, so the rows below do not move as it is flipped. Same shape and same reasoning as `RadioButtonItem`'s per-option content. A custom `ToggleStyle` draws its own indicator, so there is nothing to measure and content under one is not indented. |
| Drag preview flights | the picture of a dragged row LEAVES the row it came from rather than appearing over the pointer already carrying it: ~120 ms lifting out of the row's own place to the cursor, and ~200 ms walking back when the drag is cancelled or the drop is refused (the row draws blank until it lands, so the same row is never on screen twice). SwiftUI's drag preview appears at the cursor. The lift is applied at the DRAW site only — `liftedPreviewFrame()`, not `previewFrame()` — so the frame a drop reports through `DropInfo` and the frame a cancel measures its walk home from stay the anchor math and nothing else. **A `Table` row's CELLS travel with it**: in the grid every cell is padded out to its column's width, in the hand nothing is padded and the gaps are two cells, and that difference used to happen between two frames. The drag carries the whole travel (`ActiveDrag.morph`, row layout first), the lift plays it forward and every flight plays it backward — including a SUCCESSFUL drop, which settles the picture where it already is (the slot is at the pointer and so is the picture) purely so the cells can spread back out into the row they are becoming. Both ends line up with what is on screen either side of them, which is what makes the jump gone rather than moved. |
| `ToneCurveEditorPanel` | a modal editor for `ASCIIToneCurve` — the "this tone becomes that colour" mapping `.imageToneCurve(_:)` applies. Two aligned strips read column by column (the tone arriving above, the colour leaving below) with a marker under each stop, so the mapping IS the picture. Distinct from `GradientEditorPanel`, and the distinction has narrowed to the one that matters: both are colours at positions now, but a gradient's positions are along the thing being PAINTED and a curve's are on the TONE axis of what is being sampled — same shape, different independent variable. `ASCIIToneCurve.Stop` gains `position` / `init(at:to:)` to say where a stop sits, and the curve gains `color(atTone:)` so an editor draws the renderer's own answer rather than a second copy of the interpolation. SwiftUI has no counterpart to either panel. |
| `ASCIIToneCurve.Channels` / `.Ramp`, `ChannelCurveEditorPanel` | a recolouring that answers each channel on its own terms — three transfer functions, the shape of a photo editor's per-channel Curves tabs. It says what a tone curve cannot, because a tone curve is by construction a function of luminance alone: colour casts, cross-processing, split tones, and a negative. `.inverted` WAS a `Bool` on the type for exactly that reason and is now three descending ramps, so the special case stopped being one. The editor draws a ramp as a filled plot (input left-to-right, output bottom-to-top, eight rows × eight sub-cell levels) — a fill rather than a line because a one-cell diagonal through a cell grid is a staircase with gaps the eye reads as data. What neither shape can say is a hue rotation; that needs a 3-D cube, and 35,937 entries is not something a terminal edits. |
| Image charsets `.ascii(glyphs:)` / `.unicode(glyphs:)` / `.blocks(_:)` / `.customRamp(_:)`, `.imageShapeAware(_:)` | raster→text rendering as three orthogonal choices: the fundamental charset, its size (the `glyphs` count picks the ideal calibrated subset; blocks use a discrete resolution), and shape-aware glyph matching (measured in-cell ink distribution; applies to blocks too via quadrants/halves/corner triangles) |
| `.imageSupersampling(_:)`, `.imageEdgeThreshold(_:)` | image-fidelity knobs: N×N area averaging of every sample for the non-shape renderers (1...4; nil = default; the shape matcher's 96-sample grid needs none), and the shape-aware ascii/unicode edge-glyph gradient threshold (lower = more edges; nil = pure coverage matching) |
| `.hidden()` — what a hidden view still does | matches SwiftUI: the subtree keeps its `@State`, fires `.onAppear`/`.task`, honours a `.keyboardShortcut` (the hidden-button-as-shortcut-holder idiom works), and a `.sheet`/`.alert` it presents still presents — a panel is drawn over the whole screen rather than by the view, so hiding the presenter cannot un-present it. What goes with the picture is what belonged to it: the view's cells, its clicks, its place in the focus ring, and any ANCHORED pop-up (a popover, an `.offset` child), which is the view's own drawing displaced. Implemented as focus SUPPRESSION (`\.isFocusSuppressed`, read by control registration and ignored by section registration) rather than the wholesale isolation `.dimmed()` uses — isolating sends a presentation's own section registration and `grabInput` to a throwaway, so the sheet would draw with nothing able to reach it. **`.dimmed()` is the deliberate contrast**: TUI-specific, no SwiftUI counterpart, and genuinely inert — no focus, no keys, no shortcuts, no presentation — because it exists to make content recede rather than merely stop drawing it |
| `.tabWidth(_:)` (`TabWidth.periodic`/`.fixed`) | tab-stop layout for literal tabs in `TextEditor` (default: snap to 4-column stops, like the text system's `defaultTabInterval`; SwiftUI exposes no tab control) |
| `.navigationSplitViewResizable`, `.navigationSplitViewColumnWidth`, `.fixedSize` on `List`, `.listEmptyPlaceholder` | terminal split/list affordances |
| `formRowAlignment(_:)` | per-row override of a `Form`'s column alignment |
| `.scrollChainingDelay(_:)` | grace period before wheel ticks blocked at a nested scroller's edge chain to the parent (default 2 seconds, counted from the first blocked tick; `.zero` chains immediately) |
| `.scrollGranularity(_:)` (`ScrollGranularity.line`/`.row`) | how finely `List`/`Table` viewports move through multi-line rows — by terminal line (default: tall rows scroll in gradually, partially clipped at the top) or by whole row (classic TUI jumps). It sizes a STEP and decides where the top may rest — under both, the row straddling the bottom edge is drawn as far as it fits, so the viewport always fills exactly. Selection/focus stay row-based; SwiftUI scrolls by pixels so the question doesn't arise there |
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
bitmap. §3 is now empty: the one divergence that stood there —
`foregroundStyle` taking `Color?` — is closed, and gradients ship. §4a — additive SwiftUI features a terminal can express — is now
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
