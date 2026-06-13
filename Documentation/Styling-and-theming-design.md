# TUIkit styling & theming — design

Status: **design agreed in principle; implementation pending.** This document is
the reference for the styling/theming work. It captures the model, the public
API shape, resolution rules, worked examples, and the phased plan.

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
default is behaviour-preserving until something is customised.

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

### 3.2 `StyleScope` — *what* an entry targets (the specificity lattice)

```swift
public enum StyleScope: Sendable, Hashable {
    case all                                   // everything                       (specificity 0)
    case text                                  // any rendered text                (1)
    case semanticColor(SemanticColor)          // text drawn with a palette role
                                               //   e.g. .foregroundSecondary      (2)
    case control(ControlKind)                  // any control of a kind            (1)
    case controlVariant(ControlKind, Variant)  // a specific mode, e.g. button .default (2)
    case chrome(ChromeRole)                    // sectionHeader, sectionFooter, …  (2)
}

public enum ControlKind: Sendable, Hashable { case button, toggle, slider, picker, textField, list, stepper, … }
public enum ChromeRole:  Sendable, Hashable { case sectionHeader, sectionFooter, listRow, … }
// `Variant` is a small typed value per control (Button: .default/.bordered/.borderless/.plain
// + role .destructive; resolved from the control's style + role).
```

Each scope has a **specificity** (shown above). The taxonomy is **typed and
finite** — not open-ended CSS selectors — so it stays discoverable and checkable.

### 3.3 The cascade environment value

```swift
extension EnvironmentValues {
    /// Ordered scoped style entries contributed by ancestors. Modifiers append;
    /// resolution merges the entries that match a view, by specificity then depth.
    public var styleCascade: StyleCascade        // default: empty
}

struct StyleCascade { /* [(scope, attributes, depth)] — append-only down the tree */ }
```

### 3.4 Resolution — how a view computes its effective style

A view knows the **scopes it matches** (its "scope path"). Examples:

- A plain `Text` → `[.all, .text]` (plus `[.semanticColor(role)]` if it draws with
  a palette role).
- A *default* `Button`'s label → `[.all, .text, .control(.button), .controlVariant(.button, .default)]`.
- A `Section` header → `[.all, .text, .chrome(.sectionHeader)]`.

Effective `StyleAttributes` is the merge of every cascade entry whose scope is in
the view's path, ordered **least-specific first, ties broken by farthest ancestor
first** — so the most specific, closest entry wins. The full precedence, low → high:

1. Framework default (`EnvironmentKey.defaultValue`).
2. Palette / theme baseline.
3. **Scoped cascade entries** for the view's scopes, ordered by (specificity, depth).
4. The control's own resolved `*Style` (only where it *asserts* a property — see §3.5).
5. **Per-instance explicit** modifier on the view itself (`Text(…).foregroundStyle(…)`).

This single ordering yields: broad settings reach everywhere (step 3, `.all`/`.text`),
targeted settings override broad ones (higher specificity within step 3), and any
view can opt out by asserting the property locally (step 5) — or a control can opt
out for usability by asserting it in its style (step 4).

### 3.5 Soft-default styles — the key to "broad reaches into controls"

For "set text colour blue → button labels go blue too", a control's default style
must **not** unconditionally paint its label. Instead, styles are *partial*: they
assert only what's intrinsic to the style and **inherit the rest from the cascade**.

- The default button style asserts structure (padding/border/background) but lets
  the **label colour inherit** the cascade → a broad `.foregroundStyle(.blue)`
  colours button labels.
- A `.destructive` button style **does** assert `foreground = palette.error` →
  it intentionally ignores the broad text colour, because red is load-bearing for
  usability. That's the per-style opt-out.

So: **assert only what must be fixed; inherit everything else.** Today's hardcoded
styles (primary button bold, section header bold+dim) become *defaults expressed as
scoped entries the theme installs*, not hardcoded paints — so they're overridable.

### 3.6 Modifiers

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
// Generic: address any scope.
extension View {
    func style(_ scope: StyleScope, _ attributes: StyleAttributes) -> some View
    func style(_ scope: StyleScope, _ build: (inout StyleAttributes) -> Void) -> some View
}

// Typed conveniences (discoverable, autocomplete-friendly) layered on the generic form:
.buttonTextStyle { $0.bold = true }                 // scope .control(.button)
.buttonTextStyle(.default) { $0.foreground = .blue }// scope .controlVariant(.button, .default)
.sectionHeaderStyle { $0.textCase = .uppercase }    // scope .chrome(.sectionHeader)
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
`.disabled(true)` on a container disables every control inside. (This is a real
behavioural change — nested disabling — hence its own late phase.)

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
    // …extensible (Q5: start here, grow as needed)
}

