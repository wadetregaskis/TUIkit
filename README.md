<p align="center">
    <img alt="Platforms" src="https://img.shields.io/badge/Platforms-macOS%20%7C%20Linux-005c00">
    <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-00b300?logo=swift&logoColor=white">
    <img alt="i18n" src="https://img.shields.io/badge/i18n-7%20Languages-00d900">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-00b300?style=flat">
    <a href="https://github.com/wadetregaskis/TUIkit/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/wadetregaskis/TUIkit/ci.yml?branch=main&label=CI&color=009900"></a>
</p>

<img width="1200" height="630" alt="og-image@1x" src="https://github.com/user-attachments/assets/8bf99da8-e87c-4447-b3cb-a6f3f52c6d18" />

# TUIkit

> [!IMPORTANT]
> **This project is currently a WORK IN PROGRESS! I strongly advise against using it in a production environment because APIs are subject to change at any time.**

A SwiftUI-like framework for building Terminal User Interfaces in Swift: no ncurses, no external C dependencies, just pure Swift.

## What is this?

TUIkit lets you build TUI apps using the same declarative syntax you already know from SwiftUI. Define your UI with `View`, compose views with `VStack`, `HStack`, and `ZStack`, style text with modifiers like `.bold()` and `.foregroundStyle(.red)`, and run it all in your terminal.

```swift
import TUIkit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State var count = 0
    
    var body: some View {
        VStack(spacing: 1) {
            Text("Hello, TUIkit!")
                .bold()
                .foregroundStyle(.cyan)
            
            Text("Count: \(count)")
            
            Button("Increment") {
                count += 1
            }
        }
        .statusBarItems {
            StatusBarItem(shortcut: "q", label: "quit")
        }
    }
}
```

## Features

### Core

- **`View` protocol**: the core building block, mirroring SwiftUI's `View`
- **`@ViewBuilder`**: result builder for declarative view composition
- **`@State` / `@Binding`**: reactive state management with automatic re-rendering
- **`@Environment`**: dependency injection for theme, focus, status bar, and other services
- **`App` / `Scene` / `WindowGroup`**: app lifecycle with signal handling and a demand-driven run loop (idle screens cost nothing; animations are bounded by `maxFrameRate`)

### Views & components

