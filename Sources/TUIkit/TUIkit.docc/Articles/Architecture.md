# Architecture

Understand the layer model and rendering pipeline of TUIkit.

## Overview

TUIkit is structured in six layers, each building on the one below. This clean separation makes the framework easy to extend and maintain.

## Layer Model

### 1. App Layer

The ``App`` protocol is the entry point. It defines one or more scenes that make up your application. The internal `AppRunner` manages the main run loop, terminal setup, signal handling, and event dispatching.

```
@main → App → AppRunner → Main Loop
```

### 2. View Layer

Every UI component conforms to the ``View`` protocol. Views are composed declaratively using ``ViewBuilder``, which supports:

- Single and multiple child views (up to 10)
- Conditionals (`if`, `if-else`, `if let`)
- Loops (`for-in` via ``ForEach``)

Built-in views include:

- **Content**: ``Text``, ``Image``, ``Spinner``, ``Divider``, ``EmptyView``, ``LocalizedString``
- **Interactive controls**: ``Button``, ``ButtonRow``, ``TextField``, ``SecureField``, ``Toggle``, ``Slider``, ``Stepper``, ``RadioButtonGroup``, ``Menu``, ``Picker``, ``ColorPicker``, ``ProgressView``
- **Containers**: ``Card``, ``Panel``, ``Alert``, ``Dialog``, ``NavigationSplitView``, ``TabView``, ``ContentUnavailableView``, ``StatusBar``, ``Form``, ``LabeledContent``
- **Data collections**: ``List``, ``Table``, ``Section``
- **Layout & scrolling**: ``VStack``, ``HStack``, ``ZStack``, ``LazyVStack``, ``LazyHStack``, ``Group``, ``ViewThatFits``, ``Spacer``, ``ForEach``, ``ScrollView``

### 3. Layout Layer

Layout containers use a two-pass system to distribute space among children:

1. **Measure**: Each child is proposed a size (``ProposedSize``) and returns a ``ViewSize`` with flexibility flags
2. **Render**: The parent distributes remaining space among flexible children and renders each with its final allocation

This enables spacers, flexible text fields, and proportional sizing. See <doc:LayoutSystem> for details.

### 4. Modifier Layer

View modifiers implement the ``ViewModifier`` protocol. They operate in two phases: `adjustContext(_:)` modifies the ``RenderContext`` before children render (e.g. setting environment values), and `apply(to:context:)` transforms the rendered ``FrameBuffer`` (e.g. adding padding, borders, backgrounds).

```swift
Text("Hello")
    .padding(1)
    .border(.rounded)
    .frame(width: 40)
```

### 5. State & Environment Layer

- **``State``**: Mutable per-view state that triggers re-renders
- **``Binding``**: Two-way connection to a value owned elsewhere
- **``EnvironmentValues``**: Values propagated down the view tree
- **``AppStorage``**: Persistent key-value storage. The default backend (`JSONFileStorage`) writes to an XDG config directory; `UserDefaultsStorage` is also available.

### 6. Rendering Layer

The rendering pipeline converts the view tree into terminal output:

1. **View tree traversal**: Each view produces a ``FrameBuffer``
2. **Modifier application**: Modifiers transform buffers
3. **ANSI rendering**: The `ANSIRenderer` converts colors and styles to escape codes
4. **Terminal output**: The ``FrameBuffer`` lines are written to the terminal

## Event Loop

`AppRunner` initializes all subsystems (Terminal, AppState, StatusBarState, AppHeaderState, FocusManager, ThemeManager x2, TUIContext), creates InputHandler and RenderLoop, installs POSIX signal handlers, sets up the terminal (alternate screen, raw mode, mouse tracking), registers state and focus observers, and performs an initial render before entering the main loop. PulseTimer (100 ms) and CursorTimer (50 ms) are demand-driven: each is started only while a rendered frame actually consumed it (an animating ``Spinner``, a focused ``TextField`` caret) and stopped otherwise, so a static screen drives no animation clocks.

Rendering is **demand-driven and frame-capped**, not a fixed-rate poll. With nothing pending and nothing animating, the loop blocks in `await stdinArrival.waitForArrival(...)` until woken — by terminal input, a render request, or a signal — so a static screen does zero renders and consumes no CPU. When work is pending it renders at most once per frame interval (`App.maxFrameRate`, default 60 FPS), coalescing a burst of requests into a single frame. Each iteration checks `shouldShutdown` (set by SIGINT) and the in-app dismiss flag, consumes the resize flag to invalidate the diff cache if SIGWINCH fired, drains up to 128 pending terminal events (keys and mouse) and dispatches each — keys through five handler layers, mouse through the hit-test dispatcher — then renders if a frame is due and the frame-rate cap has cleared. The wait is a real suspension point, so it releases the main actor and lets `Task`, `MainActor.run`, and `DispatchQueue.main` work run between frames. Asynchronous render triggers (animation deadlines, @State changes, SIGWINCH, focus changes) feed back into the render decision via `appState.needsRender` or `signals.requestRerender()`, both of which also `wake()` the idle-blocked loop.

@Image(source: "architecture-event-loop.svg", alt: "Flowchart of the TUIkit demand-driven event loop: after subsystems are initialised the loop checks shouldShutdown; if not shutting down it consumes the resize flag (invalidating the diff cache on SIGWINCH), drains up to 128 key and mouse events per frame and dispatches them (keys through five layers, mouse through hit-testing), renders at most once per App.maxFrameRate when a frame is due, then blocks until woken by input, a render request, or a signal before looping again. When shouldShutdown is true it cleans up and exits.")

Input dispatch uses a first-consumer-wins model. Layer 0 and Layer 3 are mutually exclusive: when a text input element (TextField/SecureField) is focused, Layer 0 runs and Layer 3 is skipped; otherwise Layer 0 is skipped and Layer 3 runs. Both use `focusManager.dispatchKeyEvent()`, which first delegates to the focused element, then handles Tab/Shift+Tab navigation, then arrow key fallback.

@Image(source: "keyboard-event-dispatch.svg", alt: "Flowchart of the 5-layer input dispatch: A hasTextInputFocus check gates Layer 0 (Text Input via focusManager.dispatchKeyEvent for TextField/SecureField). Layer 1 Status Bar Items (statusBar.handleKeyEvent). Layer 2 View Handlers (keyEventDispatcher.dispatch, deepest view first). A second hasTextInputFocus check skips Layer 3 if text input was focused. Layer 3 Focus System (focusManager.dispatchKeyEvent: focused element delegation, Tab/Shift+Tab, arrow key fallback). Layer 4 Default Bindings (q quit, t theme, a appearance). Unmatched events are dropped.")

## Focus System

The `FocusManager` manages keyboard navigation between interactive elements. Views register as focusable, and the user navigates with Tab/Shift+Tab or arrow keys.
