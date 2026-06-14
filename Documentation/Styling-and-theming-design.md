# TUIkit styling & theming — design

Status: **design agreed; implementation in progress (phased).** This document is
the reference for the styling/theming work: the model, the public API shape,
resolution rules, a SwiftUI comparison, worked examples, and the phased plan.

## 1. Goal & principles

Make *all* visual styling customisable through **cascading modifiers** that apply
to a whole subtree and can be overridden, at any level of specificity:

- **Broad**: "set the text colour to blue" → all text (plain `Text`, button
  labels, section headers, …) is blue.
- **Targeted**: "make *button* text bold", or more specifically "*default*
  buttons", or "*destructive* buttons" — every control and each visually-distinct
  mode can be addressed.
- **Per-instance**: any individual view can override, or deliberately *opt out*
  of a broad setting when usability demands (e.g. an error label staying red).

A **theme** is then just a convenient bundle of these customisations applied at
the root (or any subtree) — not a special mechanism — so it encourages app-wide
consistency.

Principles: **reuse the existing environment cascade**; **hew to SwiftUI** for the
broad/parity modifiers; keep TUI-specific extensions clearly separated; every
default is behaviour-preserving until something is customised. The end goal is
**comprehensive coverage of all built-in controls**, delivered across many small
commits.

## 2. What already exists (reuse, don't reinvent)

TUIkit already has the SwiftUI-style cascade this needs:

- `EnvironmentModifier` threads `EnvironmentValues` to **all** descendants through
  `RenderContext.environment` (TUIkitView/Environment/Environment.swift).
- Style values already cascade and resolve **explicit > environment > default**:
  `.foregroundStyle` (`ForegroundStyleKey`), `.palette`, `.appearance`,
  `.buttonStyle`, `.listStyle`, `.pickerStyle`, `.indeterminateStyle`, `.badge`, …
- Each control reads its style from the environment at render
  (`_ButtonCore` reads `context.environment.buttonStyle`, `_ListCore` reads
  `listStyle`, …) — see ButtonStyle.swift, ListStyle.swift.

So the architecture is already the architecture. This work **fills gaps** and adds
one unifying concept (the scoped cascade), rather than replacing anything.

## 3. The granularity model — a **scoped style cascade**

The heart of the design. One mechanism spans broad → specific.

### 3.1 `StyleAttributes` — a partial bag of styleable properties

All fields optional; `nil` means "inherit / not set at this level".

```swift
public struct StyleAttributes: Sendable, Equatable {
    public var foreground: Color?
    public var background: Color?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var dim: Bool?
    public var textCase: TextCase?            // .uppercase / .lowercase / nil
    // (extensible: border colour, etc.)

    /// `self` wins where non-nil, otherwise `base`. The merge primitive.
    public func merged(over base: StyleAttributes) -> StyleAttributes
}
```

### 3.2 `StyleScope` — *what* an entry matches

```swift
public enum StyleScope: Sendable, Hashable {
    case all                                   // everything
    case text                                  // any rendered text
    case semanticColor(SemanticColor)          // text drawn with a palette role,
                                               //   e.g. .foregroundSecondary
    case control(ControlKind)                  // any control of a kind
    case controlVariant(ControlKind, Variant)  // a specific mode, e.g. button .default
    case chrome(ChromeRole)                    // sectionHeader, sectionFooter, …
}

public enum ControlKind: Sendable, Hashable { case button, toggle, slider, picker, textField, list, stepper, … }
public enum ChromeRole:  Sendable, Hashable { case sectionHeader, sectionFooter, listRow, … }
```

A scope decides **which views an entry applies to** — its *reach*, not its
priority. (`.control(.button)` reaches every button; `.controlVariant(.button,
.default)` reaches only default buttons.) Scopes have a **specificity**, but — see
§3.4 — that specificity is used *only* to order entries that live at the same place
(within one `Theme`/`.style` call), **not** as a global precedence between
ancestors. Across the tree, position decides. `Variant` is typed per control
(§ "Variant", below) over a type-erased token in the scope.

### 3.3 The cascade environment value

```swift
extension EnvironmentValues {
    /// Scoped style entries contributed by ancestors, in application order
    /// (outermost first). Modifiers append; resolution walks it per the rules in §3.4.
    public var styleCascade: StyleCascade        // default: empty
}
```

