//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentProperty.swift
//
//  Created by LAYERED.work
//  License: MIT

@_spi(Reflection) import Swift

import Observation
import TUIkitCore

// MARK: - Environment Property Wrapper

/// A property wrapper that reads a value from the environment.
///
/// Use `@Environment` to access environment values in your views.
/// The value is read dynamically during `body` evaluation, so it
/// always reflects the current environment (including any modifications
/// from parent views).
///
/// # KeyPath-Based Access
///
/// ```swift
/// struct MyView: View {
///     @Environment(\.palette) var palette
///     @Environment(\.isDisabled) var isDisabled
///
///     var body: some View {
///         Text("Hello")
///             .foregroundColor(palette.accent)
///     }
/// }
/// ```
///
/// # Type-Based Access (Observable Objects)
///
/// ```swift
/// @Observable
/// class AppModel {
///     var count = 0
///     init() {}
/// }
///
/// struct ContentView: View {
///     @Environment(AppModel.self) var model
///
///     var body: some View {
///         Text("Count: \(model.count)")
///     }
/// }
/// ```
///
/// # How It Works
///
/// The rendering pipeline resolves each view's environment *at render time*
/// (after any `.environment()` modifiers applied by parents) and stores it in a
/// reference box held by this wrapper — see `resolveEnvironmentProperties(of:in:)`,
/// which the renderer calls before evaluating a view's `body`. Because the box
/// is a reference shared with any closure that captures the view (a `Button`
/// action, an `.onKeyPress` handler, a `Binding`'s `set:`), `@Environment`
/// resolves correctly **inside those closures too** — not only during `body` —
/// matching SwiftUI. (Reading the active environment lazily at access time, the
/// old behaviour, returned defaults in deferred closures.)
///
/// As a fallback, when no box has been populated (a view rendered before the
/// resolve pass, or read outside the render tree as in tests), it reads the
/// active render environment, and finally the framework defaults.
@propertyWrapper
public struct Environment<Value> {
    /// Strategy for resolving the environment value.
    private enum LookupStrategy {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case observable((EnvironmentValues) -> Value?)
    }

    /// The lookup strategy used by this instance.
    private let strategy: LookupStrategy

    /// Reference box holding the environment captured at the owning view's
    /// render. Shared with closures that capture the view, so they see the same
    /// resolved environment. Populated by ``resolveEnvironmentProperties(of:in:)``.
    private let box = EnvironmentBox()

    /// Creates an environment property wrapper for the given key path.
    ///
    /// - Parameter keyPath: The key path to the environment value to read.
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.strategy = .keyPath(keyPath)
    }

    /// Creates an environment property wrapper that reads an observable
    /// object by its type.
    ///
    /// The object must have been injected via `.environment(model)`.
    ///
    /// ```swift
    /// @Environment(AppModel.self) var model
    /// ```
    ///
    /// - Parameter type: The observable type to look up.
    public init(_ type: Value.Type) where Value: Observable {
        self.strategy = .observable { env in
            env[observable: type]
        }
    }

    /// The current environment value.
    ///
    /// Prefers the environment captured into `box` at the owning view's render
    /// (valid inside closures); falls back to the active render environment, then
    /// the framework defaults.
    public var wrappedValue: Value {
        let env = box.environment ?? StateRegistration.activeEnvironment ?? EnvironmentValues()
        switch strategy {
        case .keyPath(let keyPath):
            return env[keyPath: keyPath]
        case .observable(let lookup):
            guard let object = lookup(env) else {
                fatalError(
                    "@Environment(\(Value.self).self): "
                        + "No object of type \(Value.self) found in the environment. "
                        + "Did you forget to call .environment(model)?"
                )
            }
            return object
        }
    }
}

// MARK: - Render-time resolution

/// A reference box holding the environment a view's ``Environment`` wrapper was
/// resolved against. Reference semantics are the whole point: a `@Environment`
/// wrapper copied into a closure shares this box, so the closure reads the value
/// captured at render even though it runs later.
final class EnvironmentBox {
    var environment: EnvironmentValues?
}

