# Theming Guide

Customize the visual appearance of your TUIkit application with palettes.

## Overview

TUIkit includes a full theming system with six built-in palettes inspired by classic CRT terminals. Palettes define semantic colors for backgrounds, foregrounds, accents, and UI elements.

## Built-in Palettes

| Palette | Preset | Inspiration |
|---------|--------|-------------|
| Green | `.green` | IBM 5151, Apple II |
| Amber | `.amber` | IBM 3278, Wyse 50 |
| Red | `.red` | Military terminals |
| Violet | `.violet` | Retro sci-fi displays |
| Blue | `.blue` | VFD displays |
| White | `.white` | DEC VT100, VT220 |

These six classic-phosphor presets are instances of ``SystemPalette``.

In addition, TUIkit ships recreations of the ten built-in **macOS Terminal.app**
profiles as ``AppleTerminalPalette`` — Basic, Grass, Homebrew, Man Page, Novel,
Ocean, Pro, Red Sands, Silver Aerogel and Solid Colors — built from the exact
colours those profiles ship with.

``PaletteRegistry/all`` lists every built-in palette (the six presets followed by
the ten profiles); ``PaletteRegistry/phosphorPresets`` and
``PaletteRegistry/appleTerminalProfiles`` expose the two groups separately.

## Using Palettes

### Via PaletteManager

Access the palette manager through the environment to cycle or set palettes:

```swift
struct MyView: View {
    @Environment(\.paletteManager) var paletteManager

    var body: some View {
        VStack {
            Text("Current: \(paletteManager.currentName)")
            Button("Next Palette") {
                paletteManager.cycleNext()
            }
        }
    }
}
```

### Via Environment

Set a palette for a view and all its descendants:

```swift
ContentView()
    .palette(SystemPalette(.amber))
```

### Palette Colors in Views

Use ``Color/palette`` to access the current palette's colors:

```swift
Text("Styled text")
    .foregroundStyle(.palette.foreground)
    .background(.palette.background)
```

Or read the palette directly from the environment:

```swift
@Environment(\.palette) var palette

Text("Hello").foregroundStyle(palette.accent)
```

## Creating Custom Palettes

Implement the ``Palette`` protocol for a palette with just the essential colors:

```swift
struct MyCustomPalette: Palette {
    let id = "custom"
    let name = "Custom"

    let background = Color.hex(0x1A1A2E)
    let foreground = Color.hex(0xE0E0E0)
    let accent = Color.hex(0x00D4FF)
    let success = Color.hex(0x00FF88)
    let warning = Color.hex(0xFFCC00)
    let error = Color.hex(0xFF4444)
    let info = Color.hex(0x44AAFF)
    let border = Color.hex(0x333355)

    // Optional: override defaults for statusBarBackground,
    // appHeaderBackground, overlayBackground,
    // foregroundSecondary, foregroundTertiary, foregroundQuaternary,
    // focusBackground, cursorColor, fieldBackground
}
```

## Palette Color Properties

- **Backgrounds**: `background`, `statusBarBackground`, `appHeaderBackground`, `overlayBackground`
- **Foregrounds**: `foreground`, `foregroundSecondary`, `foregroundTertiary`, `foregroundQuaternary`
- **Accent**: `accent`
- **Semantic**: `success`, `warning`, `error`, `info`
- **UI Elements**: `border`, `focusBackground` (focused list/table rows), `cursorColor` (text cursor), `fieldBackground` (editable-field surface)

Only 8 properties are required (`background`, `foreground`, `accent`, `border`, `success`, `warning`, `error`, `info`). All others have default implementations that derive from these.

## What built-in controls draw with

Every built-in control draws with the palette's roles, so a palette you write, or
one of the built-ins, restyles all of them. A control uses a literal colour only
when the colour is its content, not its chrome.

- **Text and labels**: `foreground`. It is text's default colour, and a
  ``StatusBar``'s labels use it while ``StatusBar/labelColor`` is `nil`.
