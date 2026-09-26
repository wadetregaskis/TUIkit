# Render Cycle

Understand how TUIkit turns your view tree into terminal output: one frame at a time.

## Overview

Every frame in TUIkit follows the same synchronous pipeline: **clear per-frame state → build environment → render the view tree → diff against previous frame → flush to terminal → track lifecycle**. Each frame evaluates `app.body` again and walks the view tree from the root, but not every body runs: a memoized subtree whose cached buffer is still valid (an `.equatable()` view, or a `ForEach` row over an `Equatable` element) is served from `RenderCache`, and nothing below it is visited (see <doc:RenderCycle#Subtree-Memoization>). Only **changed terminal lines** are written, and all writes are collected in a frame buffer and flushed as a **single `write()` syscall**.

## What Triggers a Frame

Several sources cause `RenderLoop` to produce a new frame. Most converge on two boolean checks in the main loop (`consumeResizeFlag()` and `appState.needsRender`):

| Trigger | Source | Mechanism |
|---------|--------|-----------|
| Terminal resize | `SIGWINCH` signal | `SignalManager`'s dispatch signal source sets the resize flag |
| State mutation | `@State` property change | `AppState.setNeedsRender()` sets `needsRender`; the observer wakes the loop |
| Animation clock | `CursorTimer`, at whatever interval the last frame asked for | `AppState.setNeedsAnimationTick(_:)` records WHICH clock ticked — see below |
| Focus change | `FocusManager.onFocusChange` | Resets the pulse phase and calls `appState.setNeedsRender()` |

A clock tick is deliberately not a render request. It names the clock
(`AnimationClock.cursor`, and so on) and the loop then asks whether the frame
already on screen can be brought up to date without re-rendering: the clocks
that drive pre-rendered animated cell runs are advanced by `replayAnimations`,
which splices the new cells into the existing frame, and no render happens at
all. The question is per clock because the timer posts every clock on each
wake — a ticked clock the frame left no runs for is not a reason to render,
since nothing on screen moves with it. It falls back to a full render when some
view builds its appearance from a phase as it renders (which disqualifies every
clock at once), or when no clock that ticked has runs to advance; that is the
behaviour this replaced, so the fallback is always safe. A frame that renders
for any other reason drops the pending ticks: it supersedes them.

The rest converge on boolean flags that the main loop checks each iteration. The actual rendering always happens on the main thread: signal handlers never render directly.

## The Render Pipeline

Each call to `RenderLoop.render()` executes these steps in order:

@Image(source: "render-cycle-pipeline.svg", alt: "Diagram showing the 12-step render pipeline: Step 1 clear per-frame state (key handlers, preferences, focus, status bar, app header), Step 2 begin lifecycle/state/cache tracking, Step 3 build environment with all subsystem values and services, Step 4 create render context, Step 5 evaluate scene, Step 6 render view tree, Step 7 build output lines, Step 8 begin buffered frame, Step 9 render app header and diff content, Step 10 render status bar, Step 11 flush frame, Step 12 end tracking (lifecycle onDisappear, state GC, cache cleanup).")

### Step 1: Clear Per-Frame State

Five subsystems are reset at the start of every frame:

- **`KeyEventDispatcher`**: All key handlers are removed. Views re-register them during rendering via `onKeyPress()` modifiers.
- **`PreferenceStorage`**: All preference callbacks are cleared and the stack is reset to a single empty `PreferenceValues`.
- **`FocusManager`**: All focus registrations are cleared. Focusable views re-register during rendering.
- **`StatusBarState`**: Section items are cleared. Views re-register them via `.statusBarItems()` modifiers.
- **`AppHeaderState`**: Header content is cleared. The `.appHeader()` modifier repopulates it during rendering.

Additionally, the `StatusBarState` receives a reference to the current `FocusManager` for section resolution.

This ensures that views which disappeared between frames don't leave stale handlers or registrations behind.

### Step 2: Begin Lifecycle and State Tracking

The `LifecycleManager` prepares for a new frame by clearing its `currentRenderTokens` set. The `StateStorage` clears its active identity set. The `RenderCache` begins a new render pass for cache hit/miss tracking. As views render, they add their tokens/identities to these sets. After rendering, the managers compare current and previous frames to detect which views appeared, disappeared, or had their state removed.

### Step 3: Build Environment

A fresh ``EnvironmentValues`` instance is assembled from the current subsystem state:

```swift
// Simplified from RenderLoop.buildEnvironment()
var env = EnvironmentValues()
env.statusBar           = statusBar
env.appHeader           = appHeader
env.focusManager        = focusManager
env.paletteManager      = paletteManager
env.palette             = paletteManager.currentPalette
env.appearanceManager   = appearanceManager
env.appearance          = appearanceManager.currentAppearance
env.notificationService = NotificationService.current
env.stateStorage         = tuiContext.stateStorage
env.lifecycle            = tuiContext.lifecycle
env.keyEventDispatcher   = tuiContext.keyEventDispatcher
env.mouseEventDispatcher = tuiContext.mouseEventDispatcher
env.renderCache          = tuiContext.renderCache
env.preferenceStorage    = tuiContext.preferences
env.localizationService = LocalizationService.shared
```

This environment is immutable for the duration of the frame. Runtime services (state storage, lifecycle, key dispatch, render cache, preferences) are injected here so that views and modifiers can access them through the environment rather than through `TUIContext` directly.

### Step 4: Create Render Context

A ``RenderContext`` bundles everything a view needs to render:

| Property | What |
|----------|------|
| `availableWidth` | Terminal width (mutable: containers reduce this for children) |
| `availableHeight` | Terminal height minus status bar and app header (mutable) |
| `environment` | The ``EnvironmentValues`` from step 3 |
| `tuiContext` | The `TUIContext` (lifecycle, key dispatch, preferences, state storage) |
| `identity` | The current view's structural identity (`ViewIdentity`) |

`RenderContext` is a pure data container: it does not hold a reference to `Terminal`. All terminal I/O happens after the view tree has been rendered into a ``FrameBuffer``.

The context is passed down the view tree. Each view can create a modified copy for its children: for example, a border reduces `availableWidth` by 2 before rendering its content. Container views extend the `identity` path for each child.

### Step 5: Evaluate Scene

`app.body` is evaluated fresh each frame, producing a ``WindowGroup`` that wraps the root view. The `WindowGroup` implements `SceneRenderable` and bridges from the scene layer to the view layer.

> Note: `app.body` builds new view values on every frame. `@State` values survive because `State.init` only records the default: as each view renders, `bindStateProperties(of:identity:storage:)` binds its `@State` properties to the boxes `StateStorage` keeps under the view's structural identity and each property's declaration index.

### Step 6: Render View Tree

This is where the dual rendering system kicks in. ``WindowGroup`` calls the free function `renderToBuffer()` on its content, which recursively traverses the entire view tree and produces a ``FrameBuffer``.

> See <doc:RenderCycle#The-Dual-Rendering-System> below for details on how views are dispatched.

### Step 7: Build Output Lines

The ``FrameBuffer`` is converted into terminal-ready output lines by `FrameDiffWriter.buildOutputLines()`:

1. Lines with content get their ANSI reset codes replaced with `reset + backgroundColor` (persistent background)
2. Each line is padded to full terminal width
3. Empty rows are filled with the background color
4. The total output is exactly `terminalHeight` lines

### Step 8: Begin Buffered Frame

`Terminal.beginFrame()` activates output buffering. From this point, all `Terminal.write()` calls append to an internal `[UInt8]` buffer instead of issuing syscalls.

### Step 9: Render App Header and Diff Content

If the app header has content (set by the `.appHeader()` modifier), it is rendered at the top of the terminal. Then `FrameDiffWriter.writeContentDiff()` compares the main content output lines with the previous frame and writes **only changed lines** to the terminal buffer. For mostly-static UIs, this reduces writes by ~94%.

### Step 10: Render Status Bar

The status bar renders in a separate pass but writes into the **same frame buffer**, so app header, content, and status bar are flushed together.

### Step 11: Flush Frame

`Terminal.endFrame()` writes the entire collected buffer to `STDOUT_FILENO` in a **single `write()` syscall**, then resets the buffer. This reduces per-frame syscalls from ~40+ to exactly 1.

### Step 12: End Lifecycle and State Tracking

Three managers finalize the frame:

- The **`LifecycleManager`** compares the current frame's tokens with the previous frame's. Disappeared views (tokens present last frame but absent now) fire their `onDisappear` callbacks; their tokens are removed from the appeared set, allowing future `onAppear` if they return.
- The **`StateStorage`** performs garbage collection: any state whose view identity was not marked active during this render pass, and is not under a subtree retained for the pass (the rows a lazy stack, `List` or `Table` left out of its window, a collapsed `DisclosureGroup`'s content, a memoized subtree served from the cache), is removed. This prevents memory leaks from views that have been permanently removed.
- The **`RenderCache`** removes inactive entries (subtrees no longer in the view tree) and optionally logs per-frame cache statistics.

All state changes inside the lifecycle manager are `NSLock`-protected. Callbacks execute **outside** the lock to prevent deadlocks.

### Status Bar Rendering (Step 10)

The status bar renders in a separate pass but within the same buffered frame:

1. A ``StatusBar`` view is created with the app's highlight and label colors as set; the view resolves them against the palette, with an unset color standing for the palette's accent or foreground
2. A dedicated ``RenderContext`` is created with `availableHeight` set to the status bar's height
3. `renderToBuffer()` runs on the status bar view: same dispatch as the main content
4. `FrameDiffWriter.writeStatusBarDiff()` diffs the status bar independently from the main content
5. Changed lines are written into the same frame buffer as the content

The status bar is **never affected** by view dimming or overlays. It always renders at the bottom of the terminal.

## The Dual Rendering System

TUIkit has two ways for a view to produce output:

### Path 1: Direct Rendering (Renderable)

Views that conform to `Renderable` implement `renderToBuffer(context:)` and produce a ``FrameBuffer`` directly. Their `body` property is **never called**.

This path is used by:
- **Leaf views**: ``Text``, ``Spacer``, `Divider`, ``EmptyView``
- **Private `_*Core` views**: `_VStackCore`, `_HStackCore`, `_ButtonCore`, `_CardCore`, `_ListCore`, and friends — the procedural rendering behind the public controls
- **Modifier wrappers**: `ModifiedView`, `DimmedModifier`, `OverlayModifier`, `EnvironmentModifier`, ``EquatableView``, and all lifecycle modifiers

Public controls are **not** directly `Renderable`: per the project's view-architecture rule, every public control has a real `body` that delegates to a private `_*Core` type (Path 2 below), so modifiers and environment values flow through the whole hierarchy.

### Path 2: Composition (body)

Views that are **not** `Renderable` declare their content through `body`. The rendering system recursively renders the body until it hits a `Renderable` leaf.

This path is used by:
- **Public controls**: ``VStack``, ``Button``, ``Card``, ``List``, ``Panel``, ``Alert``, ``Dialog``, ... — each wraps its private `Renderable` `_*Core`
- **Composite views**: ``Card`` returns `content.padding().border(...)`, which wraps in a `ContainerView` (whose `_ContainerViewCore` is `Renderable`)
- **User-defined views**: Your custom views compose other views in `body`

### The Dispatch Function

The free function `renderToBuffer()` is the single entry point for all view rendering:

```swift
func renderToBuffer<V: View>(_ view: V, context: RenderContext) -> FrameBuffer {
    // Priority 1: Direct rendering, through a static witness on `View`.
    // `_renderSelf` returns the buffer for a `Renderable` and nil otherwise,
    // and the result is clamped to the available space — the universal layout
    // safety net, so a view that mis-sizes itself can never overwrite a
    // sibling.
    if let buffer = V._renderSelf(view, context: context) {
        return buffer.clamped(
            toWidth: context.availableWidth, height: context.availableHeight)
    }

    // Priority 2: Composite: bind this view's @State to its own identity,
    // resolve @Environment, then recurse into body.
    if V.Body.self != Never.self {
        let childContext = context.withChildIdentity(type: V.Body.self)
        // Resolve @Environment, bind @State to this view's own identity,
        // evaluate view.body under observation tracking, mark the identity
        // active. (A `List` asking a view of your own which rows its body
        // holds evaluates that body through this same function.)
        let body = evaluateCompositeBody(of: view, context: context)
        return renderToBuffer(body, context: childContext)
    }

    // Priority 3: No rendering path: empty buffer
    return FrameBuffer()
}
```

> Note: `_renderSelf` is a **static witness**, not a `view as? Renderable`
> cast, and `_measureSelf` is its measure-side twin. The distinction is a
> performance one and it is large: the cast ran once per view per render and
> `swift_dynamicCast` under it was 4.5% of a `fanout` frame. It is the cast
> that *succeeds* most often, which is what made it expensive — a failing
> conformance check can stop at the metadata, while a succeeding one builds
> the existential. Returning the buffer rather than an `any Renderable` is the
> other half: `Self` is concrete at the call, so nothing is boxed. Do not
> implement either witness by hand; conform to `Renderable` or `Layoutable`
> and the default does it.

@Image(source: "render-cycle-dispatch.svg", alt: "Decision tree showing the dual rendering dispatch: renderToBuffer asks the static render witness first, then body recursion, then returns an empty buffer as fallback.")

> Important: If a view conforms to `Renderable`, its `body` is never evaluated. This is intentional: `Renderable` views produce output directly and don't need compositional decomposition.

## FrameBuffer

``FrameBuffer`` is the off-screen rendering primitive. It holds an array of strings (which may contain ANSI escape codes) representing terminal lines.

### Creation

Views create buffers in their `renderToBuffer(context:)`:

- ``Text``: single line with ANSI style codes
- ``Spacer``: empty lines
- ``EmptyView``: empty buffer (no lines)

### Combination

Layout containers combine child buffers using `FrameBuffer` methods:

| Method | Used by | What it does |
|--------|---------|--------------|
| `appendVertically(_:spacing:)` | `VStack` | Stacks buffers top to bottom |
| `appendHorizontally(_:spacing:)` | `HStack` | Places buffers side by side, padding shorter sides |
| `overlay(_:)` | `ZStack` | Line-by-line overlay, non-empty lines replace base |
| `composited(with:at:)` | Overlay modifier | Character-level compositing at (x, y) position |

Each of these combine operations also offset-shifts any free-floating
``OverlayLayer`` rides along with the child buffer, so a view such as a
``Picker`` drop-down can draw outside its own bounds without disturbing
sibling layout. The layers travel with their parent buffer up to the root
and are composited there in z-order; see [Overlay Layers](#Overlay-Layers)
below.

### Overlay Layers

`ZStack` honours ``View/zIndex(_:)`` on its direct children: it sorts them
in ascending z-index order (stable for ties), so a child with `.zIndex(1)`
draws on top of an earlier sibling with the default `0`.

Independent of that draw order, a view may emit an ``OverlayLayer`` —
content tagged with a level (`.popover`, `.alert`, `.modal`, …) and an
offset relative to the emitting buffer. Combine operations shift the
offset by however far the underlying lines moved, so by the time the root
``FrameBuffer`` reaches `RenderLoop.render()` every layer's offset is
absolute on the content area. `RenderLoop` then composites the layers in
ascending `(level, zIndex)` order, flipping a layer above its anchor when
it would overflow the bottom edge. Overlays are clamped and centred
against the `overlayContentHeight` environment value — the content-area
height (terminal minus status bar and app header) — so a layer never
extends behind the status bar. ``Picker``'s drop-down menu uses this
mechanism — its in-flow control stays a single line whether the menu is
open or closed.

### Diff-Based Output

After the view tree produces a ``FrameBuffer``, the `FrameDiffWriter` prepares terminal-ready output:

1. Lines with content get their ANSI reset codes replaced with `reset + backgroundColor` (persistent background)
2. Each line is padded to full terminal width
3. Empty lines are filled with the background color

The diff writer then compares each output line with the previous frame. Only lines that actually changed are written to the terminal via `Terminal.moveCursor()` + `Terminal.write()`. All writes are collected in a frame buffer and flushed as a single syscall.

## Environment Flow

Environment values flow **top-down** through the render tree via ``RenderContext``:

```
RenderLoop.buildEnvironment()
  → RenderContext carries EnvironmentValues
    → EnvironmentModifier creates a copy with modified value
      → Children see the modified value
    → Siblings and parents see the original (copy semantics)
```

The `EnvironmentModifier` (created by `.environment(_:_:)`) works by:

1. Creating a new `EnvironmentValues` with the modified key
2. Creating a new `RenderContext` with that environment via `context.withEnvironment()`
3. Rendering its content with the new context

There is no global environment: everything flows through the context parameter.

## Preference Collection

Preferences flow **bottom-up**: the reverse of environment values. Child views set values that parent views observe.

`PreferenceStorage` uses a stack-based collection mechanism:

1. `OnPreferenceChangeModifier` calls `push()`: creates a new collection scope
2. Its child tree renders, and `PreferenceModifier` calls `setValue()` on the current scope
3. `OnPreferenceChangeModifier` calls `pop()`: merges collected values into the parent scope and fires the callback

The `reduce(value:nextValue:)` function on ``PreferenceKey`` controls how multiple values from different children are combined. The default behavior: last value wins.

## ViewModifier Pipeline

TUIkit has two modifier architectures:

### Buffer Modifiers (ViewModifier protocol)

These transform a ``FrameBuffer`` after the content has rendered:

```swift
public protocol ViewModifier {
    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer
    func adjustContext(_ context: RenderContext) -> RenderContext  // default: returns context unchanged
}
```

`ModifiedView` wraps a view and a modifier. It first calls `adjustContext(_:)` to let the modifier reduce available space (e.g. padding), then renders the content, then calls `modify(buffer:context:)`. Examples:

- **`PaddingModifier`**: Adds empty lines (top/bottom) and spaces (leading/trailing) around the buffer
- **`BackgroundModifier`**: Wraps each line with background ANSI codes, padded to full width

### View-Level Modifiers (Renderable)

More complex modifiers are full `View + Renderable` implementations that control when and how their content renders:

- **`ContainerView` / `_ContainerViewCore`**: Reduces `availableWidth` by 2, renders content, adds border characters via `BorderRenderer`
- **`FlexibleFrameView`**: Modifies `availableWidth`/`availableHeight` before rendering, applies min/max constraints and alignment after
- **`OverlayModifier`**: Renders the base, offers the overlay the size the base came back at, composites via `FrameBuffer.composited(with:at:)` and cuts the result back to the base's box with `clamped(toWidth:height:)` — an overlay never resizes what it is laid over
- **`DimmedModifier`**: Renders content, then applies ANSI dim code to every line
- **`EnvironmentModifier`**: Creates modified context, renders content with it
- **``EquatableView``**: Checks `RenderCache` before rendering; returns cached buffer on hit, renders and stores on miss (see <doc:RenderCycle#Subtree-Memoization>)

## Lifecycle Tracking

The `LifecycleManager` tracks view visibility across frames using unique tokens (UUIDs):

### onAppear

The `OnAppearModifier` calls `lifecycle.recordAppear(token, action)` during rendering:

- The token is added to `currentRenderTokens` (always)
- If the token has **never appeared before**: it's added to `appearedTokens` and the action fires
- If it **has** appeared before: the action does **not** fire (prevents repeated triggers)

> Note: `onAppear` fires **synchronously** during the render traversal: not after the frame completes. This is because TUIkit uses single-pass rendering with no layout phase.

### onDisappear

The `OnDisappearModifier` does two things during rendering:

1. Registers its callback with `lifecycle.registerDisappear(token, action)`
2. Marks itself as visible with `lifecycle.recordAppear(token, {})` (empty action)

The actual `onDisappear` callback fires in step 12 (end lifecycle tracking), **after** the entire view tree has rendered.

### Task Lifecycle

The `TaskModifier` (created by `.task()`) combines appearance tracking with async tasks:

1. On first appearance: starts a `Task` with the given priority and operation
2. Registers a disappear callback that cancels the task
3. If the view reappears, a new task starts

## Output Optimization

TUIkit uses three techniques to minimize terminal I/O:

### Line-Level Diffing

`FrameDiffWriter` stores the previous frame's output lines and compares them with the new frame. Only lines that actually changed are written to the terminal. For mostly-static UIs (where only a few elements change per frame), this reduces terminal writes by ~94%.

### Frame Buffering

All terminal writes during a frame are collected in an internal `[UInt8]` buffer via `Terminal.beginFrame()` / `Terminal.endFrame()`. The entire frame is flushed to `STDOUT_FILENO` in a **single `write()` syscall**, reducing per-frame syscalls from ~40+ to exactly 1.

### Width Caching

``FrameBuffer`` caches its `width` as a stored property, recomputed only when `lines` is mutated. This eliminates hundreds of redundant ANSI-stripping regex runs per frame. The `strippedLength` property also avoids intermediate string allocations.

### What Is NOT Diffed

The view tree is re-evaluated each frame: there is no virtual DOM. However, views wrapped in ``EquatableView`` (via `.equatable()`) can skip subtree rendering when their properties are unchanged. See <doc:RenderCycle#Subtree-Memoization> below.

The alternate screen buffer (entered during setup) ensures that the user's previous terminal content is preserved and restored on exit.

## Subtree Memoization

While the view tree is reconstructed each frame, ``EquatableView`` allows **individual subtrees** to skip rendering when their inputs haven't changed. This combines the simplicity of full tree evaluation with targeted caching for expensive or static subtrees.

### How It Works

When a view is wrapped in `.equatable()`, the rendering system:

1. Looks up the cached ``FrameBuffer`` for this view's `ViewIdentity`
2. Compares the **current view value** with the cached snapshot via `Equatable.==`
3. Checks that the available **width and height** haven't changed
4. On **cache hit**: returns the cached buffer: the entire subtree is skipped
5. On **cache miss**: renders normally and stores the result

```swift
// A static info box: title and subtitle are the only inputs.
struct FeatureBox: View, Equatable {
    let title: String
    let subtitle: String

    var body: some View {
        VStack {
            Text(title).bold().foregroundStyle(.palette.accent)
            Text(subtitle).foregroundStyle(.palette.foregroundSecondary)
        }
        .padding(EdgeInsets(horizontal: 2, vertical: 1))
        .border(color: .palette.border)
    }
}

// In a parent view: cached between frames when title/subtitle are unchanged:
FeatureBox("Pure Swift", "No ncurses").equatable()
```

### Cache Invalidation

Cache invalidation is **identity-scoped** where possible, with full clears as the fallback:

| Trigger | Mechanism |
|---------|-----------|
| A `@State` change | `StateBox.value.didSet` calls `renderCache.invalidateRender(for: identity)`, which queues the identity behind a lock (the write may come from a background `Task`) and requests a render. `beginRenderPass()` drains the queue on the main actor into `clearAffected(by: identity)`, so only the affected subtree's cached buffers are invalidated. A box gets its identity and its render cache together, when `StateStorage` binds it, so a `@State` that has not been bound yet has no cache to invalidate and requests no render |
| An `@Observable` change | The body that read the property was evaluated under `withObservationTracking` at its view's identity, so the change calls `renderCache.invalidateRender(for: identity)` — the same sink as a `@State` write, and the same scope. `AppState.setNeedsRenderWithCacheClear()` → `clearAll()` is the fallback only when the render has no cache to scope to |
| A `.refreshable` run starting or ending | The run state behind `\.refresh` is the one thing about a `.refreshable` that changes without its view value changing, so a memo above it would keep serving the idle picture and the spinner would never draw. Each render binds the run state to its render cache and identity, and a run starting or ending calls `invalidateRender(for: identity)`, the same sink and scope as a `@State` write |
| A ``TimelineView``'s entry moving | The clock moves the entry a timeline's content is built for, and nothing a memo keys on moves with it: a `ForEach` row reading `timeline.date` — a list of "5 min ago" stamps — is keyed by its element, so it was served as the first entry drew it. The timeline notes its entry at its identity, as an environment modifier notes the value it injects, and a moved entry calls `clearAffected(by: identity)`, sizes included, on whichever walk sees it first. A paused schedule produces no entry and notes nothing |
| A focus move | A buffer draws the focus ring its control had while it rendered, and nothing in the key can see that the focus has moved since — the identity, the view value and the size are all unchanged by a move. So the focus manager keeps, per focus id, the identity the control last rendered at (recorded by `FocusRegistration.register`, the one registrar every interactive control goes through, and pruned to the controls that rendered this pass, like the `@FocusState` registry), and every write of the focused id calls `clearAffected(by: identity)` for the id the focus left and the id it arrived on — with its descendants, since that is where most controls draw themselves, except for a control whose focus shows only in what it draws itself (`FocusDrawnOnlyAtItself`: a `ScrollView`, whose focus is its scrollbar), where only its own buffers and those containing it go. Unlike a `@State` write it is applied at once rather than queued, so a memo still rendering above a control that auto-focused mid-walk declines to store the buffer it drew unfocused; and it asks for no frame, because a focus move already announces itself through `FocusManager.onFocusChange`, which is what schedules the repaint. This is what lets an UNFOCUSED registration be replayed rather than decline (below): the buffers it drops are exactly the ones a memo would otherwise go on serving |
| An `@AppStorage` / `@SceneStorage` write | Nothing can scope it: the wrapper is not `Equatable` so it cannot be in the memo's key, it is read as a plain field so `noteAppliedEnvironment` never sees it, and the write carries no view identity — so not even the ancestor `clearAffected` that rescues the equivalent `@State`. The setter calls `AppState.setNeedsRenderWithCacheClear()` → `clearAll()`. This is the framework's only per-user-action full clear (the `@Observable` row above scopes instead; the nearest neighbour is `LocalizationService.register`, at startup), affordable because a storage write is a user action and the flag coalesces a frame's writes into one clear — but a `Slider` bound straight to `$storage` writes per interaction tick and pays per tick |
| A global environment change | `RenderLoop` compares an `EnvironmentSnapshot` each frame and clears on mismatch: the palette (by value where it is `Equatable`, by ID where it is not — a palette edited in place keeps its ID), the appearance ID, the resolved toggle glyphs, the locale, the scene phase, and the terminal cell's geometry — its aspect and its size in pixels, read from the tty every frame and published before the comparison, since a font change moves them with nothing a memo keys on moving |
| A process-wide answer the render bakes in | The cache itself clears everything in `beginRenderPass()` when one moved since the last pass: the terminal's width claim and its reported colours (each has a generation), and the colour depth, OSC 8 link support and Kitty picture support, which have none and are read as they stand — task-local pins included — and compared with the last pass's. The depth decides how every colour is spelled, so under a runtime `ColorDepth.cap` a memo went on drawing truecolor until this; links and pictures are a margin, their renders declaring side effects and so never being stored |
| A **scoped** environment change | `EnvironmentModifier` compares the value it applied at its identity last pass; on a change it calls `clearAffected(by: identity)` — bare, always — dropping the subtree below it. A few slots do that comparison themselves instead of going through the modifier, because they write straight into the child context rather than injecting a value: the two paint slots (`ColorEnvironment`), `.tint`, the theme, and the focus publishers. The paint slots and `.tint` carry only ink and pass `keepingSizes: true` — ink moves no cell, so the memoized sizes below survive and only the buffers go. The theme keeps them only when nothing but its ink changed (palette, tint, appearance, indicator speeds): its control styles and style cascade can move cells — a plain button has no brackets, a cascaded `textCase` turns "ß" into "SS" — so a change to one of those drops the sizes too. A focus move always does, since a control may lay itself out differently while focused |
| A ``GeometryReader``'s size moving | Layout moves the size a reader hands its content, and nothing a memo below keys on moves with it: a `ForEach` row that prints `proxy.size.width` is memoized by its element and offered what its own container offers, so a sidebar's `@State` narrowing the reader — a write that clears the sidebar and what contains it, not the reader's content — left the row as it was drawn at the old width. So the reader notes the size at its identity with `noteAppliedEnvironment`, as a scoped environment change is noted, and on a change calls `clearAffected(by: identity)`, sizes included. Only a render that draws notes it: a render made to measure (a plain button's label) can offer another size, and the note answers the rest of the pass without comparing |
| An `AnyView`'s content changing type | An `AnyView` draws its content at its own identity, and so does every modifier inside it, so `AnyView(row.foregroundStyle(.red))` one frame and `AnyView(row)` the next — the usual type-erased conditional — leaves each memo below at the identity it had, keyed by a value that did not change, and it was served drawn under the modifier that had gone. The `AnyView` notes its content's type at its identity and depth (`RenderCache.noteErasedContent`, a table of its own beside the environment slots, since it is two integers where a slot hashes a key path) and clears the subtree when it changes, on whichever walk sees it first. It raises the depth for its content, as an environment modifier does, so two `AnyView`s nested at one identity note separately |

The scoped case is why the cache key carries no environment. A
`.foregroundStyle(x)` applied *above* an `.equatable()` boundary leaves the view
value identical, so a key of identity + value + size cannot see the difference
and would hand back the buffer rendered under the old `x`. Detecting the change
where it is applied costs one comparison per environment modifier per pass
rather than a fingerprint per memoized view per lookup.

One thing *is* in the key beyond identity + value + size: where the view sits in
a ``View/gradientExtent(_:)`` ramp. A spanning gradient bakes a different colour
into a view depending on where it is, and unlike an environment change nothing
is "applied" at a boundary that could notice — the ramp is the same, the view
has moved. Inserting a row at the top of a four-row ramp left every row below it
wearing the three-row ramp's ink until the frame joined the key. It is an
`Optional` that is `nil` unless a `.subtree` ramp is in force, so an ordinary
lookup compares one `nil`.

A value that is **not** `Equatable` cannot be compared. What that costs depends
on which of the two routes in the table applied it, and the two costs are
opposites.

Through `EnvironmentModifier` — every `.environment(\.slot, value)`, which is how
the style modifiers publish — the `.incomparable` answer is acted on: the
modifier carries it down as a flag on the environment, and every memo below
declines to store. Memoization is lost there, which is a performance cost rather
than a correctness one.

At a slot that notes itself and acts on `.changed` alone, there is nothing to
carry the answer, so it falls through ignored — and `noteAppliedEnvironment`
deadens the slot for good on the way past, so it can never report a change
again. The subtree then goes on wearing the ink it was painted with: stale
pixels, not lost work. Those sites stay off that path by construction rather
than by handling it — `.foregroundStyle` resolves the caller's `ShapeStyle` to
a concrete, `Equatable` `Paint` before noting it, `ThemeModifier` takes
`some Equatable`, and the focus publishers note a `Bool` — which makes the
answer unreachable rather than unhandled. That is the property to preserve when
adding another such slot.

Between these events — for example during ``Spinner`` animation frames — the cache is fully active. Static subtrees are rendered once and reused for every subsequent frame (the run loop renders only when a frame is actually due, capped at `App.maxFrameRate`).

One more thing moves a stored buffer out of date, and it is not an event: time.
A subtree whose motion is all in animated cell runs (a ``Spinner`` in a
`ForEach` row, say) is stored, since the run loop moves its runs on without
it — but its buffer shows each run at the frame of the instant it was drawn.
So every entry whose buffer carries runs keeps that instant
(`RenderCache.frameInstant`, which the loop sets before every render walks the
tree), and a lookup misses once any of its runs would show a different picture
now. Served anyway, the render put the old frame back on screen until
the run loop's next tick: every spinner in a memoized row stepped back to where
it stood when its row was stored, at every render. A run that is still showing
the same picture — the same frame, a repeated shade, a whole cycle later — is
still served, and a measure pass is served regardless, as a frame changes no
cell's width. It is paid for: a queue of memoized rows whose spinners turn at
six speeds (`Stress --session jobs`) measures +9.4% [+8.6%, +10.4%] a frame
against the stale serve, on an idle machine (2026-09-24) — each row whose run
moved is drawn again rather than served.

### What Declines the Cache

A buffer is only *stored* when serving it again would be safe. The render
declines when it:

- was produced by a **measure pass** (incomplete: interactive controls suppress
  their hit-test regions while measuring, and it was produced at a different
  size);
- contains an **overlay** (a layer the buffer has not composited yet: what it
  draws, and where, is settled by the frame rather than by the subtree);
- **read a time-varying value** or requested an animation (a view that builds
  its picture from the phase as it renders would freeze — an animation carried
  in cell runs does not decline, and is served only while its frames are
  current: see above). A ``TimelineView`` with an entry still ahead declines
  its SIZE as well as its picture, however it is measured — asked for its
  size, or rendered under a measure as a plain button renders its label: the
  clock moves the entry its content is measured for, and a size kept across
  frames would lay a timer counting from "9s" to "100s" out two cells wide.
  The two memos that keep one width for a whole collection of views — a
  windowed stack's widest row and a hugging `List`'s — keep such a size until
  the timeline's next entry instead, because refusing it sends them over
  every row on every frame;
- **registered an effect** — `onAppear`, `.task`, `onChange`, a focus
  registration, a preference write. A cache hit skips the body that registers
  them, so the frame the cache answers is a frame on which the effect does not
  exist.

The last one turns on *placement*. `Leaf().equatable().onAppear { … }` puts the
effect **above** the boundary, where it re-registers every frame and caching the
leaf below it is perfectly correct. Only an effect **inside** the memoized
subtree declines the cache.

### Registrations a Hit Makes Again

A key handler (`onKeyPress`, or the <kbd>Ctrl</kbd>-<kbd>R</kbd> binding of
`.refreshable`), a status-bar item (`.statusBarItems`), an unfocused control's
place in the focus ring (`FocusRegistration.register`), a `.defaultFocus`
declaration, the binding a `.focused(_:equals:)` makes, an inactive
`.focusSection`, a `Button`'s `.keyboardShortcut`, a hit-test handler with
the mouse features its control asks for, and the drag session's three
registrations (a drop destination, a drag auto-scroll zone, a row-reorder
host), do not decline the cache. While a memoized subtree renders on a
miss, each such registration is also recorded, and the recording is stored with
the buffer. Every hit then makes those registrations again, in the order they
were made, at the point in the walk where the subtree would have rendered. So
the key dispatcher sees the same handlers in the same precedence, the status bar
the same items with the same per-section replacement, Tab the same ring in the
same order, and the mouse dispatcher the same closure under the same id as the
region the buffer carries, whether a row rendered or was served; and a frame the
render loop walks twice gets them once per walk.

Three rules keep that equivalent to rendering:

- **The channels in force.** A registration recorded into a different key
  dispatcher or status bar from the memo's own — a `.dimmed()` subtree, or the
  page rendered beneath a modal, both of which get throwaway key channels — is
  not kept. A replay goes into the channels of the frame that serves it.
- **The focus section.** A handler or an item files under the section it
  renders in, and that section is assigned into the environment rather than
  compared, so the key would not see it change. A hit under a different section
  than the one the registrations were recorded in is a miss.
- **Whether it was a backdrop.** The page beneath a modal, and a navigation
  stack's covered root, render against a throwaway focus manager that focuses
  nothing, so their pictures show every control unfocused. An entry that
  recorded registrations remembers whether it was drawn as a backdrop, and a hit
  across that line either way is a miss (`RenderCache.EffectScope`). A backdrop
  is served as a backdrop while the sheet stays up, and the live page draws
  again, focused, when it goes: a sheet with no focusables of its own moves no
  focused id, so nothing else would invalidate it.
- **What the handler captured.** A replayed handler is the closure the subtree
  built when it rendered. `@State` and `@Observable` changes reach it as they
  reach any memo (they clear the entry), and bindings read current values. A
  value a `ForEach` row captures from *outside* its element stays as it was,
  the same captured-data hole a row's drawing already has.

A focus registration keeps declining in three cases, because in each of them
registering again is not the same thing as having rendered:

- **A control that holds the focus**, whose buffer draws the focus ring.
- **A probe's focus manager**, which renders rows the frame never draws.
- **A control named by an offered declaration** — `.focused(_:equals:)` or
  `.focusHandoff(_:_:)` — since the offer is planted above the control and
  possibly above the memo, where the key cannot see it.

A backdrop's focus manager used to be a fourth, which kept everything behind a
sheet, and under a navigation stack's pushed screen, out of the cache: drawn
afresh on every frame. Its registrations are replayed now, into the next
backdrop's throwaway manager, and the backdrop line above keeps the picture
where it belongs.

A `.focusSection` likewise declines while its section is ACTIVE, because an
active section hands its subtree a breathing ● that is drawn into the buffer and
assigned straight into the environment, where neither the key nor
`noteAppliedEnvironment` can see it change.

A `.defaultFocus` declaration is replayed for the same reason running the other
way. Everything above would go MISSING on a served frame; this one would come
BACK. The declaration carries the render generation as a focus binding does, and
the end-of-pass prune drops one the pass did not renew — taking with it the flag
that records an `.automatic` default as already applied. So a frame that served
the subtree silently un-applied the default, and the next frame the subtree
actually rendered on applied it a second time, taking the focus off wherever the
user had moved it. Renewing the declaration on a hit is what makes "apply once"
mean once whether the subtree rendered or was served; the priority is replayed
with it, so a `.userInitiated` default goes on overriding the user's moves every
frame, as it is documented to. It declines under a backdrop's or a probe's
manager — where the declaration is discarded with the throwaway manager, so a
subtree stored while it drew against one would be served against the LIVE
manager having never told it the default at all.

The binding a `.focused(_:equals:)` makes — this value of this `@FocusState`
is the id offered below — is per-frame presence of the same kind, stamped and
pruned the same way. Over a focusable it never reached a hit: the control that
claims the offer declines, as above. Over content nothing claims — a label that
becomes a field when it is edited — nothing declined, so the first served frame
lost the binding, and the app's `focus = value` found nothing to turn into a
focus intent: the field revealed by the same action never took the focus. It is
replayed now, into the manager of the frame that serves it. The offer is not,
since a hit renders nothing below the modifier that could claim it. Under a
backdrop's manager, which is never told the binding, it follows the focus
registrations' policy rather than the default's decline: the binding is still
recorded, which scopes a subtree stored from that render to the backdrop, so it
is not served to the live page after the sheet goes having told the live manager
nothing — and a memo above a `.dimmed()` one filters the throwaway entry out and
goes on caching.

A `Button`'s `.keyboardShortcut` is replayed only when the modifier carrying it
is INSIDE the memoized subtree, which is where writing the button and its
shortcut together puts it. Planted above the boundary it keeps declining, for a
reason particular to a claimable carrier: the modifier offers its shortcut to
the first control that renders under it, and on a served frame no control
renders under it at all — so the offer would stand while the replay registered
anyway, and a sibling rendered after the memo could take a shortcut that belongs
to the button inside it. The key cannot rule that out either, being made of the
view value below the modifier.

Under `TUIKIT_VERIFY_RENDER_MEMO` a hit renders fresh instead, which registers
for real, and the verifier compares the kinds and number of registrations that
render makes against the stored ones.

An inline menu's paging keys and a split view's sidebar chords are recorded the
same way, and so is the mouse. A handler id is the control's own — interned per
view identity and slot rather than counted off in registration order — so the id
baked into a stored buffer's regions still names the control it was taken from
on every frame that serves it, and the replay files that control's own closure
back under it. The per-frame feature requests that go with it (`.motion` for a
control that lifts under the pointer, `.drag` for one that tracks it) are
recorded beside it, because they lapse every walk as well: without them a page
whose only hovering control was memoized would stop being told where the pointer
is at all.

A dimmed subtree is the one place where a region and its handler part company,
and they part the right way. `.dimmed()` flattens its content to an inert
picture and drops the regions with the rest of it, while the throwaway key
channels it renders under keep everything it registered out of the memo above
it — so nothing is left for a click to reach, which is what dimming means.

The drag session's registries go with the mouse, and they are the half that
enumeration missed. `.dropDestination` makes THREE per-frame writes, not two:
the handler, the feature request, and the drop target it files with
`DragAndDropSession`, whose `beginFrame()` empties `targets`, `autoScrollZones`
and `reorderHosts` before every walk exactly as the handler table is emptied. A
served frame that replayed the first two and not the third left hit-testing
finding the region's id and `resolveTarget` finding nothing behind it: the row
looked alive and accepted nothing. `List`, `Table` and `ScrollView` write to the
same three registries — a row drop target, a reorder host, an auto-scroll zone —
and lost them the same way, the moment a memoized container could be stored at
all. All three registrations are recorded and replayed now, through
`DragAndDropRegistrar`.

`TUIKIT_VERIFY_RENDER_MEMO` could not have found this. It re-renders a served
subtree and compares the buffer, plus the kinds and number of registrations that
render *records* — and a write journalled nowhere is recorded by neither side,
while the buffer is identical whether the target was filed or not. A test for
this class has to assert on the registry, or on the gesture the registry serves.

### Keeping Nested Entries Alive

A hit at an outer `.equatable()` skips the subtree entirely, so a *nested*
`.equatable()` never marks itself active and would be garbage-collected while
still live — costing a full re-render of the inner subtree the moment the outer
value finally changes. The hit therefore declares `retainSubtree`, to both
`RenderCache` and `StateStorage`, protecting everything below it for that pass.

### When to Use `.equatable()`

| Good candidates | Why |
|----------------|-----|
| Static display views (labels, headers, feature boxes) | Properties rarely change, body is rebuilt identically each frame |
| Complex container hierarchies | Many nested views that produce the same output |
| Views next to animated siblings | A `.custom(_:)` spinner whose frames differ in width, or a pulse, re-renders the whole tree; static siblings benefit from caching. Every other spinner leaves an animated cell run and re-renders nothing, so its siblings have nothing to be spared |

| Bad candidates | Why |
|---------------|-----|
| Views that read `@State` directly | State lives in a reference-type box: the view struct compares as equal even when state changed |
| Views that change every frame | Cache overhead with no benefit |
| Tiny views (single `Text`) | Rendering cost is already minimal |

### Which Types Support `.equatable()`

The following types have `Equatable` conformance, enabling `.equatable()` on views composed of them:

**Leaf views:** ``Text``

**Container views** (conditional: `where Content: Equatable`): `VStack`, `HStack`, `ZStack`, ``Panel``, ``Card``, ``Dialog``, `ContainerView`

**Modifier views** (conditional): `FlexibleFrameView`, `OverlayModifier`, `DimmedModifier`

**Supporting types:** `TextStyle`, `Alignment`, `ContainerConfig`, `ContainerStyle`

> Note: `Button` cannot be `Equatable` because it stores a closure (`action: () -> Void`). Views containing buttons are not candidates for `.equatable()`.

### Debug Logging

Set `TUIKIT_DEBUG_RENDER=1` to enable per-frame cache statistics on stderr:

```
[RenderCache] STORE Root/MainMenuPage/FeatureBox
[RenderCache] HIT Root/MainMenuPage/FeatureBox
[RenderCache] MISS (no entry) Root/SpinnersPage/Spinner
[RenderCache] FRAME: hits: 3, misses: 2, stores: 2, clears: 0, entries: 3, hit rate: 60%
```

Redirect with `2>render.log` to capture without interfering with the TUI.

### Checking What the Cache Serves

When a view does not update, one question splits the search in two: is the
cache serving it a picture drawn from stale state, or is the new state not
reaching it at all? Two debugging switches answer it:

```sh
TUIKIT_VERIFY_RENDER_MEMO=/tmp/memo.log TUIKIT_VERIFY_MEASURE_MEMO=/tmp/memo.log swift run MyApp
```

With them on, every buffer and size the cache serves is rendered or measured
again, and the fresh result is what is drawn. So:

- **The view updates with them on.** The cache was serving it stale, and the
  log names the view's type and where it sits in the tree, with the first line
  that differed. Something that changes what the view draws is invisible to
  the cache: typically an `==` that ignores a field the view draws, or a value
  read in `body` that no state tracks — a global, a plain class, the clock.
  Route that value through `@State`, `@Environment`, an `@Observable` model or
  the view's own stored properties, and the cache will see it. If the log names
  a framework view with nothing of yours in it, that is a TUIkit bug: please
  report it with the log line.
- **It still does not update.** The cache is not the problem: the state is not
  reaching the view, and the log stays empty.

The switches are a diagnostic, never a fix. They re-render everything the cache
serves, which costs more than the cache saves, and every difference they draw
they also report. Set without a path (`=1`), they keep the findings in memory
instead (`RenderCache.renderMemoMismatches`, `measureMemoMismatches`); the
Stress harness fails a run on any.