- **Primitive views**: `Text`, `EmptyView`, `Spacer`, `Divider`, `Image`
  - **`Image`** renders raster images (PNG/JPEG, decoded by AppKit's `NSImage` on Apple platforms and the bundled `stb_image` elsewhere) as terminal art. Five character sets via `.imageCharacterSet(_:)` — `fineBlocks` (the default; half-block `▄` cells giving near-square sub-pixels), `coarseBlocks`, `shapeBased` (shape-vector matching), `ascii`, and `braille`. Four colour modes via `.imageColorMode(_:)` — `trueColor` (default), `ansi256`, `grayscale`, `mono` — auto-downgraded to the terminal's capability, with optional Floyd–Steinberg dithering. Loads asynchronously from a file path or URL (session-cached) behind a placeholder spinner, and supports aspect-fit/fill, zoom including sub-1× (`.imageZoom(_:)`), and fit targets (`.imageFitTarget(.proposedSize | .viewport)`).
- **Layout containers**: `VStack`, `HStack`, `ZStack` (with `.zIndex` for draw order and overlay layers for floating content), `LazyVStack`, `LazyHStack`, `Group`, `ViewThatFits`, and `TabView` / `Tab`
- **Interactive controls**: `Button`, `ButtonRow`, `Toggle`, `Menu`, `Picker`, `TextField`, `SecureField`, `Slider`, `Stepper`, `RadioButtonGroup`, and `ColorPicker` (with a rich `ColorPickerPanel` offering RGB/HSL/HSB/CMYK editing, a 256-colour grid, and named / web-safe / crayon palettes) — all with keyboard navigation and focus
  - `Picker` styles: `.automatic` (default), `.menu`, `.inline`, `.radioGroup`
  - `Toggle` styles: `.automatic`, `.checkbox` (a checkbox; customise its glyphs with `CheckboxStyle` — `.squares` (default) or `.ascii` — via `.checkboxStyle(_:)`), and `.switch` (a two-position switch — a knob over a coloured track)
- **Data views**: `List`, `Table`, `Section`, `ForEach`, `NavigationSplitView`, `ContentUnavailableView`
  - `List` rows render lazily — only the visible window is materialised, so very large lists stay O(visible) — with `.plain` / `.insetGrouped` styles and `.badge()` rows
  - `Table` supports per-column sizing (`.width(.fixed(n) | .flexible | .ratio(r) | .fit)`, where `.fit` sizes to the widest header/cell value), multi-line wrapping cells (`.lineLimit(_:)`), per-column alignment and truncation, and row selection
  - `NavigationSplitView` columns are resizable by default (drag the divider or use the keyboard) and offer automatic / balanced / prominent-detail styles
- **Containers & chrome**: `Alert`, `Dialog`, `Panel`, `Card`
- **Feedback**:
  - **`ProgressView`** — determinate or indeterminate. Determinate look via `.progressViewStyle(_:)` (`TrackStyle`): `block` (default), `bar`, `blockFine`, `dot`, `shade`, `braille`, `shadeRamp(gradient:)`, `threeSegment(...)`. Indeterminate animation via `.indeterminateStyle(_:)`: `sweep` (default), `barberPole`, `pulse`, `knightRider`, `gradient`.
  - **`Spinner`** — animated, in three styles: `dots` (default), `line`, `bouncing` (a Knight-Rider scanner with a fading trail), with an optional label and colour.
- **`StatusBar`**: context-sensitive keyboard shortcuts with `.compact` and `.bordered` styles

### Scrolling & scrollbars

- **`ScrollView`** scrolls both vertically and horizontally (`ScrollView(.horizontal)` / `[.horizontal, .vertical]`), and `List`, `Table`, and `Picker` pop-ups scroll too.
- **Scrollbars** are opt-in (hidden by default). Configure with `.scrollbarVisibility(.automatic | .visible | .hidden)`, `.scrollbarArrows(.none | .single | .double)`, `.scrollbarProportionalThumb(_:)`, and `.scrollbarClickBehavior(.page | .jump)`. They are fully interactive: a sub-cell-precise proportional thumb, drag-to-scroll, click-to-page/jump on the track, end-arrow stepping, and auto-repeat while a button is held.

### Mouse & trackpad

- Left / middle / right clicks, vertical scroll-wheel, and horizontal + vertical trackpad scrolling, with drag tracking and enter/exit hit-testing. Both SGR and legacy X10 mouse-report encodings are parsed.
- Gesture modifiers: `.onTapGesture`, `.onScrollGesture`, `.onDragGesture`, `.onHover`, and the raw `.onMouseEvent`.
- Enable the level you want with `.mouseSupport(.disabled | .scrollOnly | .standard | .full)` on a `View` or a `Scene`.

### Presentation

- **Alerts**: `.alert(_:isPresented:actions:message:)` (and a no-message overload), with optional `borderStyle` / `borderColor` / `titleColor`.
- **Modals / sheets**: `.modal(isPresented:content:)`, an always-on `.modal { … }`, and `.sheet(isPresented:content:)` (a SwiftUI-compatible alias for `.modal`).
- Alerts and modals present a **centred overlay that dims the whole screen and captures keyboard input** from any attachment point; <kbd>ESC</kbd> dismisses.
- **Notifications**: toast-style transient messages drawn by `.notificationHost(width:)`, posted out-of-band via `NotificationService.current.post(...)` — they overlay without dimming or blocking the background.

### Styling

- **Text styling**: `.bold()`, `.italic()`, `.underline()`, `.strikethrough()`, `.fontWeight(_:)`, `.textCase(_:)` on any view; plus `.dim()`, `.blink()`, and `.inverted()` on `Text`.
- **Colour**: `.foregroundStyle(_:)` and `.background(_:)`. `Color` supports the 8 standard + 8 bright ANSI colours, the 256-colour palette (`Color.palette(_:)`), 24-bit RGB (`Color.rgb(_:_:_:)`), hex (`Color.hex(0xFF5500)` / `Color.hex("#FF5500")`), and the HSL / HSB / CMYK colour spaces. Palette-aware semantic colours resolve against the active palette at render time.
- **Border styles** (`BorderStyle`): `.line`, `.rounded`, `.doubleLine`, `.heavy`, `.none`, plus a public initialiser for fully custom border characters; applied with `.border(_:color:)`.
- **Control styles**: `.buttonStyle`, `.toggleStyle`, `.pickerStyle`, `.checkboxStyle`, `.tabViewStyle`, `.navigationSplitViewStyle`, plus per-control text-style builders.
- **Badges**: `.badge(_ count: Int)` (0 hides) or `.badge(_ label:)` on list rows.

### Internationalization (i18n)

- **7 languages built-in**: English, German, French, Italian, Spanish, Simplified Chinese, Japanese
- **Type-safe string constants**: the compile-time-verified `LocalizationKey` namespace
- **Persistent language selection**: stored per-app in the platform config dir (macOS `~/Library/Application Support/<App>`, Linux `$XDG_CONFIG_HOME/<App>`)
- **Fallback chain**: current language → English → key itself
- **Thread-safe operations**: safe language switching at runtime

### Advanced

- **Lifecycle modifiers**: `.onAppear()`, `.onDisappear()`, `.task()`, `.onChange(of:initial:)`
- **Key handling**: `.onKeyPress()` (a raw handler, a key-set handler, and a single-key action), with modifier keys (ctrl, alt, shift) and function keys F1–F12
- **Storage**: `@AppStorage` with a JSON file backend (per-app platform config dir, default) and a `UserDefaults` backend
- **Preferences**: bottom-up data flow with `PreferenceKey` — `.preference(key:value:)`, `.onPreferenceChange(_:perform:)`, `.navigationTitle(_:)`
- **Focus system**: Tab / Shift+Tab navigation, `.focusSection(_:)` for grouped areas, and `.focusID(_:)` to set an explicit identity on a control
- **Accelerated stepping**: `.shiftStepMultiplier(_:)` controls how far a Shift-accelerated key press moves (scrolling, list/table cursor movement, and `Stepper` / `Slider` value changes; default 5)
- **Render caching**: `.equatable()` for subtree memoization

## Run the example app

```bash
swift run TUIkitExample
```

Press `q` to exit. (Inside a demo page, `ESC` goes back to the menu.)

## Installation

### Quick start with the CLI

Install the `tuikit` command and create a new project:

```bash
curl -fsSL https://raw.githubusercontent.com/wadetregaskis/TUIkit/main/project-template/install.sh | bash
tuikit init MyApp
cd MyApp && swift run
```

See [project-template/README.md](project-template/README.md) for more options (SQLite, Swift Testing).

### Manual setup

Add TUIkit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wadetregaskis/TUIkit.git", branch: "main")
]
```

Then add it to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["TUIkit"]
)
```