- **Shortcut keys in the status bar**: `accent`, while
  ``StatusBar/highlightColor`` is `nil`. A colour you set there, on the view or on
  ``StatusBarState``, is drawn as you set it.
- **The unlit part of a track**: `foregroundTertiary`, in a ``Slider``, a
  ``ProgressView`` and a ``Gauge``; their filled part is `foregroundSecondary`.
- **A switch that is off** (``SwitchToggleStyle``): its track is
  `foregroundTertiary`, moved only as far as it takes to stand off both the page,
  which the knob is drawn in, and the accent, which the track turns when the
  switch is on. A disabled switch fades that track halfway toward the page. A
  scroll track is `foregroundQuaternary`, separated the same way.
- **A label on a surface the control did not choose**: the active tab's label in
  a ``TabView``, the check mark on the swatch under the cursor in
  ``ColorPickerPanel``'s grids, and the index numbers on its 256-colour grid. These use
  ``Palette/readableText(on:)`` for the surface: whichever of `foreground` and
  `background` reads better there. A focused tab strip breathes the active label
  toward the accent. Where the two are too close to see apart, as on White, whose
  accent is white, the accent end moves just far enough to be seen.
- **The indeterminate ``IndeterminateStyle/gradient(_:)`` bar with no stops**:
  `error`, `warning`, `success`, `info` and `accent`, in that order. The accent is
  among them, so `.tint` still reaches the bar.
- **Alerts and destructive actions**: the warning, error, info and success alert
  presets draw their titles in the role of the same name. A destructive button or
  menu item is drawn in `error`.

A role's alpha comes with it, so a faded palette fades the controls drawn with
it.

These stay literal on purpose:

- **Content**: an ``Image``'s pixels; the colour being edited in a colour picker;
  the swatch sets (Greyscale, Named, Web Safe, Crayons) and the 256-colour grid's
  cells; ``GradientEditorPanel``'s preset gradients; any gradient you supply.
  The colour is what these show, so a theme must not change it.
- **Identity**: ``ChannelCurveEditorPanel``'s red, green and blue curves, and
  ``ToneCurveEditorPanel``'s strip of input greys. They say which channel or
  which tone you are looking at, which a theme would not know.
- **Fallbacks for input that has no colour**: an empty gradient, or an animated
  colour with no frames.
- **The frame-dump debug overlay** (`TUIKIT_DEBUG_FRAME_DUMP=1`), a diagnostic.

## Editing Colors at Runtime

Two controls edit a `Binding<Color>`, mirroring SwiftUI's `ColorPicker`:

- ``ColorPicker`` — a **compact, inline** editor: a live swatch plus one slider
  per RGB channel. Good for a settings row where a full panel would be overkill.

  ```swift
  @State private var tint: Color = .rgb(80, 160, 255)
  ColorPicker("Accent", selection: $tint)
  ```

- ``ColorPickerPanel`` — the **full modal editor**, the terminal analogue of
  macOS's colour panel: a live preview plus tabs for the **RGB / HSL / HSB /
  CMYK** colour models (one slider per channel), a **Semantic** tab that selects
  a palette role (`.semantic(role)`, so the colour tracks the theme), a **256**
  tab showing the xterm palette as an arrow-navigable grid, and **Greyscale**,
  **Named**, **Web Safe** and **Crayons** tabs for picking from those curated
  sets.

  Present it with ``View/modal(isPresented:onDismiss:content:)``. The modal is centred and
  dims the whole screen no matter where it is attached, so you can hang it off any
  subtree — there is no need to host it from a special root:

  ```swift
  @State private var colour: Color = .rgb(80, 160, 255)
  @State private var editing = false

  Button("Edit colour…") { editing = true }
      .modal(isPresented: $editing) {
          ColorPickerPanel("Accent", selection: $colour, isPresented: $editing)
      }
  ```

  It edits the binding **live** (the preview and anything bound to `colour`
  update as you drag); "Done" or `Esc` dismisses it. See the example app's Theme
  page, which edits the live app-wide palette with both controls.
