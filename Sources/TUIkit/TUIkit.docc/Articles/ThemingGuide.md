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
profiles as ``TerminalProfilePalette`` — Basic, Grass, Homebrew, Man Page, Novel,
Ocean, Pro, Red Sands, Silver Aerogel and Solid Colors — built from the exact
colours those profiles ship with.

``PaletteRegistry/all`` lists every built-in palette (the six presets followed by
the ten profiles); ``PaletteRegistry/phosphorPresets`` and
``PaletteRegistry/terminalProfiles`` expose the two groups separately.

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
    // foregroundSecondary, foregroundTertiary
}
```

## Palette Color Properties

- **Backgrounds**: `background`, `statusBarBackground`, `appHeaderBackground`, `overlayBackground`
- **Foregrounds**: `foreground`, `foregroundSecondary`, `foregroundTertiary`
- **Accent**: `accent`
- **Semantic**: `success`, `warning`, `error`, `info`
- **UI Elements**: `border`

Only 8 properties are required (`background`, `foreground`, `accent`, `border`, `success`, `warning`, `error`, `info`). All others have default implementations that derive from these.

## Editing Colors at Runtime

Two controls edit a `Binding<Color>`, mirroring SwiftUI's `ColorPicker`:

- ``ColorPicker`` — a **compact, inline** editor: a live swatch plus one slider
  per RGB channel. Good for a settings row where a full panel would be overkill.

  ```swift
  @State private var tint: Color = .rgb(80, 160, 255)
  ColorPicker("Accent", selection: $tint)
  ```

- ``ColorPickerPanel`` — the **full modal editor**, the terminal analogue of
  macOS's colour panel: a live preview, tabs for the **RGB / HSL / HSB / CMYK**
  colour models (one slider per channel), a **Semantic** tab that selects a
  palette role (`.semantic(role)`, so the colour tracks the theme), and a
  **256** tab showing the xterm palette as an arrow-navigable grid.

  TUIkit modals are page-hosted (a `.modal` centres on the space available where
  it's attached), so present the panel from a full-screen subtree — typically
  the page root — rather than from deep inside a layout:

  ```swift
  @State private var colour: Color = .rgb(80, 160, 255)
  @State private var editing = false

  PageRoot {
      Button("Edit colour…") { editing = true }
  }
  .modal(isPresented: $editing) {
      ColorPickerPanel("Accent", selection: $colour, isPresented: $editing)
  }
  ```

  It edits the binding **live** (the preview and anything bound to `colour`
  update as you drag); "Done" or `Esc` dismisses it. See the example app's Theme
  page, which edits the live app-wide palette with both controls.
