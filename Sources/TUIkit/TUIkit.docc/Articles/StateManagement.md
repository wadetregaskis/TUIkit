# State Management

Manage reactive state in your TUIkit application.

## Overview

TUIkit provides a state management system modeled after SwiftUI. When state changes, the view tree is automatically re-rendered.

## @State

Use ``State`` for simple values owned by a single view:

```swift
struct CounterView: View {
    @State var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") {
                count += 1  // Triggers re-render
            }
        }
    }
}
```

## Binding

``Binding`` provides a two-way connection to a value owned elsewhere. Use the `$` prefix on a `@State` property to get its binding:

```swift
struct ParentView: View {
    @State var selection = "medium"

    var body: some View {
        Picker("Size", selection: $selection) {
            Text("Small").tag("small")
            Text("Medium").tag("medium")
            Text("Large").tag("large")
        }
    }
}
```

Create constant bindings for previews or static values:

```swift
let binding = Binding.constant(42)
```

### Binding to something that might not be there

`$model.field` derives a binding to any property, including an optional one —
and a dictionary entry derives the same way, because a key that isn't there has
no value:

```swift
@State private var enabled: [String: Bool] = [:]

var body: some View {
    ForEach(features, id: \.self) { feature in
        Toggle(feature, isOn: $enabled[feature].defaulted(to: false))
    }
}
```

`$enabled[feature]` is a `Binding<Bool?>`, which ``Toggle`` cannot take: it has
to draw a checkbox one way or the other, and "absent" is not a third way to draw
it. `defaulted(to:)` decides which way absent means, at the call site where the
answer is known.

Writing through such a binding **creates** the entry — including a write of the
fallback itself, so a feature toggled on and then off leaves `[feature: false]`
rather than nothing. That is usually what "which of these are chosen" wants; a
collection that should hold *only* what was chosen is better modelled as a `Set`.

`defaulted(to:)` is TUIkit-only. The portable spelling is the longhand it saves:
`Binding(get: { enabled[feature] ?? false }, set: { enabled[feature] = $0 })`.

## @Environment

``EnvironmentValues`` provides values propagated down the view hierarchy:

```swift
struct MyView: View {
    @Environment(\.palette) var palette
    @Environment(\.statusBar) var statusBar

    var body: some View {
        Text("Themed text")
            .foregroundStyle(palette.foreground)
    }
}
```

### Defining Custom Environment Keys

```swift
struct MyCustomKey: EnvironmentKey {
    static var defaultValue: String = "default"
}

extension EnvironmentValues {
    var myCustomValue: String {
        get { self[MyCustomKey.self] }
        set { self[MyCustomKey.self] = newValue }
    }
}
```

Inject values with the `.environment()` modifier:

```swift
ContentView()
    .environment(\.myCustomValue, "custom")
```

## @AppStorage

``AppStorage`` persists values across app launches using `UserDefaults`:

```swift
struct SettingsView: View {
    @AppStorage("username") var username = "Guest"

    var body: some View {
        Text("Hello, \(username)!")
    }
}
```

### When a save fails

SwiftUI's `@AppStorage` is backed by `UserDefaults`, which for practical purposes
cannot fail. Ours falls back to a JSON file off Apple platforms — and a file in a
user-owned directory genuinely can fail to write: read-only mount, full disk, a
sandbox that denies the path.

The wrapper's signature is SwiftUI's, so its setter cannot throw. The failure
surfaces beside the API instead, through ``StorageDiagnostics``:

```swift
StorageDiagnostics.onFailure = { failure in
    Task { @MainActor in showBanner("Couldn't save settings: \(failure)") }
}
```

With no handler installed the failure is still recorded rather than dropped —
``StorageDiagnostics/lastFailure`` and ``StorageDiagnostics/failureCount`` always
reflect what happened, so an app can check after a `synchronize()`.

Reads are deliberately quieter: a value that fails to *decode* falls back to the
declared default, which is defined behaviour and sits on the per-frame render
path. Directory creation, loads, encodes and writes are all reported.

## How State Survives Re-Rendering

TUIkit re-evaluates the entire view tree on every frame. When `body` is called, views are
reconstructed from scratch. Despite this, `@State` values persist: they are never reset
to their initial value.

### Structural Identity

Each view in the tree has a **structural identity**: a path like `"ContentView/VStack.0/Menu"`.
This path is built automatically during rendering based on:
- The view's type name
- Its position among siblings (child index)
- Conditional branches (`true`/`false` for `if`/`else`)

### Persistent State Storage

All `@State` values live in one `StateStorage`, owned by the app's `TUIContext`. Each value
is held in a reference box (`StateBox`), keyed by:
- The structural identity of the view that declares the property
- The property's declaration index within that view (0, 1, 2, ...)

Declaring `@State var count = 0` stores nothing. The `init` only records the default, in a
box of its own that belongs to no identity. The property is bound when its view renders:
`bindStateProperties(of:identity:storage:)` walks the view's properties in declaration order
and points each `@State` at the box stored under the view's identity and that index. An
existing box keeps its value; a missing one is created with the default. The measure pass
binds the same way, under the same identity, so a view is measured and drawn with the same
values.

The key is the identity the view renders at, not the body it was constructed in. That is
what keeps two views an `if`/`else` or `switch` swaps between from sharing state: each branch
renders under an identity of its own.

Until its view first renders, a `@State` still points at the box its `init` made. That box
has no identity and no render cache, so a write to it requests no render. The first bind
replaces it with the stored box, so the written value is not kept either.

An `App` is not a view, so no render walk reaches it. `RenderLoop` binds the App's own
`@State` itself, at the identity at the root of the view tree, each frame before it evaluates
`app.body`, and marks that identity active so the prune at the end of the pass keeps it. A
write to it therefore invalidates the whole tree below the root, just as a write to a root
view's `@State` does.

### Re-Render Trigger

When a ``State`` value changes:

1. `StateBox.value`'s `didSet` calls `invalidateRender(for: identity)` on the box's invalidation sink: the `RenderCache` of the `TUIContext` whose `StateStorage` bound it. That call only records the identity behind a lock, so a write from a background `Task` never touches the cache, and then calls `AppState.shared.setNeedsRender()`
2. `setNeedsRender()` sets the `needsRender` flag and calls `AppState`'s observers. The observer `AppRunner` registers does not render: it only wakes the run loop, which may be blocked waiting for input. The loop checks the flag on each iteration (`foldPendingWork`), clears it and marks a frame due, and `FramePacer` renders that frame once the frame-rate cap has cleared. Any number of writes between two frames produce one frame
3. As the render pass begins, `RenderCache.beginRenderPass()` drains the recorded identities on the main actor into `clearAffected(by:)`. That drops the cached buffers and sizes of each identity, its ancestors and its descendants; sibling subtrees keep theirs
4. The App's `@State` is bound and `app.body` is evaluated again, and the tree is rendered. A memoized subtree whose cached buffer survived step 3 is served from the cache; every other view is rendered, and each composite view's `@State` is bound again to the same boxes, so it reads the values they now hold
5. The new ``FrameBuffer`` output is written to the terminal

### Garbage Collection

Views that disappear from the tree (e.g., a conditional branch switches) have their state
automatically cleaned up at the end of each render pass. `ConditionalView` also immediately
invalidates the inactive branch's state to prevent stale values.

This is simple and predictable: the view tree is fully re-evaluated each frame (no virtual DOM), with persistent state. Terminal output is then diffed at the line level: only changed lines are written. See <doc:RenderCycle> for details on the output optimization pipeline.
