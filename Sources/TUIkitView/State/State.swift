//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// (e.g., from an animation timer on a background queue). Internal state is protected
/// by an `NSLock`.
///
/// The `AppRunner` subscribes to state changes and re-renders when notified.
/// Property wrappers like ``State`` and ``AppStorage`` access the shared instance
/// via `AppState.shared`.
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
        var pendingTransaction: Transaction?
        var pendingAnimationClocks: Set<AnimationClock> = []
        var needsCacheClear = false
        var shouldExit = false
        var observers: [@Sendable () -> Void] = []

        /// Stamps the change being recorded with whatever ``Transaction`` is in
        /// force where it was made — the seam that makes
        /// ``withAnimation(_:_:)`` reach the render that follows it.
        ///
        /// Only an *explicit* transaction is recorded. A plain
        /// `setNeedsRender()` leaves whatever an earlier animated change put
        /// here, because the two mean different things: without this,
        /// `withAnimation { a = 1 }` followed by an unrelated `b = 2` before
        /// the next frame would drop the animation on the floor.
        mutating func recordAmbientTransaction() {
            guard let ambient = Transaction.ambient else { return }
            pendingTransaction = ambient
        }
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
            state.recordAmbientTransaction()
            return state.observers
        }
        // Call observers outside the lock to avoid potential deadlocks
        for observer in observers {
            observer()
        }
    }

    /// Records that an animation clock ticked, WITHOUT asking for a render.
    ///
    /// The distinction is the whole point. A state change means the view tree
    /// now describes something different, so it has to be walked again. A clock
    /// tick means only that time passed: the tree describes exactly what it did
    /// a moment ago, and the sole difference on screen is the next frame of
    /// whatever cells declared themselves animated. Conflating the two is what
    /// made a blinking cursor cost a full measure-layout-render pass 20 times a
    /// second — see ``AnimatedCellRun``.
    ///
    /// The run loop tries to serve these by replaying the animated cells of the
    /// frame already on screen. If it cannot — because some view still animates
    /// the old way, by reading the phase during its own render — it falls back
    /// to a full render, which is exactly the behaviour this replaces.
    public func setNeedsAnimationTick(_ clock: AnimationClock) {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.pendingAnimationClocks.insert(clock)
            return state.observers
        }
        for observer in observers {
            observer()
        }
    }

    /// Takes the transaction the pending change was made under, clearing it.
    ///
    /// Called once by the run loop at the start of each render pass. The pass
    /// publishes it as ``EnvironmentValues/transaction`` so every view affected
    /// by the change can see how it was meant to arrive.
    ///
    /// A frame coalesces every change made since the last one, so a frame with
    /// two animated changes in it renders both under the *last* transaction —
    /// there is one pass and it can only run under one. Two animations of
    /// genuinely different lengths in one frame want
    /// ``View/animation(_:value:)``, which scopes the animation to a subtree
    /// and a value rather than to the whole update.
    public func consumePendingTransaction() -> Transaction? {
        lock.withLock { state in
            defer { state.pendingTransaction = nil }
            return state.pendingTransaction
        }
    }

    /// Takes the clocks that have ticked since the last call, clearing them.
    public func consumePendingAnimationClocks() -> Set<AnimationClock> {
        lock.withLock { state in
            defer { state.pendingAnimationClocks = [] }
            return state.pendingAnimationClocks
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
            state.recordAmbientTransaction()
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

// MARK: - Render Invalidation Sink

/// Receives render-invalidation requests raised by state mutations.
///
/// A `@State` write fires ``StateBox``'s `didSet`, which must (a) drop the
/// cached buffers for the affected subtree and (b) request a re-render. The
/// write can originate off the main actor (a `@State` mutated from a background
/// `Task`), and ``RenderCache`` is single-threaded — so the box must not touch
/// the cache directly. Instead it calls this sink, whose conformer records the
/// invalidation behind a lock and applies it on the main-actor frame boundary.
///
/// ``RenderCache`` conforms (it is the per-context object that owns the cached
/// buffers, so routing through it keeps each context's invalidations isolated).
/// Keeping the seam a protocol lets ``StateBox`` stay free of both the concrete
/// cache type and the app-state singleton name.
public protocol RenderInvalidationSink: AnyObject, Sendable {
    /// Records that the subtree rooted at `identity` (or the whole cache, when
    /// `identity` is `nil`) needs its cached buffers dropped, and requests a
    /// re-render. Thread-safe; the cache mutation itself is deferred to the
    /// next main-actor frame boundary.
    func invalidateRender(for identity: ViewIdentity?)
}

// MARK: - Environment Registration

/// Publishes the active environment during a composite view's `body` evaluation
/// so `@Environment` resolves against it.
///
/// `@State` no longer self-hydrates here: it binds to its view's *own* render
/// identity in `renderToBuffer` / `measureChild` (see
/// `bindStateProperties(of:identity:storage:)`), not by construction order in
/// an enclosing scope.
public enum StateRegistration {
    /// The environment of the `body` currently being evaluated, or `nil`
    /// outside one.
    ///
    /// This is a **fallback**, not the mechanism. `@Environment` resolves
    /// primarily from a per-view reference box that
    /// `resolveEnvironmentProperties(of:in:)` fills immediately before `body` —
    /// the equivalent of SwiftUI updating a `DynamicProperty` before its view's
    /// body runs, and what makes an `@Environment` read work inside a captured
    /// closure. This value covers only the paths that publish an environment
    /// without running that resolution: the measure pass
    /// (`measureCompositeBody`), `App.body` (an `App` is not a `View`, so
    /// nothing populates its boxes), and `@FocusState` reaching for a
    /// `FocusManager` before a `.focused` modifier has wired one.
    ///
    /// It is a `@TaskLocal` rather than a mutable global because the scoping is
    /// what the render pipeline actually wants — a value that exists for the
    /// duration of one `body` evaluation and nests — and because a global
    /// cannot express that safely under concurrency. Rendering is
    /// single-threaded on the run loop, so this is not fixing a production
    /// race; it removes one that the *tests* could hit, since suites run in
    /// parallel and more than one of them publishes an environment. A task
    /// local is per-task, so no test can write into another's scope.
    ///
    /// Only readable directly; publish it with ``withHydration(context:_:)`` or
    /// ``withHydration(environment:_:)``.
    @TaskLocal public static var activeEnvironment: EnvironmentValues?

    /// Evaluates `block` with `context`'s environment published as
    /// ``activeEnvironment``. Needed whenever `view.body` is evaluated outside
    /// the normal `renderToBuffer` dispatch (e.g. in `measureChild`). The name
    /// is retained for its existing call sites.
    ///
    /// Nesting works by construction: an inner scope shadows an outer one and
    /// the outer value is restored when it returns.
    public static func withHydration<R>(context: RenderContext, _ block: () -> R) -> R {
        withHydration(environment: context.environment, block)
    }

    /// The environment-only form, for publishers that have no `RenderContext` —
    /// `App.body`, and tests exercising the fallback directly.
    public static func withHydration<R>(
        environment: EnvironmentValues?, _ block: () -> R
    ) -> R {
        $activeEnvironment.withValue(environment, operation: block)
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

    /// The transaction writes through this binding are made under, or `nil`
    /// for "whatever is ambient".
    ///
    /// Optional, where ``transaction`` is not: an empty `Transaction` is a
    /// STATEMENT — "this change is not animated, whatever the caller said" —
    /// and a plain binding must not make it. Stored as `nil`, a write inside
    /// `withAnimation { … }` is animated; stored as `Transaction()`, it would
    /// silently override the caller. Same third-state shape as `\.font`'s
    /// `Font??`.
    private var declaredTransaction: Transaction?

    /// The transaction writes through this binding are made under.
    ///
    /// Reads as an empty transaction until one is set, which is what SwiftUI
    /// reports for a binding that has never been given one.
    public var transaction: Transaction {
        get { declaredTransaction ?? Transaction() }
        set { declaredTransaction = newValue }
    }

    /// The current value.
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set {
            guard let declaredTransaction else {
                setValue(newValue)
                return
            }
            withTransaction(declaredTransaction) { setValue(newValue) }
        }
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

    /// A binding whose writes are made under `animation`, so a control that
    /// knows nothing about animation still animates what it changes.
    ///
    /// ```swift
    /// Toggle("Expanded", isOn: $isExpanded.animation(.easeInOut))
    /// ```
    ///
    /// The third place an animation can be stated, and the one for when
    /// neither the change nor the view is yours to annotate: the *binding* is.
    /// Reads are untouched — only the write is wrapped.
    ///
    /// - Parameter animation: How to animate changes made through the returned
    ///   binding. `nil` makes them explicitly un-animated.
    /// - Returns: A binding that writes inside ``withAnimation(_:_:)``.
    public func animation(_ animation: Animation? = .default) -> Self {
        // Through the transaction, because that is what it IS —
        // `withAnimation(a)` is `withTransaction(Transaction(animation: a))`,
        // so writing the wrapping by hand here was the same mechanism spelled
        // twice. `nil` still means explicitly un-animated: it is a stated
        // transaction whose animation is none, not the absence of one.
        transaction(Transaction(animation: animation))
    }

    /// A binding whose writes are made under `transaction`.
    ///
    /// The general form of ``animation(_:)`` — reach for it when the thing to
    /// state is not the animation but `disablesAnimations`, so a control's
    /// writes opt out of whatever the caller is animating.
    ///
    /// Reads are untouched; only the write is wrapped.
    ///
    /// - Parameter transaction: The context to write under.
    /// - Returns: A binding that writes inside ``withTransaction(_:_:)``.
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        var copy = self
        copy.transaction = transaction
        return copy
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
/// `measureChild`) processes a view, `bindStateProperties(of:identity:storage:)`
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

/// A property that needs only a *stable id* derived from its view's render
/// identity — not a full ``StateStorage`` slot — bound at render time.
///
/// `@FocusState` (in the higher-level `TUIkit` module, where the focus system
/// lives) uses this: it keeps its per-value focus mappings on the persistent
/// `FocusManager`, keyed by an id that must stay the same across frames so a
/// control's focusID and the "which value is focused?" reverse-lookup remain
/// stable. The id is derived from the owning view's identity + the property's
/// declaration order, exactly like a `StateBindable` slot key. Public so a
/// type in a module layered above `TUIkitView` can participate in the same
/// `bindStateProperties(of:identity:storage:)` walk that binds `@State`.
public protocol RenderIdentityBindable {
    /// Binds this property to a stable id derived from its view's render
    /// `path` and declaration `propertyIndex`.
    func bindRenderIdentity(path: String, propertyIndex: Int)
}

/// Binds every `@State` (and ``RenderIdentityBindable``, e.g. `@FocusState`)
/// property of `view` to storage/ids keyed by the view's own render `identity`
/// + declaration order. Mirrors ``resolveEnvironmentProperties``.
///
/// `view` is not constrained to `View`: the render loop binds an `App`'s
/// `@State` with it too, at the root identity, before evaluating `App.body`.
@MainActor
package func bindStateProperties<V>(of view: V, identity: ViewIdentity, storage: StateStorage) {
    let typeID = ObjectIdentifier(V.self)
    if StateBindingCache.typesWithoutState.contains(typeID) { return }
    var index = 0
    for child in Mirror(reflecting: view).children {
        if let bindable = child.value as? StateBindable {
            bindable.bindState(to: storage, identity: identity, propertyIndex: index)
            index += 1
        } else if let idBindable = child.value as? RenderIdentityBindable {
            // Shares the same declaration-order counter as @State so mixing
            // @State and @FocusState in one view keeps stable, non-colliding
            // keys regardless of their relative order.
            idBindable.bindRenderIdentity(path: identity.path, propertyIndex: index)
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
