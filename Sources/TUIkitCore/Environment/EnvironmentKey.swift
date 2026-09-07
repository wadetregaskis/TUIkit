//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentKey.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation

// MARK: - Environment Key Protocol

/// A key for accessing values in the environment.
///
/// Conform to this protocol to define custom environment values.
///
/// # Example
///
/// ```swift
/// struct MyCustomKey: EnvironmentKey {
///     static var defaultValue: String = "default"
/// }
///
/// extension EnvironmentValues {
///     var myCustomValue: String {
///         get { self[MyCustomKey.self] }
///         set { self[MyCustomKey.self] = newValue }
///     }
/// }
/// ```
public protocol EnvironmentKey {
    /// The type of value stored by this key.
    associatedtype Value

    /// The default value for this key.
    static var defaultValue: Value { get }
}

// MARK: - Environment Values

/// A collection of environment values propagated through the view hierarchy.
///
/// Environment values flow down from parent views to child views.
/// Each view can read environment values and optionally override them
/// for its children.
public struct EnvironmentValues: @unchecked Sendable {
    /// Storage for environment values.
    private var storage: [ObjectIdentifier: Any] = [:]

    /// Creates an empty environment values container.
    public init() {}

    /// Accesses the environment value for the given key.
    ///
    /// - Parameter key: The type of the environment key.
    /// - Returns: The value for the key, or its default value if not set.
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            // Unwrap the STORAGE lookup before the cast. Doing it in one step
            // — `storage[…] as? K.Value` — reads correctly and is wrong for
            // every Optional-valued key: a miss gives `Optional<Any>.none`,
            // which casts *successfully* to `Optional<Wrapped>.none`, so the
            // `if let` binds a nil value and `defaultValue` is never reached.
            // Silently, because the only observable difference is a default
            // nobody could see was being ignored. Every Optional key in the
            // tree happens to default to nil, so nothing was wrong today —
            // but the next one to want a real default would have got nil and
            // no diagnostic.
            guard let boxed = storage[ObjectIdentifier(key)] else {
                return K.defaultValue
            }
            // A value that WAS stored, including one deliberately set to nil,
            // is what the caller asked for.
            if let value = boxed as? K.Value {
                return value
            }
            return K.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }

    /// Accesses an observable object stored by its type.
    ///
    /// Objects stored via `.environment(model)` are keyed by
    /// `ObjectIdentifier(type(of: object))`, enabling type-based lookup
    /// via `@Environment(MyModel.self)`.
    ///
    /// - Parameter type: The observable object's type.
    /// - Returns: The stored object, or `nil` if not set.
    public subscript<T: Observable>(observable type: T.Type) -> T? {
        get { storage[ObjectIdentifier(type)] as? T }
        set { storage[ObjectIdentifier(type)] = newValue }
    }

    /// The object stored under `type`, looked up without knowing the type
    /// statically — the untyped twin of ``subscript(observable:)``.
    ///
    /// It exists so `@Environment(SomeModel.self)` can hold a **metatype** for
    /// its lookup instead of a closure that captures one. That is not a style
    /// preference: a closure is two words, which pushed the property wrapper to
    /// 32 bytes, past the three-word inline buffer of an existential — and the
    /// renderer projects every `@Environment` property through `Any` to resolve
    /// it, so every such property of every view was paying a heap box on every
    /// body. With a metatype the wrapper is 16 bytes and the box is inline.
    ///
    /// - Parameter type: The observable type to look up.
    /// - Returns: The stored object, or `nil` if none was injected.
    public func storedObject(ofType type: Any.Type) -> Any? {
        storage[ObjectIdentifier(type)]
    }

    /// Creates a copy of this environment with a modified value.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the value to modify.
    ///   - value: The new value.
    /// - Returns: A new EnvironmentValues with the modified value.
    public func setting<V>(_ keyPath: WritableKeyPath<Self, V>, to value: V) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}