> **Tip:** `import TUIkit` re-exports all sub-modules. For finer control you can import individual modules: `TUIkitCore`, `TUIkitStyling`, `TUIkitView`, or `TUIkitImage`.

## Theming

TUIkit ships two families of built-in palettes, both conforming to the `Palette` protocol and applied at the scene (or view) level with `.palette(_:)`.

**Classic-phosphor presets** — `SystemPalette`:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .palette(SystemPalette(.green))  // Classic green terminal
    }
}
```

Available presets (`SystemPalette.Preset`):
- `.green` — IBM 5151 / Apple II (P1 phosphor) — the default
- `.amber` — IBM 3278 / Wyse 50 (P3 phosphor)
- `.red` — military / night-vision
- `.violet` — retro computing / sci-fi terminals
- `.blue` — vacuum fluorescent displays (VFDs)
- `.white` — DEC VT100/VT220 (P4 phosphor)

**macOS Terminal.app profiles** — `TerminalProfilePalette` recreates ten built-in Terminal.app profiles from their exact shipped colours (Basic, Grass, Homebrew, Man Page, Novel, Ocean, Pro, Red Sands, Silver Aerogel, Solid Colors):

```swift
.palette(TerminalProfilePalette(.homebrew))
```

`PaletteRegistry.all` enumerates all 16 built-in palettes (`.phosphorPresets` + `.terminalProfiles`), with `PaletteRegistry.palette(withId:)` / `palette(withName:)` lookups. Custom palettes conform to `Palette` directly, and the modal `ColorPicker` lets users edit colours interactively.

## Internationalization

TUIkit includes comprehensive i18n support with 7 languages and type-safe string constants:

```swift
import TUIkit