/// A `@Environment` wrapper that can be handed its resolved environment.
///
/// Existential over the wrapper's `Value` so the renderer can populate every
/// `@Environment` on a view without knowing each one's type.
public protocol EnvironmentResolvable {
    /// Hands this property wrapper the environment to read from.
    ///
    /// Called by the renderer on every `@Environment` it finds on a view,
    /// immediately before the view's `body` runs, so a wrapper answers from
    /// the values in force at *its* position in the tree. Outside a render
    /// pass a wrapper has no environment and reads its default — which is why
    /// an event closure must capture what it needs at render time rather than
    /// reaching for `@Environment` when the event arrives.
    ///
    /// - Parameter environment: The values in force where the view sits.
    func resolveEnvironment(_ environment: EnvironmentValues)
}

extension Environment: EnvironmentResolvable {
    public func resolveEnvironment(_ environment: EnvironmentValues) {
        box.environment = environment
    }
}

/// Populates every `@Environment` property of `view` with `environment`, so the
/// view (and any closure that captures it) resolves them against the environment
/// active at *this* view's render.
///
/// Mirrors SwiftUI's `DynamicProperty` update step. The renderer calls this once
/// per view, just before evaluating its `body`, which makes it one of the
/// most-executed functions in the framework and its cost worth stating.
///
/// Every view type is resolved from a per-type memo, decided on its first
/// sighting and one of three answers:
///
/// * **No `@Environment` at all** — the overwhelming majority of leaf and layout
///   views. A `Set` membership test and nothing else, forever.
/// * **Key paths** — the properties' key paths, found once and applied on every
///   later render.
/// * **Reflect every time** — the fallback for a type
///   `_forEachFieldWithKeyPath` declines to enumerate. Also memoized, so such a
///   type does not re-attempt the key-path walk before each `Mirror` walk.
///
/// The key paths exist to keep `Mirror` off the per-render path, and the reason
/// is how much each of its steps costs rather than how many there are. On the
/// `menu` tree this function is called 35 times a frame, 74% of which the first
/// bucket answers outright — so it reflects **nine times, over thirty-six
/// children in total**, and those thirty-six operations were **12.4% of the
/// frame** (`AnyIterator.next()` 8.8%, this function 3.6%). Roughly 3.4 µs per
/// walk. Every step of `Mirror.children` builds a `Child`, which means a String
/// allocated for the field's name and the field's value boxed into an `Any`,
/// on top of the reflective field projection itself.
///
/// Replacing it with cached key paths is -11.6% on that tree over 9 of 9 paired
/// reps, and the whole run shortens from 14,687 ms to 13,245 ms. What the
/// before/after does NOT show is any change in generic metadata instantiation
/// (`_swift_getGenericMetadata` and friends move ~1,350 ms to ~1,250 ms) or in
/// ARC traffic (`swift_retain`/`swift_release` are flat, marginally up). An
/// earlier draft of this comment blamed metadata instantiation; the measurement
/// says otherwise, and the cost stays inside `AnyIterator.next()`, which is
/// specialized into this binary and does not decompose further in the profile.
///
/// A key path is the right cache because it is the only thing `Mirror` cannot
/// give: `Mirror` yields a *value*, which is useless on the next render of a
/// freshly constructed view, whereas a key path is an accessor that outlives the
/// instance it was found on. `_forEachFieldWithKeyPath` is `@_spi(Reflection)`
/// rather than fully public API; the `Mirror` path is kept, and is what a type it
/// refuses still uses.
@MainActor
public func resolveEnvironmentProperties<V>(of view: V, in environment: EnvironmentValues) {
    let typeID = ObjectIdentifier(V.self)
    if EnvironmentResolutionCache.typesWithoutEnvironment.contains(typeID) { return }
    if let paths = EnvironmentResolutionCache.resolvablePaths[typeID] {
        resolve(paths, of: view, in: environment)
        return
    }
    if EnvironmentResolutionCache.typesNeedingMirror.contains(typeID) {
        resolveByMirror(of: view, in: environment)
        return
    }
    classify(view, in: environment, typeID: typeID)
}

