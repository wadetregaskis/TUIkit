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

- **Primitive views**: `Text`, `EmptyView`, `Spacer`, `Divider`, `Image`, and `Label(_:systemImage:)` (SF Symbols, on terminals using Apple's fonts)
  - **`Image`** renders raster images (PNG/JPEG, decoded by AppKit's `NSImage` on Apple platforms and the bundled `stb_image` elsewhere) as terminal art, configured by three orthogonal choices. The **charset** via `.imageCharacterSet(_:)` — `.ascii(glyphs:)`, `.unicode(glyphs:)` (adds box-drawing and geometric shapes; excludes block characters), `.blocks(_:)` at a discrete resolution (`.half` half-block `▄` cells, the default; `.solid` gap-free background fill; `.coarse` shades; `.braille` 2×4 dots), or `.customRamp(_:)`. The charset **size** — the `glyphs` count picks the ideal calibrated subset (density levels spread evenly, flattest glyph per level). And **shape-awareness** via `.imageShapeAware(_:)` — glyphs matched by their measured in-cell ink distribution (with Sobel edge-orientation lines for ascii/unicode; blocks shape-match over quadrants, halves, shades, and corner triangles `◢◣◤◥`). Four colour modes via `.imageColorMode(_:)` — `trueColor` (default), `ansi256`, `grayscale`, `mono` — auto-downgraded to the terminal's capability, with optional Floyd–Steinberg dithering. Loads asynchronously from a file path or URL (session-cached) behind a placeholder spinner, and supports aspect-fit/fill, zoom including sub-1× (`.imageZoom(_:)`), and fit targets (`.imageFitTarget(.proposedSize | .viewport)`).
- **Layout containers**: `VStack`, `HStack`, `ZStack` (with `.zIndex` for draw order and overlay layers for floating content), `LazyVStack`, `LazyHStack`, `Group`, `ViewThatFits`, and `TabView` / `Tab`
- **Interactive controls**: `Button`, `ButtonRow`, `Toggle`, `Menu`, `Picker`, `TextField` (with combo-box-style suggestion menus via `.textInputSuggestions(_:)`), `SecureField`, `TextEditor`, `DatePicker`, `Slider`, `Stepper`, `RadioButtonGroup`, `Link` (with the `openURL` environment action), and `ColorPicker` (with a rich `ColorPickerPanel` offering RGB/HSL/HSB/CMYK editing, a 256-colour grid, and named / web-safe / crayon palettes) — all with keyboard navigation and focus
  - `Picker` styles: `.automatic` (default), `.menu`, `.inline`, `.radioGroup`
  - `Menu` takes a `@ViewBuilder` of `Button`s (as SwiftUI's does) and is styled with `.menuStyle(_:)`: `.automatic` — a collapsed pull-down that opens a pop-up — or `.inline`, the items expanded in place. Click-and-hold works like a Mac menu: the highlight tracks the pointer and releasing over an item chooses it.
  - `.contextMenu(menuItems:)` attaches a right-click pop-up to any view (Ctrl-click where the terminal keeps right-click for itself; Shift+F10 opens it from the keyboard)
  - `Toggle` styles: `.automatic`, `.checkbox` (a checkbox; customise its glyphs with `ToggleCharacterSet` — `.unicode` (■/□), `.emoji` (⬛︎/⬜︎), or `.ascii` (`[x]`/`[ ]`) — via `.toggleCharacterSet(_:)`; the default adapts to the terminal: emoji under Apple's Terminal.app and iTerm2, unicode elsewhere), and `.switch` (a two-position switch — a knob over a coloured track, following the same glyph repertoire)
- **Data views**: `List`, `Table`, `Section`, `ForEach`, `Form` (with `LabeledContent` rows and columns / grouped layouts via `.formStyle(_:)`), `NavigationSplitView`, `ContentUnavailableView`
  - **Editing**: `Table` takes a TUI-specific `.onMove(perform:)` of its own (its rows are values, so there is no `ForEach` to attach one to) and reorders through the same state machine and the same `.rowReorderFeedback(_:)` modes — `.live` only for a multi-line table. `ForEach` takes `.onMove(perform:)` / `.onDelete(perform:)` — rows then drag to reorder, and <kbd>Delete</kbd> removes the row at the cursor — gated on those closures being present, NOT on `\.editMode`, which TUIkit ships as app-level state (`EditButton` drives it; no view reads it yet) because a terminal UI is desktop-shaped and SwiftUI itself marks `EditMode` unavailable on macOS. `.rowReorderFeedback(_:)` picks what a drag shows — in every mode the row leaves its old place, so what is on screen *is* the order a drop would produce: `.live` (the default: the rows reorder as the cursor moves, at one `onMove` per slot crossed), `.dimmed` (the row reappears greyed in the slot it would land in), or `.cursor` (it rides the pointer and the landing slot is an empty gap). `.dimmed` and `.cursor` move the data once, on release. **Without a mouse:** Ctrl+R picks the focused row up, the movement keys move its landing slot, Return places it and Escape puts it back — a mode rather than a modifier+arrow chord because Apple Terminal cannot deliver one (it strips modifiers from Up/Down). `.cursor` shows `.dimmed` for a keyboard move, having no cursor to ride. Ctrl+↑/↓ and Option+↑/↓ nudge the focused row one place with no mode at all (macOS eats the Ctrl pair itself — Mission Control), Option+Home/End/Page move it further, and Shift applies the coarse step.
  - **Search**: `.searchable(text:placement:prompt:)` composes a magnifier glyph and a bound field above the content; `.searchFieldIconPlacement(_:)` moves the glyph and turns it to face the field
  - `List` rows render lazily — only the visible window is materialised, so very large lists stay O(visible) — with `.plain` / `.insetGrouped` styles and `.badge()` rows
  - `Table` supports per-column sizing (`.width(.fixed(n) | .flexible | .ratio(r) | .fit)`, where `.fit` sizes to the widest header/cell value), multi-line wrapping cells (`.lineLimit(_:)`), per-column alignment and truncation, and row selection
  - `Set`-bound selections follow the macOS model: plain / shift- / ctrl-click for sole / range / toggle selection, Shift+arrows extend the range where the terminal reports Shift, Ctrl+V toggles an extend mode so plain arrows extend in any terminal, Ctrl+A selects all, and Escape clears — consuming the key only when there is something to clear, so it never blocks app navigation. Every one of those chords is rebindable with `.rowShortcuts(_:)` — bare keys are deliberately left to the app
  - `NavigationSplitView` columns are resizable by default (drag the divider or use the keyboard) and offer automatic / balanced / prominent-detail styles
- **Containers & chrome**: `Alert`, `Dialog`, `Panel`, `Card`
- **Feedback**:
  - **`ProgressView`** — determinate or indeterminate. Determinate look via `.progressViewStyle(_:)` (`TrackStyle`): `block` (default), `bar`, `blockFine`, `dot`, `shade`, `braille`, `shadeRamp(gradient:)`, `threeSegment(...)`, or `custom(TrackConfiguration)` — the named fill styles are presets of one configurable renderer (fill glyph, sub-cell ramp, solid-background unfilled, gradient). Indeterminate animation via `.indeterminateStyle(_:)`: `sweep` (default), `barberPole`, `pulse`, `knightRider`, `gradient`.
  - **`Gauge`** — a labelled value read-out with min/max bounds, styled via `.gaugeStyle(_:)`: `linearCapacity` (default), `accessoryLinear` (position marker), `accessoryLinearCapacity`, `accessoryCircular` / `accessoryCircularCapacity` (ring dials), or the compact `accessoryCircularTiny` pie glyph.
  - **`Spinner`** — animated, in eleven built-in styles (`dots` (default), `line`, `bouncing` (a Knight-Rider scanner with a fading trail), `pie`, `beachball`, `box`, `bars`, `blockWedge`, `moon`, `earth`, `clock`) plus `.custom(_:)` frame sequences, with an optional label and colour.
- **`StatusBar`**: context-sensitive keyboard shortcuts with `.compact` and `.bordered` styles

### Scrolling & scrollbars

- **`ScrollView`** scrolls both vertically and horizontally (`ScrollView(.horizontal)` / `[.horizontal, .vertical]`), and `List`, `Table`, and `Picker` pop-ups scroll too.
- **Scrollbars** are opt-in (hidden by default). Configure with `.scrollbarVisibility(.automatic | .visible | .hidden)`, `.scrollbarArrows(.none | .single | .double)`, `.scrollbarProportionalThumb(_:)`, and `.scrollbarClickBehavior(.page | .jump)`. They are fully interactive: a sub-cell-precise proportional thumb, drag-to-scroll, click-to-page/jump on the track, end-arrow stepping, and auto-repeat while a button is held.
- **What stays put** when the content or the terminal changes size is a policy, not an accident: `.anchorPosition(_:)` pins the viewport to `.top`, `.bottom`, a specific `.row(id)`, or the default `.window` (whatever is on screen stays on screen). `.scrollFollowMargin(_:)` says how much context to keep around a cursor that scrolls into view, `.scrollGranularity(_:)` sizes a step in lines or whole rows, and `.scrollOverscroll(_:)` allows (or forbids) scrolling past the end.
- **`ScrollViewReader`** hands you a `ScrollViewProxy` for imperative `scrollTo(_:anchor:)`, as in SwiftUI. Focusing a control also reveals it — including its border — in every scrollable ancestor.

### Mouse & trackpad

- Left / middle / right clicks, vertical scroll-wheel, and horizontal + vertical trackpad scrolling, with drag tracking and enter/exit hit-testing. Both SGR and legacy X10 mouse-report encodings are parsed.
- Gesture modifiers: `.onTapGesture` (including `count:` for double/triple-click, via synthesised `MouseEvent.clickCount`), `.onScrollGesture`, `.onDragGesture`, `.onHover`, and the raw `.onMouseEvent`.
- Drag and drop: `.draggable(_:)` (with an optional custom preview and grab-point anchoring) and `.dropDestination(for:action:)`, in the style of SwiftUI's Transferable API.
- Enable the level you want with `.mouseSupport(.disabled | .scrollOnly | .standard | .full)` on a `View` or a `Scene`.

### Presentation

- **Alerts**: `.alert(_:isPresented:actions:message:)` (and a no-message overload), with optional `borderStyle` / `borderColor` / `titleColor`.
- **Confirmation dialogs**: `.confirmationDialog(_:isPresented:titleVisibility:actions:message:)` — the same host with its buttons stacked as an action sheet and the `.cancel` role sorted last.
- **Modals / sheets**: `.modal(isPresented:content:)`, an always-on `.modal { … }`, and `.sheet(isPresented:content:)` (a SwiftUI-compatible alias for `.modal`).
- Alerts and modals present a **centred overlay that dims the whole screen and captures keyboard input** from any attachment point, and are draggable by their title or border. Choosing any alert action dismisses it (as in SwiftUI — the action does not flip the binding itself), and <kbd>ESC</kbd> *is* the `.cancel`-role button: it runs that action if there is one, and closes either way.
- **Notifications**: toast-style transient messages drawn by `.notificationHost(width:)`, posted out-of-band via `NotificationService.current.post(...)` — they overlay without dimming or blocking the background.

### Styling

- **Text styling**: `.bold()`, `.italic()`, `.underline()`, `.strikethrough()`, `.fontWeight(_:)`, `.textCase(_:)` on any view; plus `.dim()`, `.blink()`, and `.inverted()` on `Text`.
- **Colour**: `.foregroundStyle(_:)` and `.background(_:)`. `Color` supports the 8 standard + 8 bright ANSI colours, the 256-colour palette (`Color.palette(_:)`), 24-bit RGB (`Color.rgb(_:_:_:)`), hex (`Color.hex(0xFF5500)` / `Color.hex("#FF5500")`), and the HSL / HSB / CMYK colour spaces. Palette-aware semantic colours resolve against the active palette at render time.
- **Border styles** (`BorderStyle`): `.line`, `.rounded`, `.doubleLine`, `.heavy`, `.none`, plus a public initialiser for fully custom border characters; applied with `.border(_:color:)`.
- **Control styles**: `.buttonStyle`, `.toggleStyle`, `.pickerStyle`, `.toggleCharacterSet`, `.menuStyle`, `.listStyle`, `.formStyle`, `.gaugeStyle`, `.tabViewStyle`, `.navigationSplitViewStyle`, plus per-control text-style builders.
- **Badges**: `.badge(_ count: Int)` (0 hides) or `.badge(_ label:)` on list rows.

### Internationalization (i18n)

- **7 languages built-in**: English, German, French, Italian, Spanish, Simplified Chinese, Japanese
- **Type-safe string constants**: the compile-time-verified `LocalizationKey` namespace
- **Persistent language selection**: stored per-app in the platform config dir (macOS `~/Library/Application Support/<App>`, Linux `$XDG_CONFIG_HOME/<App>`); set `TUIKIT_CONFIG_DIR` to relocate ALL of an app's persisted state (`@AppStorage` included) — the isolation hook for test harnesses, since `UserDefaults` on macOS ignores `$HOME`
- **Fallback chain**: current language → English → key itself
- **Thread-safe operations**: safe language switching at runtime

### Advanced

- **Lifecycle modifiers**: `.onAppear()`, `.onDisappear()`, `.task()`, `.onChange(of:initial:)`
- **Key handling**: `.onKeyPress()` (a raw handler, a key-set handler, and a single-key action), with modifier keys (ctrl, alt, shift) and function keys F1–F12 (plus the VT220 F13–F20, which Apple's Terminal.app sends for Shift+F5–F12)
- **Keyboard shortcuts**: `.keyboardShortcut(_:modifiers:)` with `KeyEquivalent` / `EventModifiers`, and the semantic `.defaultAction` (Return) / `.cancelAction` (Escape) roles. A terminal never reports ⌘, so SwiftUI's default `modifiers: .command` is remapped at registration to whatever `.commandKey(_:)` names — `.control` (default), `.option`, `.bare`, or `.unavailable` — which is what lets one `View` source carry ⌘-shortcuts under both frameworks
- **Storage**: `@AppStorage`, backed by `UserDefaults` on Apple platforms (the preferences domain, like SwiftUI — `~/Library/Preferences/<id>.plist`) and a JSON file under the XDG config dir on Linux
- **Preferences**: bottom-up data flow with `PreferenceKey` — `.preference(key:value:)`, `.onPreferenceChange(_:perform:)`, `.navigationTitle(_:)`
- **Focus system**: Tab / Shift+Tab navigation, `.focusSection(_:)` for grouped areas, and `.focusID(_:)` to set an explicit identity on a control. `@FocusState` + `.focused($x)` / `.focused($field, equals:)` read and move focus programmatically, `.defaultFocus($field, value)` picks what starts focused, and `.focusable(_:interactions:)` makes any view a Tab stop. The focused control pulses on a shared clock; `\.isFocused` and `\.selectionEmphasis` let your own views join in
- **Accelerated stepping**: `.shiftStepMultiplier(_:)` controls how far a Shift-accelerated key press moves (scrolling, list/table cursor movement, and `Stepper` / `Slider` value changes; default 5)
- **Render caching**: `.equatable()` for subtree memoization

## Run the example app

```bash
swift run Example
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
                LocalizationService.shared.setLanguage(.german)
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

The `LocalizationKey` namespace groups all framework strings into `Button`, `Label`, `Error`, `Placeholder`, `Menu`, `Dialog`, `Validation`, and `StatusBar`, with typed-key overloads for `Text(localized:)`, `LocalizedString(_:)`, and `LocalizationService.string(for:)`. The fallback chain is current language → English → the key itself, and the selection is persisted per-app in the platform config directory alongside `@AppStorage` (macOS: `~/Library/Application Support/<App>/language`; Linux: `$XDG_CONFIG_HOME/<App>/language`, else `~/.config/<App>/language`).

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
- [ordo-one/benchmark](https://github.com/ordo-one/package-benchmark) — performance benchmarks, opt-in via the `TUIKIT_BENCHMARKS` flag: `TUIKIT_BENCHMARKS=1 swift package benchmark` (kept out of the default build/test graph)

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
│   ├── Input/            Drag-and-drop session tracking
│   ├── Localization/     i18n service, type-safe keys, translations (7 languages)
│   ├── Modifiers/        Border, Frame, Padding, Overlay, Lifecycle, KeyPress, Mouse, ...
│   ├── Notification/     Toast-style notification system
│   ├── Rendering/        Terminal, ANSIRenderer, ViewRenderer
│   ├── SFSymbols/        SF Symbols name → codepoint table and resolver
│   ├── State/            @State / @AppStorage / binding storage
│   ├── StatusBar/        Status bar model, shortcuts, system items
│   ├── Styles/, Styling/ Control and visual styles
│   ├── Utility/          Misc helpers
│   ├── TUIkit.docc/      DocC documentation catalog
│   └── Views/            Text, Stacks, Button, TextField, Slider, List, Table, Image, ...
├── Example/        Example app (executable target)
└── Stress/         Performance stress harness, also a complex-TUI demo (executable)

Tests/                    ~3,350 tests across ~510 suites in 341 files
├── TUIkitTests/          The umbrella module's suite (incl. i18n consistency,
│                         localization & golden-snapshot tests)
├── TUIkitCoreTests/      One suite per library module, so a module's tests
├── TUIkitStylingTests/   cannot lean on the umbrella's API — the boundary is
├── TUIkitViewTests/      enforced by Tools/validate-test-boundaries.sh
└── TUIkitImageTests/

Tools/
├── BuildDocs/            Builds the DocC reference as ONE archive covering every
│                         module (the module split is not the reader's problem)
├── Diagrams/             Generates the DocC architecture / lifecycle diagrams from source
├── EmojiBenchmark/       Benchmarks emoji classification strategies
├── EmojiBugScanner/      Probes Terminal.app for emoji cursor-advance quirks
├── GenerateImageGlyphs/  Font-rasterisation calibration tables for the Image glyph renderers
├── GenerateSFSymbols/    Regenerates the baked SF Symbol name → codepoint table
├── Profiling/            Instruments Time Profiler tooling (record.sh, drive.py,
│                         analyze_timeprofile.py, idle_cpu.py) and the RenderHarness
│                         executable (no-PTY render loop for `xctrace --launch`)
├── Smoke/                Drives the Example and Stress apps through a PTY and walks
│                         every page, to catch crashes only reachable interactively
└── TerminalProbes/       Reproducible terminal-behaviour probes backing
                          Documentation/Terminal-compatibility.md

Benchmarks/
└── TUIkitBenchmarks/     ordo-one/package-benchmark suite (color, frame buffer, image,
                          input parsing, layout, list/table, render, scroll, text width,
                          view identity); run via `TUIKIT_BENCHMARKS=1 swift package benchmark`
```

The package also vends each library as an individual product. `import TUIkit` re-exports `TUIkitCore`, `TUIkitStyling`, `TUIkitView`, and `TUIkitImage` (via `@_exported`), so the umbrella import gives full API access; import the sub-modules individually for finer control.

## Requirements

- Swift 6.2+
- macOS 14+ or Linux

## Developer notes

- Tests use Swift Testing (`@Test`, `#expect`): run with `swift test`. The suite is ~3,350 tests across ~510 suites in 341 files.
- Most tests run in parallel; a small subset that mutates global state is serialised, so the whole suite runs in a few seconds.
- Benchmarks: `TUIKIT_BENCHMARKS=1 swift package benchmark` (full suite) — see `Benchmarks/TUIkitBenchmarks`. The `TUIKIT_BENCHMARKS` flag opts the `ordo-one/benchmark` dependency into the graph; without it the default build/test stays benchmark-free (no jemalloc requirement, no plugin deprecation warnings).
- Profiling: see [Tools/Profiling/README.md](Tools/Profiling/README.md) (Instruments Time Profiler via a PTY, plus the no-PTY `RenderHarness` for `xctrace --launch`).
- The `Terminal` class handles raw mode and cursor control via POSIX `termios`.

## License

This repository has been published under the [MIT](https://mit-license.org) license.