struct MyView: View {
    var body: some View {
        VStack {
            // Type-safe localized strings (typed-key overloads)
            Text(localized: LocalizationKey.Button.ok)
            LocalizedString(LocalizationKey.Error.notFound)

            // Or look up by dot-notation key directly
            LocalizedString("button.cancel")

            // Switch language at runtime
            Button("Deutsch") {
                AppState.shared.setLanguage(.german)
            }
        }
    }
}
```

**Supported languages**: English, Deutsch, Français, Italiano, Español, 简体中文, 日本語

Apps can localize **their own** strings through the same service — register
language-keyed tables once at startup, then look them up by key:

```swift
LocalizationService.shared.register(translations: [
    "en": ["app.greeting": "Hello"],
    "de": ["app.greeting": "Hallo"],
])
LocalizationService.shared.string(for: "app.greeting")  // honours the current language
```

The `LocalizationKey` namespace groups all framework strings into `Button`, `Label`, `Error`, `Placeholder`, `Menu`, `Dialog`, and `Validation`, with typed-key overloads for `Text(localized:)`, `LocalizedString(_:)`, and `LocalizationService.string(for:)`. The fallback chain is current language → English → the key itself, and the selection is persisted per-app in the platform config directory alongside `@AppStorage` (macOS: `~/Library/Application Support/<App>/language`; Linux: `$XDG_CONFIG_HOME/<App>/language`, else `~/.config/<App>/language`).

For complete documentation, see the [Localization Guide](https://github.com/wadetregaskis/TUIkit/blob/main/Sources/TUIkit/TUIkit.docc/Articles/Localization.md) in the DocC documentation.

## Architecture

- **Modular package**: 5 Swift library modules + 1 in-tree C target (see Project Structure below)
- **No singletons for state**: application state flows through the Environment system
- **Pure ANSI rendering**: no ncurses runtime dependency; the only C is the bundled `stb_image` decoder, and only as the fallback where AppKit's `NSImage` is unavailable (selected via `canImport(AppKit)`, not a hard-coded platform list)
- **Linux compatible**: works on macOS and Linux (XDG paths supported)
- **Value types**: views are structs, just like SwiftUI

### Package dependencies

- [swift-collections](https://github.com/apple/swift-collections) — `DequeModule`, used by the terminal output queue
- [swift-docc-plugin](https://github.com/swiftlang/swift-docc-plugin) — documentation
- [ordo-one/benchmark](https://github.com/ordo-one/package-benchmark) — performance benchmarks, run via `swift package benchmark`

## Project structure

```
Sources/
├── CSTBImage/            C target: bundled stb_image — image decoder fallback (non-Apple platforms)
├── TUIkitCore/           Primitives, key/input parsing, frame buffer, concurrency helpers
│                         (Concurrency, Environment, Extensions, Input, Rendering)
├── TUIkitStyling/        Color, theme palettes, border styles (Color, Styles, Theme)
├── TUIkitView/           View protocol, ViewBuilder, State, Environment, Renderable
│                         (Core, Environment, Rendering, State)
├── TUIkitImage/          ASCII-art converter (braille / fine-blocks / shape / dithering),
│                         image loading — NSImage on Apple, else stb_image
│                         (depends on CSTBImage + TUIkitStyling)
├── TUIkit/               Umbrella module: App, Views, Modifiers, Focus, StatusBar, ...
│   ├── App/              App, Scene, WindowGroup
│   ├── AppHeader/        App header chrome
│   ├── Environment/      Environment keys, service configuration
│   ├── Extensions/       View modifiers and convenience APIs
│   ├── Focus/            Focus system and keyboard navigation
│   ├── Localization/     i18n service, type-safe keys, translations (5 languages)
│   ├── Modifiers/        Border, Frame, Padding, Overlay, Lifecycle, KeyPress, Mouse, ...
│   ├── Notification/     Toast-style notification system
│   ├── Rendering/        Terminal, ANSIRenderer, ViewRenderer
│   ├── State/            @State / @AppStorage / binding storage
│   ├── Styles/, Styling/ Control and visual styles
│   ├── Utility/          Misc helpers
│   ├── TUIkit.docc/      DocC documentation catalog
│   └── Views/            Text, Stacks, Button, TextField, Slider, List, Table, Image, ...
├── TUIkitExample/        Example app (executable target)
└── TUIkitStress/         Performance stress harness, also a complex-TUI demo (executable)

Tests/
└── TUIkitTests/          ~2,275 tests across 316 suites in 186 files
                          (incl. i18n consistency, localization & golden-snapshot tests)

Tools/
├── EmojiBugScanner/      Probes Terminal.app for emoji cursor-advance quirks
├── EmojiBenchmark/       Benchmarks emoji classification strategies
└── Profiling/            Instruments Time Profiler tooling (record.sh, drive.py,
                          analyze_timeprofile.py, idle_cpu.py) and the RenderHarness
                          executable (no-PTY render loop for `xctrace --launch`)

Benchmarks/
└── TUIkitBenchmarks/     ordo-one/package-benchmark suite (color, frame buffer, image,
                          input parsing, layout, list/table, render, scroll, text width,
                          view identity); run via `swift package benchmark`
```

The package also vends each library as an individual product. `import TUIkit` re-exports `TUIkitCore`, `TUIkitStyling`, `TUIkitView`, and `TUIkitImage` (via `@_exported`), so the umbrella import gives full API access; import the sub-modules individually for finer control.

## Requirements

- Swift 6.2+
- macOS 14+ or Linux

## Developer notes

- Tests use Swift Testing (`@Test`, `#expect`): run with `swift test`. The suite is ~2,275 tests across 316 suites in 186 files.
- Most tests run in parallel; a small subset that mutates global state is serialised, so the whole suite runs in a few seconds.
- Benchmarks: `swift package benchmark` (full suite) — see `Benchmarks/TUIkitBenchmarks`.
- Profiling: see [Tools/Profiling/README.md](Tools/Profiling/README.md) (Instruments Time Profiler via a PTY, plus the no-PTY `RenderHarness` for `xctrace --launch`).
- The `Terminal` class handles raw mode and cursor control via POSIX `termios`.

## License

This repository has been published under the [MIT](https://mit-license.org) license.
