//  🖥️ TUIKit — Terminal UI Kit for Swift
//  State.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - App State

/// Application state that triggers re-renders when modified.
///
/// `AppState` is thread-safe: ``setNeedsRender()`` can be called from any thread
/// (e.g., from `PulseTimer` on a background queue). Internal state is protected
/// by an `NSLock`.
///
/// The `AppRunner` subscribes to state changes and re-renders when notified.
/// Property wrappers like ``State`` and ``AppStorage`` access the shared instance
/// via ``AppState.shared``.
///
/// - Important: This is framework infrastructure. Prefer using ``State`` for reactive state
///   management in your views. Direct use of `AppState` is only necessary in advanced scenarios
///   where you manage state outside the view hierarchy.
public final class AppState: Sendable {
    /// The global shared instance.
    public static let shared = AppState()

    /// Internal state protected by a lock.
    private struct StateData: Sendable {
        var needsRender = false
        var needsCacheClear = false
        var shouldExit = false
        var observers: [@Sendable () -> Void] = []
    }

    /// Lock protecting all mutable state.
    private let lock = Lock(initialState: StateData())

    /// Creates a new app state instance.
    public init() {}
}

// MARK: - Public API

extension AppState {
    /// Marks state as changed and notifies observers.
    ///
    /// This method is thread-safe and can be called from any thread.
    ///
    /// Callers that change visual output (theme, palette, appearance) do
    /// **not** need to manually clear the render cache. `RenderLoop`
    /// automatically detects environment changes via `EnvironmentSnapshot`
    /// comparison and clears the cache when needed.
    public func setNeedsRender() {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.needsRender = true
            return state.observers
        }
        // Call observers outside the lock to avoid potential deadlocks
        for observer in observers {
            observer()
        }
    }

    /// Marks state as changed and requests a full cache clear on next render.
    ///
    /// Called by `withObservationTracking` when an `@Observable` property
    /// changes. Unlike ``setNeedsRender()``, this also sets a flag that tells
    /// the render loop to clear the entire render cache, ensuring cached
    /// `EquatableView` subtrees re-render with the new model data.
    ///
    /// Thread-safe: can be called from any thread.
    public func setNeedsRenderWithCacheClear() {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.needsRender = true
            state.needsCacheClear = true
            return state.observers
        }
        for observer in observers {
            observer()
        }
    }
}

// MARK: - Internal API

extension AppState {
    /// Whether state has changed since last render.
    public var needsRender: Bool {
        lock.withLock { $0.needsRender }
    }

    /// Registers an observer to be notified of state changes.
    ///
    /// - Parameter callback: The callback to invoke on state change.
    public func observe(_ callback: @escaping @Sendable () -> Void) {
        lock.withLock { state in
            state.observers.append(callback)
        }
    }

    /// Clears all observers.
    public func clearObservers() {
        lock.withLock { state in
            state.observers.removeAll()
        }
    }

    /// Resets the needs render flag.
    public func didRender() {
        lock.withLock { state in
            state.needsRender = false
        }
    }

    /// Consumes and returns the cache-clear flag.
    ///
    /// Called by the render loop at the start of each frame. Returns `true`
    /// if any `@Observable` property changed since the last render, signaling
    /// that the render cache should be fully cleared.
    public func consumeNeedsCacheClear() -> Bool {
        lock.withLock { state in
            let value = state.needsCacheClear
            state.needsCacheClear = false
            return value
        }
    }

    /// Requests that the application's run loop exit gracefully on the next
    /// iteration.
    ///
    /// Backs the SwiftUI-parity `@Environment(\.dismiss)` action. Setting
    /// this flag makes `AppRunner` fall out of its run loop, restore the
    /// terminal to its prior state, and return from `App.main()` — exactly
    /// the same shutdown path that the built-in quit key follows. Safe to
    /// call from any thread.
    public func requestExit() {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.shouldExit = true
            return state.observers
        }
        for observer in observers {
            observer()
        }
    }

    /// Consumes and returns the exit-requested flag.
    ///
    /// Returns `true` once after ``requestExit()`` has been called. Called by
    /// `AppRunner` once per loop iteration.
    public func consumeShouldExit() -> Bool {
        lock.withLock { state in
            let value = state.shouldExit
            state.shouldExit = false
            return value
        }
    }
}