### 3.4 Resolution — **proximity-dominant, per property**

This is the rule, and it matches SwiftUI's environment exactly:

> For each property independently, among all cascade entries whose **scope matches**
> the view, the entry applied **closest to the view in the tree wins** ("innermost
> wins"). Properties resolve independently, so a broad `.foregroundStyle(.blue)`
> changes only `foreground` and leaves a `bold` set elsewhere intact.

Full precedence for a property, low → high:

1. Framework default (`EnvironmentKey.defaultValue`).
2. Palette / theme baseline.
3. **Scoped cascade** — the innermost matching entry that sets this property.
4. The control's resolved `*Style`, **where it asserts the property** (load-bearing /
   semantic — see §3.5).
5. **Per-instance explicit** modifier on the view (`Text(…).foregroundStyle(…)`).

Step 4 sits **above** the soft cascade (3): a control's style may assert a property
(e.g. a destructive button's error-red) that the soft cascade must not silently
override. That's what keeps proximity safe — see §3.6.

**Within a single application point** — one `Theme` bundle, or one `.style` call
that targets several scopes — entries are ordered by **specificity** (broad first,
specific last) so the most specific wins *there*. Specificity is only this
within-bundle tiebreak; across tree depth, proximity decides.

### 3.5 Soft-default styles — the key to "broad reaches into controls"

For "set text colour blue → button labels go blue too", a control's default style
must **not** unconditionally paint its label. Styles are *partial*: they assert
only what's intrinsic and **inherit the rest from the cascade**.

- The default button style asserts structure (padding/border/background) but lets
  the **label colour inherit** the cascade → a broad `.foregroundStyle(.blue)`
  colours button labels.
- A `.destructive` button style **does** assert `foreground = palette.error` →
  it intentionally ignores broad text colour (precedence 4 > 3), because red is
  load-bearing. That's the per-control opt-out.

So: **assert only what must be fixed; inherit everything else.** Today's hardcoded
styles (primary button bold, section header bold+dim) become *soft scoped entries
the theme installs* (overridable), except genuinely load-bearing colours, which
stay asserted by styles.

### 3.6 Why proximity, not specificity (flaws considered)

The earlier draft used specificity-dominant resolution (a narrow scope beats a
broad one regardless of position). Proximity-dominant is better:

- **It's intuitive as you recurse the tree.** "I set buttons green up here, then
  said *all text red* down there" → the red wins, because it's closer. Specificity-
  dominant would surprisingly keep the buttons green (the far, narrower rule), which
  is exactly the unintuitive case to avoid.
- **It matches SwiftUI.** SwiftUI has no specificity system; the nearest environment
  modifier wins. Hewing to it keeps the mental model familiar.

Flaws of pure proximity, and how each is handled:

- **Load-bearing colours clobbered.** A closer broad `.foregroundStyle(.blue)` would
  override a theme's destructive-red *if that red lived in the cascade*. **Handled:**
  load-bearing/semantic styling is asserted by the control's *style* (precedence 4)
  or per-instance (5), never as a soft cascade entry. The cascade is for overridable
  preferences only.
- **Chained modifiers on one view.** `.style(.button){green}.style(.button(.default)){blue}`
  resolves by tree position: the first-written modifier is innermost and wins
  (green) — the same gotcha as SwiftUI's `.foregroundColor(.red).foregroundColor(.blue)`
  → red. **Handled:** combine broad + specific in a `Theme` / single `.style` call
  (specificity-ordered there), not by hand-chaining; document innermost-wins.
- **Per-property "mixed" results.** Outer `{green, bold}` + inner `{red}` → red and
  bold. **Accepted:** per-property independence is SwiftUI's model and more flexible;
  reset every property to fully override.

### 3.7 Modifiers

Broad (SwiftUI-identical signatures; each appends a `.text`/`.all`-scoped entry):

```swift
extension View {
    func foregroundStyle(_ color: Color?) -> some View       // already exists; feeds the cascade
    func bold(_ enabled: Bool = true) -> some View
    func italic(_ enabled: Bool = true) -> some View
    func underline(_ enabled: Bool = true) -> some View
    func fontWeight(_ weight: FontWeight?) -> some View       // .bold→bold, .light/.thin→faint(dim)
    func textCase(_ textCase: TextCase?) -> some View
}
```

Targeted (TUI extension) — the generic engine plus typed conveniences:

```swift
extension View {
    func style(_ scope: StyleScope, _ attributes: StyleAttributes) -> some View
    func style(_ scope: StyleScope, _ build: (inout StyleAttributes) -> Void) -> some View
}

// Typed conveniences over the generic form:
.buttonTextStyle { $0.bold = true }                 // .control(.button)
.buttonTextStyle(.default) { $0.foreground = .blue }// .controlVariant(.button, .default)
.sectionHeaderStyle { $0.textCase = .uppercase }    // .chrome(.sectionHeader)
```

`Text("x").bold()` keeps working unchanged (the method on the concrete `Text` type
is preferred over the `View` extension and sets its own `TextStyle`).

## 4. Tint (implemented **last** — wholly new)

```swift
extension EnvironmentValues { var tint: Color? }          // default nil
extension View { func tint(_ tint: Color?) -> some View }  // SwiftUI-identical
```

Tint is the cascading **accent** override. Controls that draw an accent resolve
`environment.tint ?? palette.accent`. It applies **wherever tinting makes sense**
(Button default style, Toggle, Slider, Picker, focus ring, ProgressView, …); some
controls legitimately ignore it (a case-by-case call documented per control).

## 5. Cascading `.disabled` (implemented near the end, **before** tint — also new)

```swift
extension EnvironmentValues { var isEnabled: Bool }        // default true
extension View { func disabled(_ disabled: Bool = true) -> some View }  // SwiftUI-identical
```

Controls compute `effectiveDisabled = ownDisabled || !environment.isEnabled`, so
`.disabled(true)` on a container disables every control inside. (A real behavioural
change — nested disabling — hence its own late phase.)

## 6. Theme = a bundle

A theme is **not** a new resolution mechanism — it's a struct whose `.theme(_:)`
modifier expands into individual environment settings (palette, appearance, tint,
and a set of scoped style entries). Deeper modifiers then override pieces naturally.

```swift
public struct Theme: Sendable {
    public var palette: any Palette
    public var appearance: Appearance
    public var tint: Color?
    public var styles: [ (StyleScope, StyleAttributes) ]   // scoped defaults the theme installs
    public var buttonStyle: any ButtonStyle
    public var listStyle: any ListStyle
    public var pickerStyle: any PickerStyle
    // …extensible
}

extension View  { func theme(_ theme: Theme) -> some View }
extension Scene { func theme(_ theme: Theme) -> some Scene }
```

`styles` is where a theme says e.g. "section headers are bold+dim" or "default
buttons are bold" — as scoped entries, ordered by specificity within the bundle so
its specific entries beat its broad ones, while any deeper subtree modifier still
wins by proximity. Built-in themes wrap the palettes from the colour work (phosphor
presets + Terminal.app profiles).

**Override semantics (confirmed):** `.theme()` sets the baseline; any modifier
closer to the content wins; a nested `.theme()` fully replaces for its subtree.
`Theme` / `.theme(_:)` are explicitly TUI-specific and kept separate from the
SwiftUI-parity surface.

## 7. How SwiftUI approaches this — a comparison

SwiftUI is the model we hew to. It's worth being precise about what it does, what it
*doesn't*, and where TUIkit deliberately extends it.

### 7.1 SwiftUI has no `Theme` type

SwiftUI theming is *composition of environment-propagated modifiers* + *per-control
style protocols*. There is no first-class "theme" object; you either compose
modifiers at the root, or define a custom `EnvironmentKey` and read it yourself.

```swift
// SwiftUI — "theme" = a pile of modifiers (or a custom EnvironmentKey).
WindowGroup {
    ContentView()
        .tint(.green)
        .font(.system(.body, design: .monospaced))
        .buttonStyle(.bordered)
}
```
```swift
// TUIkit — a Theme bundles the same intent into one value + modifier.
WindowGroup { ContentView() }
    .theme(.ocean)        // palette + appearance + tint + scoped style defaults
```
TUIkit keeps the SwiftUI building blocks *and* adds the bundle as a convenience.

### 7.2 Resolution: innermost wins, no specificity

SwiftUI resolves a style by the **nearest** modifier; there is no notion of one
scope being "more specific" than another. The classic consequence:

```swift
// SwiftUI — the INNER modifier wins. This is red, not blue.
Text("Hi")
    .foregroundColor(.red)    // innermost → wins
    .foregroundColor(.blue)   // outer → overridden
```
```swift
// TUIkit — same rule (§3.4). Innermost wins, per property.
Text("Hi").foregroundStyle(.red).foregroundStyle(.blue)   // → red
```
TUIkit adds **scopes** so an entry can target a subset of views, but precedence
between ancestors is still pure proximity — i.e. SwiftUI's rule, generalised.

### 7.3 Broad content styling

SwiftUI cascades content style through the environment; controls inherit it.

```swift
// SwiftUI — everything inside, including button labels, goes blue.
VStack {
    Text("Title")
    Button("Action") {}
}
.foregroundStyle(.blue)
```
```swift
// TUIkit — identical (foregroundStyle feeds the .text scope; soft-default styles
// let button labels inherit it — §3.5).
VStack {
    Text("Title")
    Button("Action") {}
}
.foregroundStyle(.blue)
```

SwiftUI also has **hierarchical** foreground levels (`.secondary`/`.tertiary`/
`.quaternary`) and a cascading `.font`/`.fontWeight`/`.bold`/`.textCase`:

```swift
// SwiftUI
Text("Subtitle").foregroundStyle(.secondary)
VStack { Text("a"); Text("b") }.fontWeight(.semibold).textCase(.uppercase)
```
```swift
// TUIkit — palette roles play the role of SwiftUI's hierarchical styles, and the
// same container-level modifiers cascade (no real fonts in a terminal, so weight
// maps to bold/regular/faint).
Text("Subtitle").foregroundStyle(.palette.foregroundSecondary)
VStack { Text("a"); Text("b") }.fontWeight(.bold).textCase(.uppercase)
// plus a role rule TUIkit adds: "secondary-coloured text is always dim"
.style(.semanticColor(.foregroundSecondary)) { $0.dim = true }
```

### 7.4 Per-control styling

SwiftUI restyles a control with its style protocol; **variants/roles are handled
inside the style** via `configuration`:

```swift
// SwiftUI — a custom ButtonStyle that reacts to role + pressed state.
struct MyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .bold()
            .foregroundStyle(configuration.role == .destructive ? .red : .accentColor)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
Form { … }.buttonStyle(MyButton())     // applies to all buttons in scope
```
```swift
// TUIkit — the same per-control style protocol exists (ButtonStyle + configuration
// carrying role/state). Structural restyling works the SwiftUI way.
Form { … }.buttonStyle(MyButtonStyle())
```

### 7.5 Where TUIkit extends SwiftUI

SwiftUI can target **"all buttons"** (`.buttonStyle`) and **"this button"**
(explicit), and handles variants *inside* a style. What it can **not** do
ergonomically is *tweak one property of one variant, app-wide, without authoring a
whole style* — e.g. "make just *default* buttons' text blue but keep their default
look." You'd have to write a `ButtonStyle` that reimplements the default look plus
the tweak.

```swift
// SwiftUI — no selector for "default-button text"; you replace the whole style.
struct DefaultBlue: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.blue)   // …and you've now lost the
    }                                                 // system default look/behaviour
}
.buttonStyle(DefaultBlue())
```
```swift
// TUIkit — the scoped cascade tweaks one property of one variant, keeping the
// default style intact.
RootView().buttonTextStyle(.default) { $0.foreground = .blue }
```

This is the one deliberate superset: **a scoped, property-level cascade layered
over SwiftUI's broad modifiers + style protocols.** Broad modifiers and `*Style`
protocols stay SwiftUI-identical; `StyleScope`/`.style(_:_:)`/`Theme` are the
clearly-marked TUI extensions.

### 7.6 Goal → SwiftUI → TUIkit

| Goal | SwiftUI | TUIkit |
|---|---|---|
| App-wide accent | `.tint(_:)` | `.tint(_:)` (identical) |
| All text blue | `.foregroundStyle(.blue)` | `.foregroundStyle(.blue)` (identical) |
| All buttons restyled | `.buttonStyle(_:)` | `.buttonStyle(_:)` (identical) |
| Variant/role look | branch on `configuration` in a style | same, **or** `.buttonTextStyle(.destructive){…}` |
| *One property of one variant*, app-wide | author a full custom style | `.style(.controlVariant(…)){…}` ← **new** |
| Bundle it all as a "theme" | compose modifiers / custom key | `.theme(_:)` ← **new convenience** |
| Resolution | nearest modifier wins | nearest modifier wins (per property) |

## 8. Worked examples

```swift
// (a) Broad: all text blue — Text, button labels, section headers included.
RootView().foregroundStyle(.blue)

// (b) Targeted by control: only button labels bold.
Pane().buttonTextStyle { $0.bold = true }

// (c) Targeted by variant: only DEFAULT buttons get blue text.
Pane().buttonTextStyle(.default) { $0.foreground = .blue }

// (d) Per-subtree bundle: green + bold controls in one pane, defaults elsewhere.
Editor().tint(.green).bold()

// (e) Role-based: secondary-coloured text is always dim, app-wide.
Root().style(.semanticColor(.foregroundSecondary)) { $0.dim = true }

// (f) Proximity override (your example): buttons green up here, all text red below.
VStack {
    Toolbar()                              // buttons green (from the outer rule)
    Editor().foregroundStyle(.red)         // here buttons (and all text) are red — closer wins
}
.buttonTextStyle { $0.foreground = .green }

// (g) Opt-out for usability: a destructive button keeps error red even under (a),
//     because its style asserts it (precedence 4 > 3). A one-off opts out explicitly:
Text("Critical").foregroundStyle(.palette.error)

// (h) A theme bundles such defaults:
WindowGroup { ContentView() }.theme(.ocean)
```

## 9. Migration of today's hardcoded styling

Each is behaviour-preserving by default and individually testable:

- **Section header/footer** (`applyHeaderFooterStyle`, bold+dim / dim) → installed
  as soft `.chrome(.sectionHeader/.sectionFooter)` entries in the default theme;
  `Section` resolves them via the cascade. Default look unchanged, now overridable.
- **Button primary bold** (`_ButtonAppearance.primary.isBold`) → the style asserts
  bold (precedence 4); its label colour inherits the cascade (so `tint`/foreground
  reach it); destructive/role colours stay asserted (the opt-out).
- **Dimmed overlay backdrop** → unchanged (situational, not theme-level).

## 10. Implementation phases (each its own commit(s) + tests)

Comprehensive coverage of all built-in controls, delivered incrementally. Order
reflects: colour-role attributes early; `disabled` late but before tint; tint last.

1. ✅ **(shipped)** **`StyleAttributes` + scoped-cascade core** — env value,
   `StyleScope`, the resolver (proximity-per-property); wired into `Text`
   (`.all`/`.text` + `.semanticColor`). Broad modifiers
   `.bold/.italic/.underline/.strikethrough/.fontWeight/.textCase` (+ `FontWeight`,
   `TextCase`) and the generic `.style(_:_:)`. Delivers (a), (e), (f-text).
   `Text.bold()` unchanged. (TUIkitExample: Text Styles page "Cascading styles".)
2. ✅ **(shipped)** **Chrome roles** — `Section` header/footer resolve via an
   environment `chromeRole` + `.chrome(...)` scope; defaults preserve the current
   look (header bold+dim, footer dim) and are now overridable (e.g. uppercase /
   un-bold headers). (TUIkitExample: Text Styles page "Themeable chrome".)
3. ▶︎ **Control targeting, control by control** (in progress) — soft-default
   styles + cascade resolution + typed conveniences, one control per commit.
   First landed `StyleAttributes.foreground/background` (the deferred half of the
   cascade) so controls can resolve scoped colour. ✅ **Button** — its label
   resolves `.control(.button)` / `.controlVariant(.button, …)` as soft overrides
   (destructive red stays load-bearing); `Button.Variant` + `.buttonTextStyle`.
   ✅ **Toggle** — a reusable `controlKind` env tag lets a label-via-Text control
   resolve `.control(.toggle)`; `.toggleTextStyle`. ✅ **Slider** — its value
   read-out resolves `.control(.slider)`; `.sliderTextStyle`. ✅ **Picker** — its
   subtree is tagged `.picker` so label/option Text resolves `.control(.picker)`;
   `.pickerTextStyle`. ✅ **Stepper** — value read-out resolves `.control(.stepper)`;
   `.stepperTextStyle`. ✅ **TextField / SecureField** — entered text resolves
   `.control(.textField)` / `.control(.secureField)` (cursor/selection/prompt
   keep their colours); `.textFieldTextStyle` / `.secureFieldTextStyle`. ✅
   **RadioButton** — labels resolve `.control(.radioButton)` (claimed only when
   not already inside another control, so a Picker's radio options stay
   `.picker`); `.radioButtonTextStyle`. ✅ **List/Table rows** — row content is
   ordinary Text: per-row styling and broad `.foregroundStyle` reach it (verified).
   **Follow-up:** container-level *attribute* cascade (e.g. `.bold()` on the List)
   does not yet reach rows — the lazy row-buffer path doesn't re-key on the style
   cascade; tracked below. All interactive controls covered. Delivers (b), (c), (g).
4. ✅ **(shipped) Cascading `.disabled`** — env `isEnabled` + an additive
   `DisabledModifier` (`.disabled(_:)` on any View); every interactive control
   combines `self.isDisabled || !environment.isEnabled`. A descendant can't
   re-enable what an ancestor disabled. (TUIkitExample: Buttons page "Cascading
   .disabled".)
5. ✅ **(shipped) Tint** — `.tint(_:)` + env `tint`, implemented by overriding the
   subtree palette's `accent` (a `TintedPalette` wrapper) so *every* `palette.accent`
   read — button caps/focus, toggle ON mark, slider/stepper arrows, radio dot,
   focus highlights, accent-coloured text — follows the tint with no per-control
   wiring. Nested tints override; `.tint(nil)` inherits. (TUIkitExample: Buttons
   page "Tinted group".)
6. **`Theme` + `.theme(_:)`** (View + Scene) — expands to env keys + scoped entries;
   built-in theme bundles wrapping the existing palettes/profiles.
7. **Example UI** — theme editor exercising broad, role-based, and control/variant
   overrides + per-section demos.

## Variant — typed-per-control vs. one shared enum

**Decision: typed per control** (e.g. `Button.Variant { .automatic, .bordered,
.borderless, .plain, .destructive }`), exposed through the typed convenience
modifiers, over a **type-erased token** stored inside `StyleScope`.

Pros (per-control typed):
- Type-safe & self-documenting; autocomplete offers only valid variants
  (`.buttonTextStyle(.bordered)`, never `.buttonTextStyle(.large)`).
- Each control owns and can extend its own variant taxonomy.
- Impossible to target a variant a control doesn't have.

Cons / cost:
- One small enum per control to define and maintain.
- The generic `.style(_:_:)` core must store the variant **type-erased** (a string
  or `AnyHashable` token), so there's a thin typed-convenience layer bridging to the
  erased core. (The typed conveniences are what users normally touch; the generic
  form is the escape hatch.)

Shared `StyleVariant` was rejected: variants don't map across controls (a button's
`.bordered` is meaningless for a slider), so a shared enum is either too generic to
be useful or a grab-bag that permits invalid combinations.

## Follow-ups

- **List/Table row attribute cascade.** Broad `.foregroundStyle` and per-row Text
  styling reach row content, but container-level *attribute* entries (e.g.
  `.bold()` / `.style(.control(.list)) { … }` on the List) don't yet reach row
  text: the lazy/cached row-buffer path doesn't re-key on `styleCascade`. Wiring
  it needs the row content cache to include the cascade in its key (carefully, to
  preserve the List's per-frame row memoisation). Until then, style row text
  per-row or via the palette.

## Resolved decisions (was: open questions)

- **Ambition** — comprehensive; *all* built-in controls. Phasing is the
  implementer's call; delivered as many small commits (§10).
- **Resolution** — proximity-dominant, per property; specificity only orders within
  a bundle (§3.4, §3.6).
- **Variant** — typed per control over a type-erased token (above).
- **Control coverage** — all of them, one per commit in phases 3 & 5.
- **Override semantics** — baseline theme; closer wins; nested theme replaces (§6).
```