extension View  { func theme(_ theme: Theme) -> some View }
extension Scene { func theme(_ theme: Theme) -> some Scene }
```

`styles` is where a theme says e.g. "section headers are bold+dim" or "default
buttons are bold" — as scoped entries, so any subtree can override them. Built-in
themes wrap the palettes from the colour work (phosphor presets + Terminal.app
profiles) with sensible appearance/tint/styles.

**Override semantics (confirmed):** `.theme()` sets the baseline; any modifier
closer to the content wins; a nested `.theme()` fully replaces for its subtree.
`Theme` / `.theme(_:)` are explicitly TUI-specific and kept separate from the
SwiftUI-parity surface.

## 7. SwiftUI parity

- Identical signatures: `.foregroundStyle`, `.bold(_:)`, `.italic(_:)`,
  `.fontWeight(_:)`, `.textCase(_:)`, `.tint(_:)`, `.disabled(_:)`.
- `FontWeight` and `TextCase` mirror SwiftUI's enums, terminal-mapped (weight →
  bold / regular / faint(dim)).
- Per-control `*Style` protocols (`ButtonStyle`, …) remain the SwiftUI-faithful way
  to restyle a control's *structure*; the scoped attribute cascade is the TUI
  extension for *property-level* tweaks without authoring a whole style. They
  compose: a style sets structure + asserts intrinsic properties; the cascade fills
  the rest.
- `StyleScope` / `.style(_:_:)` / `Theme` are TUI-specific, documented as such.

## 8. Worked examples

```swift
// (a) Broad: all text blue — Text, button labels, section headers included.
RootView().foregroundStyle(.blue)

// (b) Targeted by control: only button labels bold.
Pane().buttonTextStyle { $0.bold = true }              // .control(.button)

// (c) Targeted by variant: only DEFAULT buttons get blue text.
Pane().buttonTextStyle(.default) { $0.foreground = .blue }   // .controlVariant(.button, .default)

// (d) Per-subtree bundle: green + bold controls in one pane, defaults elsewhere.
Editor().tint(.green).bold()

// (e) Role-based: secondary-coloured text is always dim, app-wide.
Root().style(.semanticColor(.foregroundSecondary)) { $0.dim = true }

// (f) Opt-out for usability: a destructive button keeps error red even under (a).
//     Achieved by its style asserting foreground = palette.error (step 4 > step 3).
//     A one-off view opts out explicitly:
Text("Critical").foregroundStyle(.palette.error)       // per-instance wins (step 5)

// (g) A theme bundles the above kinds of defaults:
WindowGroup { ContentView() }.theme(.ocean)
```

## 9. Migration of today's hardcoded styling

Each is behaviour-preserving by default and individually testable:

- **Section header/footer** (`applyHeaderFooterStyle`, bold+dim / dim) → installed
  as `.chrome(.sectionHeader/.sectionFooter)` scoped entries in the default theme;
  `Section` resolves them through the cascade. Default look unchanged, now overridable.
- **Button primary bold** (`_ButtonAppearance.primary.isBold`) → the style asserts
  bold as today, but its label colour inherits the cascade (so `tint`/foreground
  reach it); destructive/role colours stay asserted (opt-out).
- **Dimmed overlay backdrop** → unchanged (situational, not theme-level).

## 10. Implementation phases (each its own commit + tests)

Order reflects: colour-role attributes now; `disabled` late but before tint; tint last.

1. **`StyleAttributes` + scoped-cascade core** — the env value, `StyleScope`, the
   resolver; wire into `Text` (`.all`/`.text` + `.semanticColor` scopes). Broad
   modifiers `.bold/.italic/.underline/.fontWeight/.textCase` (+ `FontWeight`,
   `TextCase`). Delivers (a), (b-partial), (e). `Text.bold()` unchanged.
2. **Chrome roles** — `Section` header/footer resolve via `.chrome(...)`; defaults
   preserve the current look.
3. **Control targeting** — soft-default styles; `Button` (then others) resolve the
   cascade for `.control(.button)` / `.controlVariant(.button, …)`; add `.style(_:_:)`
   + typed conveniences. Delivers (b), (c), (f-opt-out).
4. **Cascading `.disabled`** — env `isEnabled`; controls AND-combine.
5. **Tint** — env `tint`, `.tint(_:)`, resolved wherever tinting makes sense.
6. **`Theme` + `.theme(_:)`** (View + Scene) — expands to env keys + scoped entries;
   built-in theme bundles wrapping the existing palettes/profiles.
7. **Example UI** — theme editor exercising broad, role-based, and control/variant
   overrides + per-section demos.

## 11. Open questions

1. **Ambition of v1 scoped engine** — build the full `StyleScope` cascade as the
   foundation (recommended; one mechanism for every granularity), or start with the
   broad cascade + chrome roles and add control/variant targeting in a later pass?
   (Phases are written for the full engine; we can defer phase 3's variant targeting
   if you'd rather see the broad pieces land first.)
2. **`Variant` typing** — strongly type per control (e.g. `Button.Variant`) for
   autocomplete, vs a single shared `StyleVariant`? Leaning per-control typed.
3. **How many controls in phase 3/5 initially** — Button + Toggle + Slider + Picker
   first, others as a follow-up? (Coverage is incremental regardless.)
```