// MARK: - Environment Registration

/// Publishes the active environment during a composite view's `body` evaluation
/// so `@Environment` resolves against it.
///
/// `@State` no longer self-hydrates here: it binds to its view's *own* render
/// identity in `renderToBuffer` / `measureChild` (see
/// ``bindStateProperties(of:identity:storage:)``), not by construction order in
/// an enclosing scope. Single-threaded (`@MainActor` render), so a plain
/// `static var` is safe.
public enum StateRegistration {
    /// The active environment, set during composite view body evaluation and
    /// read by `@Environment` (and its event-closure fallback).
    nonisolated(unsafe) public static var activeEnvironment: EnvironmentValues?

    /// Evaluates `block` with `context`'s environment published as
    /// ``activeEnvironment`` (saved/restored for nesting). Needed whenever
    /// `view.body` is evaluated outside the normal `renderToBuffer` dispatch
    /// (e.g. in `measureChild`). The name is retained for its existing call sites.
    public static func withHydration<R>(context: RenderContext, _ block: () -> R) -> R {
        let previous = activeEnvironment
        activeEnvironment = context.environment
        defer { activeEnvironment = previous }
        return block()
    }
}

// MARK: - Binding

/// A two-way connection to a mutable value.
///
/// `Binding` provides read and write access to a value owned elsewhere.
/// Use bindings to connect interactive views to state.
///
/// # Example
///
/// ```swift
/// struct ContentView: View {
///     @State var selectedIndex = 0
///
///     var body: some View {
///         Menu(items: menuItems, selection: $selectedIndex)
///     }
/// }
/// ```
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    /// The getter for the value.
    private let getValue: () -> Value

    /// The setter for the value.
    private let setValue: (Value) -> Void

    /// The current value.
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue) }
    }

    /// The binding itself (for projectedValue access).
    public var projectedValue: Binding<Value> {
        self
    }

    /// Creates a binding with custom getter and setter.
    ///
    /// - Parameters:
    ///   - get: The getter closure.
    ///   - set: The setter closure.
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    /// Creates a constant binding that never changes.
    ///
    /// - Parameter value: The constant value.
    /// - Returns: A binding that always returns the given value.
    public static func constant(_ value: Value) -> Binding<Value> {
        Self(get: { value }, set: { _ in })
    }

    /// Creates a binding from an existing binding's projected value.
    ///
    /// Mirrors SwiftUI's `Binding(projectedValue:)`; used by generic code and
    /// macros that re-wrap a `$value` projection.
    ///
    /// - Parameter projectedValue: The binding to wrap.
    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    /// Derives a binding to a sub-property of the wrapped value via key path.
    ///
    /// This is what makes `$model.field` work: writing to the derived binding
    /// reads the parent value, mutates the addressed member, and writes the
    /// whole value back through this binding's setter. Matches SwiftUI's
    /// `@dynamicMemberLookup` `Binding` exactly. A `ReferenceWritableKeyPath`
    /// is a `WritableKeyPath`, so reference members work through this subscript
    /// too.
    public subscript<Subject>(
        dynamicMember keyPath: WritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        Binding<Subject>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { newValue in self.wrappedValue[keyPath: keyPath] = newValue }
        )
    }
}

// MARK: - State Property Wrapper