/// Hands `environment` to the `@Environment` property at each of `paths`.
///
/// The downcast is sound by construction: the paths were found on `V` itself and
/// are only ever read back under the same `ObjectIdentifier(V.self)` that stored
/// them. `AnyKeyPath` is a class, so this is a pointer bitcast in release rather
/// than a dynamic cast on the hot path.
@MainActor
private func resolve<V>(
    _ paths: [AnyKeyPath], of view: V, in environment: EnvironmentValues
) {
    for path in paths {
        let typed = unsafeDowncast(path, to: PartialKeyPath<V>.self)
        if let resolvable = view[keyPath: typed] as? EnvironmentResolvable {
            resolvable.resolveEnvironment(environment)
        }
    }
}

/// Decides, once, which of the three memo answers `V` gets — and resolves this
/// first sighting on the way.
///
/// Deliberately NOT inlined into ``resolveEnvironmentProperties(of:in:)``: it
/// runs once per view type and never again, while its caller runs once per view
/// per render and sits on the recursion that deep view trees pay a stack frame
/// for at every level. The same trade `measureCompositeBody` makes.
@inline(never)
@MainActor
private func classify<V>(
    _ view: V, in environment: EnvironmentValues, typeID: ObjectIdentifier
) {
    var paths: [AnyKeyPath] = []
    let walked = _forEachFieldWithKeyPath(of: V.self) { _, keyPath in
        if view[keyPath: keyPath] is EnvironmentResolvable { paths.append(keyPath) }
        return true
    }
    guard walked else {
        // Reflect from here on — but only if reflection finds something. A type
        // the key-path walk refuses AND that has no `@Environment` belongs in
        // the cheapest bucket, not the dearest.
        if resolveByMirror(of: view, in: environment) {
            EnvironmentResolutionCache.typesNeedingMirror.insert(typeID)
        } else {
            EnvironmentResolutionCache.typesWithoutEnvironment.insert(typeID)
        }
        return
    }
    guard !paths.isEmpty else {
        EnvironmentResolutionCache.typesWithoutEnvironment.insert(typeID)
        return
    }
    EnvironmentResolutionCache.resolvablePaths[typeID] = paths
    resolve(paths, of: view, in: environment)
}

/// The reflective walk, kept for the types `_forEachFieldWithKeyPath` declines.
///
/// - Returns: Whether it found any `@Environment` property to resolve.
@MainActor
@discardableResult
private func resolveByMirror<V>(of view: V, in environment: EnvironmentValues) -> Bool {
    var found = false
    for child in Mirror(reflecting: view).children {
        if let resolvable = child.value as? EnvironmentResolvable {
            resolvable.resolveEnvironment(environment)
            found = true
        }
    }
    return found
}

/// Per-type memo of how each view type's `@Environment` properties are reached.
///
/// Three buckets, checked in descending order of how often they answer, so the
/// commonest case is the cheapest test. Render is single-threaded
/// (`@MainActor`), so plain collections are sufficient.
@MainActor
private enum EnvironmentResolutionCache {
    /// Types with no `@Environment` property. Checked first: on a menu frame it
    /// answers 74% of all calls.
    static var typesWithoutEnvironment: Set<ObjectIdentifier> = []

    /// The key paths of each type's `@Environment` properties.
    static var resolvablePaths: [ObjectIdentifier: [AnyKeyPath]] = [:]

    /// Types `_forEachFieldWithKeyPath` will not enumerate, which fall back to
    /// `Mirror`. Recorded so the refused walk is attempted once, not per render.
    static var typesNeedingMirror: Set<ObjectIdentifier> = []
}
