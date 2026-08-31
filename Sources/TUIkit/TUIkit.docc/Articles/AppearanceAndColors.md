# Appearance and Colors

Control border styles, visual appearances, and the color system.

## Overview

TUIkit separates visual styling into two systems:

- **Appearance**: Controls border characters and container styling (rounded, doubleLine, heavy, etc.)
- **Colors**: A palette-aware color system with semantic tokens that resolve at render time

Both systems integrate with the theming pipeline described in <doc:ThemingGuide>.

## Appearances

An ``Appearance`` defines the border characters used by containers and the `.border()` modifier. TUIkit ships with four built-in appearances:

| Appearance | Border Characters | Example |
|------------|-------------------|---------|
| `.line` | `─ │ ┌ ┐ └ ┘` | Thin single lines |
| `.rounded` | `─ │ ╭ ╮ ╰ ╯` | Rounded corners (default) |
| `.doubleLine` | `═ ║ ╔ ╗ ╚ ╝` | Double-line borders |
| `.heavy` | `━ ┃ ┏ ┓ ┗ ┛` | Bold / heavy lines |

### Setting the Appearance

The active appearance flows through the environment:

```swift
// Set appearance for all children
VStack {
    Panel("Settings") {
        Text("Uses doubleLine borders")
    }
}
.environment(\.appearance, .doubleLine)
```

### Cycling Appearances at Runtime

Users can press `a` to cycle through appearances. The `ThemeManager` handles this via the `AppearanceRegistry`.

### Custom Appearances

Create additional appearances with a custom ``BorderStyle``:

```swift
let custom = Appearance(
    id: .init(rawValue: "dashed"),
    borderStyle: BorderStyle(
        topLeft: "+", topRight: "+",
        bottomLeft: "+", bottomRight: "+",
        horizontal: "-", vertical: "|",
        leftT: "+", rightT: "+"
    )
)
```

## The Color System

TUIkit's ``Color`` type supports multiple color modes:

### Standard ANSI Colors (8)

```swift
.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white
```

### Bright ANSI Colors (8)

```swift
.brightBlack, .brightRed, .brightGreen, .brightYellow,
.brightBlue, .brightMagenta, .brightCyan, .brightWhite
```

### 256-Color Palette

```swift
Color.palette(202)  // orange
```

### True Color (RGB)

```swift
Color.rgb(255, 128, 0)       // orange via RGB components
Color.hex(0xFF8000)          // orange via hex integer
Color.hex("#FF8000")         // orange via hex string
Color.hsl(30, 100, 50)       // orange via HSL
Color.hsb(30, 100, 100)      // orange via HSB
Color.cmyk(0, 50, 100, 0)    // orange via CMYK
```

### Color Manipulation

```swift
let lighter = color.lighter(by: 0.2)  // 20% lighter
let darker = color.darker(by: 0.3)    // 30% darker
```

### Gradients

Anywhere a colour is painted, a gradient goes instead: ``View/foregroundStyle(_:)``
and ``View/background(_:)`` take any ``ShapeStyle``, and ``LinearGradient``,
``RadialGradient``, ``EllipticalGradient`` and ``AngularGradient`` are
SwiftUI's own types with SwiftUI's own initialisers.

```swift
Text("Gradient text")
    .foregroundStyle(LinearGradient(colors: [.red, .blue],
                                    startPoint: .leading, endPoint: .trailing))
```

By default each view runs the whole ramp inside itself, which is SwiftUI's
meaning. ``View/gradientExtent(_:)`` is the TUI-specific addition SwiftUI has no
spelling for — **one ramp across a set of views**, each taking its own slice by
where it sits:

```swift
VStack {
    ForEach(rows) { Text($0.title) }
}
.foregroundStyle(LinearGradient(colors: [.red, .blue],
                                startPoint: .top, endPoint: .bottom))
.gradientExtent(.subtree)      // first row red, last row blue
```

That case costs what colouring each row by hand costs: a ramp that does not
change along a row is one escape per row, exactly what it would have been. A
ramp that varies *across* a row is a colour change per cell — right for a label
or a panel, dear for a whole page.

The ramp spans the **content**, not the window — so a row keeps its colour as it
scrolls, and forty rows in a ten-row viewport show the first quarter of the ramp.
Every container that places children takes part: the stacks and their lazy
twins, ``ZStack``, ``ScrollView``, ``Form``, ``List``, ``OutlineGroup``, the
grids, and any ``Layout`` you write yourself. Swapping one for another does not
change a colour. ``Table`` is the exception — its columns yield strings rather
than views, so it paints its own cells and reads no foreground style at all.