/// A property wrapper that stores mutable state for a view.
///
/// When the value changes, the view hierarchy is re-rendered.
/// Use `@State` for simple value types owned by a single view.
///
/// # Example
///
/// ```swift
/// struct CounterView: View {
///     @State var count = 0
///
///     var body: some View {
///         VStack {
///             Text("Count: \(count)")
///             // When count changes, view re-renders
///         }
///     }
/// }
/// ```
///
/// # Accessing the Binding
///
/// Use the `$` prefix to get a `Binding` to the state:
///
/// ```swift
/// Menu(selection: $selectedIndex)
/// ```
///
/// # Render Integration
///
/// `@State` binds to persistent storage at **render time, by the view's own
/// structural identity** — not at construction. When `renderToBuffer` (or
/// `measureChild`) processes a view, ``bindStateProperties(of:identity:storage:)``
/// walks its `@State` properties (in declaration order) and points each at the
/// `StateStorage` slot keyed by `(this view's identity, property index)`.
///
/// Keying by the view's *own* identity — rather than the scope it was
/// constructed in — is what keeps conditionally-swapped views (`if` / `switch`
/// branches, which carry distinct `#true` / `#false` identities) from aliasing
/// each other's state. Values survive view reconstruction because the same
/// identity always resolves to the same `StateBox`.
///
/// Mutations signal re-renders through `AppState.shared`.
@propertyWrapper
public struct State<Value> {
    /// Reference-typed backing whose `box` can be (re)bound to the persistent
    /// `StateStorage` slot at render time — see ``StateBacking`` and
    /// ``bindStateProperties(of:identity:storage:)``.
    private let backing: StateBacking<Value>

    /// The current state value.
    public var wrappedValue: Value {
        get { backing.box.value }
        nonmutating set { backing.box.value = newValue }
    }

    /// A binding to the state value.
    public var projectedValue: Binding<Value> {
        let backing = self.backing
        return Binding(
            get: { backing.box.value },
            set: { backing.box.value = $0 }
        )
    }

    /// Creates a state with an initial value. Binds to persistent storage at
    /// render time (keyed by the view's own identity), not at construction.
    public init(wrappedValue: Value) {
        self.backing = StateBacking(wrappedValue)
    }

    /// Creates a state with an initial value (SwiftUI-parity alias for
    /// ``init(wrappedValue:)``).
    ///
    /// Rarely written by hand, but some generic code and macros construct
    /// `@State` via `initialValue:` rather than `wrappedValue:`.
    public init(initialValue value: Value) {
        self.backing = StateBacking(value)
    }
}

// MARK: - State backing

/// Reference-typed backing for ``State`` so the storage box can be rebound at
/// render time through the value-type copy a `Mirror` walk produces.
final class StateBacking<Value> {
    let defaultValue: Value
    var box: StateBox<Value>

    init(_ value: Value) {
        self.defaultValue = value
        self.box = StateBox(value)
    }

    func bind(to storage: StateStorage, key: StateStorage.StateKey) {
        box = storage.storage(for: key, default: defaultValue)
    }
}

// MARK: - Render-time binding

/// A `@State` property that can be bound to storage at render time (mirrors
/// ``EnvironmentResolvable``).
protocol StateBindable {
    func bindState(to storage: StateStorage, identity: ViewIdentity, propertyIndex: Int)
}

extension State: StateBindable {
    func bindState(to storage: StateStorage, identity: ViewIdentity, propertyIndex: Int) {
        backing.bind(to: storage, key: StateStorage.StateKey(identity: identity, propertyIndex: propertyIndex))
    }
}

/// Binds every `@State` of `view` to storage keyed by the view's own render
/// `identity` + declaration order. Mirrors ``resolveEnvironmentProperties``.
@MainActor
func bindStateProperties<V>(of view: V, identity: ViewIdentity, storage: StateStorage) {
    let typeID = ObjectIdentifier(V.self)
    if StateBindingCache.typesWithoutState.contains(typeID) { return }
    var index = 0
    for child in Mirror(reflecting: view).children {
        if let bindable = child.value as? StateBindable {
            bindable.bindState(to: storage, identity: identity, propertyIndex: index)
            index += 1
        }
    }
    if index == 0 {
        StateBindingCache.typesWithoutState.insert(typeID)
    }
}

@MainActor
private enum StateBindingCache {
    static var typesWithoutState: Set<ObjectIdentifier> = []
}
