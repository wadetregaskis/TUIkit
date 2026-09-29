//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentProperty.swift
//
//  Created by LAYERED.work
//  License: MIT

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
    // How the value is looked up: by key path, or — for an observable object —
    // by its type, through ``EnvironmentValues/storedObject(ofType:)``. Exactly
    // one is set.
    //
    // Each is one pointer wide, deliberately. The observable lookup used to be a
    // `(EnvironmentValues) -> Value?` closure, which is two words and took the
    // whole wrapper to 32 bytes — past the 24-byte inline buffer of an
    // existential. `resolveEnvironmentProperties` reaches every `@Environment`
    // property through `Mirror`, whose children hand each one back as `Any`,
    // so an over-large wrapper meant a heap allocation per property per view
    // per `body`. Two optionals and the box are 24 bytes.
    //
    // Two optionals rather than an enum of the two, which is what this was:
    // the enum is generic (it is `Value`'s), so the per-pass memos' value hash
    // could not read it — a generic enum's inactive payload is not reliably
    // written — and every view holding an `@Environment` bypassed both memos.
    // An optional of one pointer (a key path's reference, a metatype) spells
    // `nil` in that pointer's spare values and writes it whole, so the hash
    // reads these, and the wrapper, as plain words.

    /// The key path to read, or `nil` for an observable lookup.
    private let keyPath: KeyPath<EnvironmentValues, Value>?

    /// The observable type to look up, or `nil` for a key-path lookup.
    private let observableType: Any.Type?

    /// Reference box holding the environment captured at the owning view's
    /// render. Shared with closures that capture the view, so they see the same
    /// resolved environment. Populated by ``resolveEnvironmentProperties(of:in:)``.
    private let box = EnvironmentBox()

    /// Creates an environment property wrapper for the given key path.
    ///
    /// - Parameter keyPath: The key path to the environment value to read.
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
        self.observableType = nil
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
        self.keyPath = nil
        self.observableType = type
    }

    /// The current environment value.
    ///
    /// Prefers the environment captured into `box` at the owning view's render
    /// (valid inside closures); falls back to the active render environment, then
    /// the framework defaults.
    public var wrappedValue: Value {
        let env = box.environment ?? StateRegistration.activeEnvironment ?? EnvironmentValues()
        if let keyPath { return env[keyPath: keyPath] }
        guard let type = observableType, let object = env.storedObject(ofType: type) as? Value else {
            fatalError(
                "@Environment(\(Value.self).self): "
                    + "No object of type \(Value.self) found in the environment. "
                    + "Did you forget to call .environment(model)?"
            )
        }
        return object
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
/// per view, just before evaluating its `body`. To keep that cheap it caches,
/// per view *type*, whether the type has any `@Environment` properties at all —
/// types that have none (the overwhelming majority of leaf/layout views) skip
/// reflection entirely after the first sighting. A type that has some is
/// reflected on every render.
///
/// Why not cache the properties' key paths instead, so a type that has them
/// skips `Mirror` too? That was tried, and measured -11.6% on a menu frame whose
/// rows each had three `@Environment` properties. It needs the standard
/// library's `_forEachFieldWithKeyPath`, and that is `@_spi(Reflection)`: Apple's
/// SDKs build `Swift` from its public interface, which has no SPI in it, so
/// Xcode's own toolchain does not see the function at all and TUIkit stopped
/// building there. Only swift.org toolchains, which ship the private interface,
/// compiled it. There is no public API that yields a stored property's key path,
/// so reflection per render is the price of building with Xcode.
@MainActor
public func resolveEnvironmentProperties<V>(of view: V, in environment: EnvironmentValues) {
    let typeID = ObjectIdentifier(V.self)
    if EnvironmentResolutionCache.typesWithoutEnvironment.contains(typeID) { return }

    var found = false
    for child in Mirror(reflecting: view).children {
        if let resolvable = child.value as? EnvironmentResolvable {
            resolvable.resolveEnvironment(environment)
            found = true
        }
    }
    if !found {
        EnvironmentResolutionCache.typesWithoutEnvironment.insert(typeID)
    }
}

/// Per-type memo of which view types have no `@Environment` properties, so they
/// can skip reflection on every subsequent render. Render is single-threaded
/// (`@MainActor`), so a plain `Set` is sufficient.
@MainActor
private enum EnvironmentResolutionCache {
    static var typesWithoutEnvironment: Set<ObjectIdentifier> = []
}