A colour or a gradient is also a **view**, filling the space it is offered — so
`ZStack { LinearGradient(…); Text("Title") }` works, and a fill in a stack takes
the slack the other children leave. One caveat: compositing is opaque per cell,
so a sibling drawn over a fill replaces the cells it covers rather than showing
the fill through its glyphs. Where a glyph needs colour behind it, put the
colour on the thing that has the glyph — `Text("hi").background(.red)`.

``View/backgroundStyle(_:)`` names a surface for a subtree and
``View/background()`` paints whatever is in force, defaulting to the palette's
own background:

```swift
VStack {
    Text("Total").padding().background()
}
.backgroundStyle(Color.rgb(20, 24, 34))
```

Two deviations from SwiftUI, both because a cell is about twice as tall as it
is wide: ``RadialGradient``'s radii are `Int` **cells** measured along the
horizontal axis, with the vertical derived through
``EnvironmentValues/imageCellAspect`` so a circle looks like one, and
``AngularGradient``'s angles are corrected the same way.
``EllipticalGradient`` follows the box's own shape and needs no correction.

### Fading a Whole View

``View/opacity(_:)`` fades everything a subtree draws, without
your having to reach for each colour in it:

```swift
VStack {
    Text("Coming soon").bold()
    Text("This section is not ready yet.")
}
.opacity(0.4)
```

This is real compositing, done with the two things a cell has: the subtree
renders to its own layer, and where that layer is drawn onto what is behind
it, each cell is resolved against the cell beneath. So a view fading over a
coloured panel moves toward the *panel's* colour, not the page's. Hue
survives — a red heading at `0.4` still reads red rather than flattening to
grey — and nesting multiplies, as in SwiftUI: `0.5` inside `0.5` shows at
`0.25`.

Colours compose exactly, at every alpha. **Characters cannot**: two
characters cannot share one cell at half strength each, so where two
characters want the same cell, alpha becomes a decision rather than a mix.

- **Over anything blank** there is no contest: the subtree's characters draw
  at every alpha, in colours blended toward what is behind them, and simply
  fade all the way out.
- **Where a character sits underneath**, at or above `0.5` the subtree's
  character draws; below `0.5` the character behind shows instead, keeping
  its own foreground while its field carries the veil. So `opacity(0)`
  really does reveal what it covers, while still keeping its space and its
  clickable regions, which is what SwiftUI's `opacity(0)` does too.
- **Matching characters never snap**: where both sides hold the same
  character the cell cross-fades exactly, so a colour animation on unchanged
  text is seamless.

Text fading over *different* text therefore swaps characters at the midpoint
rather than dissolving through it. There is no way around that in a cell
grid, and it is the one place this differs visibly from a graphical
compositor.

Two more rules make fading a container behave the way you would expect:

- **A space is not a character.** A faded view's blank cells composite their
  background and let what is behind them show through, so fading a `VStack`
  does not punch a rectangle of blanks through the page.
- **What is behind keeps its own foreground.** A translucent pane over text
  tints the surface under the text, not the text — which stays legible.

## Semantic Colors

`SemanticColor` provides palette-aware color tokens that resolve at render time. This is the bridge between the color system and the theming system.

### In View Bodies (no RenderContext)

Use `Color.palette.*`: these return semantic tokens:

```swift
Text("Hello")
    .foregroundStyle(.palette.accent)    // resolves to palette's accent color
    .background(.palette.background)
```

Available semantic tokens include:

| Token | Typical Use |
|-------|-------------|
| `.palette.foreground` | Primary text |
| `.palette.foregroundSecondary` | Secondary / dimmed text |
| `.palette.foregroundTertiary` | Disabled / muted text |
| `.palette.foregroundQuaternary` | Dimmest foreground (subtle UI, e.g. spinner tracks) |
| `.palette.accent` | Highlighted elements, titles |
| `.palette.border` | Container borders |
| `.palette.background` | App background |
| `.palette.statusBarBackground` | Status bar background |
| `.palette.appHeaderBackground` | App header background |
| `.palette.overlayBackground` | Overlay / dimmed background |
| `.palette.focusBackground` | Focused list/table row background |
| `.palette.cursorColor` | Text cursor in text fields |
| `.palette.fieldBackground` | Editable-field surface (TextField, TextEditor) |
| `.palette.success` / `.warning` / `.error` / `.info` | Status indicators |

### In renderToBuffer (with RenderContext)

Use `context.environment.palette.*` directly: these return concrete colors:

```swift
func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let accent = context.environment.palette.accent
    let border = context.environment.palette.border
    // use directly in rendering code
}
```

> Important: Unresolved semantic colors hitting the `ANSIRenderer` trigger a `fatalError`. Always resolve via `Color.resolve(with:)` or use `context.environment.palette.*` in rendering code.

## Text Styling

Text emphasis can be applied per-``Text``, or **cascaded** to a whole subtree
through the environment — exactly like ``View/foregroundStyle(_:)``.

### Per-Text

```swift
Text("Bold").bold()
Text("Quiet").dim().italic()
```

### Cascading (container-level)

Container-level modifiers apply to every descendant ``Text`` and can be
overridden closer to the content — the nearest modifier wins, per attribute:

```swift
VStack {
    Text("Title")
    Text("Subtitle")
}
.bold()                  // both lines bold
.textCase(.uppercase)    // …and uppercased

// A descendant opts out:
VStack {
    Text("Bold")
    Text("Not bold").bold(false)   // closer wins
}
.bold()
```

Available cascading modifiers: `bold(_:)`, `italic(_:)`, `underline(_:)`,
`strikethrough(_:)`, `fontWeight(_:)` (weight maps to bold / normal / faint on a
terminal), and `textCase(_:)`.

### Semantic font styles

``View/font(_:)`` takes a ``Font`` — `.headline`, `.body`, `.caption` and the
rest of SwiftUI's semantic styles — so source that says *this is a heading*
keeps saying it here:

```swift
VStack(alignment: .leading) {
    Text("Deployment failed").font(.headline)
    Text("3 of 12 replicas unhealthy").font(.body)
    Text("2 minutes ago").font(.caption)
}
```

A terminal has one typeface at one size, so a font selects **intensity**, not
metrics. Eleven SwiftUI styles collapse onto the three tiers a cell grid can
tell apart:

| Styles | Renders |
|--------|---------|
| `largeTitle`, `title`, `title2`, `title3`, `headline` | bold |
| `subheadline`, `body`, `callout` | normal |
| `footnote`, `caption`, `caption2` | faint |

Nothing here changes a glyph or a cell count, so applying a font cannot reflow
the layout around it. The axes that survive the medium are carried for real —
``Font/weight(_:)``, ``Font/bold(_:)`` and ``Font/italic(_:)`` — while the ones
that need a typeface (size, design, width, small caps) are absent rather than
accepted and ignored.

The mapping is the **baseline**, so an explicit attribute anywhere in the
cascade still wins, and each style is addressable as a ``StyleScope/font(_:)``
scope — which is how a theme redefines one wholesale:

```swift
ContentView()
    .style(.font(.headline)) { $0.underline = true }
```

### Scoped styling

``View/style(_:_:)-(_,StyleAttributes)`` targets a subset of views by ``StyleScope`` — including a
semantic colour role, so you can, for example, dim every secondary-coloured text
app-wide without touching primary text:

```swift
RootView()
    .style(.semanticColor(.foregroundSecondary)) { $0.dim = true }
```

Structural **chrome** — `Section` headers and footers — can be targeted the same
way (they are bold + dim by default, and the cascade overrides that):

```swift
List {
    Section("Settings") { /* … */ }
}
.style(.chrome(.sectionHeader)) { $0.textCase = .uppercase }   // UPPERCASE headers
```

**Controls** expose typed conveniences over the scope mechanism. For example, a
button's label text:

```swift
Sidebar().buttonTextStyle { $0.bold = true; $0.foreground = .green }  // all buttons
RootView().buttonTextStyle(.automatic) { $0.foreground = .blue }      // default-style only
```

A load-bearing colour (e.g. a `.destructive` button's error red) stays asserted by
the control's style and is not overridden by a broad cascade entry.

## BorderStyle

``BorderStyle`` defines the actual Unicode characters for border rendering:

```swift
public struct BorderStyle {
    let topLeft, topRight, bottomLeft, bottomRight: Character
    let horizontal, vertical: Character
    let leftT, rightT: Character
}
```

Built-in styles: `.line`, `.rounded`, `.doubleLine`, `.heavy`, `.none`.
