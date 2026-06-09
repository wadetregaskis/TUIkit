//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewIdentity.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - View Identity

/// A stable identifier for a view based on its position in the view tree.
///
/// `ViewIdentity` enables the `StateStorage` to persist `@State` values
/// across render passes. Each view gets a unique identity derived from its
/// **structural position** — the path of type names and child indices from
/// the root to the view.
///
/// ## How It Works
///
/// During rendering, `renderToBuffer` builds the identity path incrementally:
///
/// ```
/// "ContentView"                          → root view
/// "ContentView/VStack.0"                 → first child of VStack
/// "ContentView/VStack.1"                 → second child of VStack
/// "ContentView/VStack.1/Menu"            → Menu inside second child
/// ```
///
/// Container views (`VStack`, `HStack`, `TupleView`, `ViewArray`) append
/// their child index. Leaf views append their type name. `ConditionalView`
/// appends a branch label (`"true"` or `"false"`).
///
/// ## Stability
///
/// The identity is **stable across render passes** as long as the view tree
/// structure does not change. If a `ConditionalView` switches branches, the
/// old branch's state is invalidated.
public struct ViewIdentity: Hashable, Sendable, CustomStringConvertible {
    /// The structural path from root to this view.
    ///
    /// Format: `"TypeA/TypeB.childIndex/TypeC"`
    public let path: String

    /// Creates a root identity for the given view type.
    ///
    /// - Parameter type: The type of the root view.
    public init<V>(rootType type: V.Type) {
        self.path = cachedTypeName(type)
    }

    /// Creates an identity from a raw path string.
    ///
    /// - Parameter path: The full identity path.
    public init(path: String) {
        self.path = path
    }

    public var description: String { path }
}

// MARK: - Type-name memo

/// Process-wide memo of `String(describing:)` for view types, keyed by the
/// type's `ObjectIdentifier`.
///
/// Building a `ViewIdentity` path stringifies the child view's type name on
/// every container / body descent — during BOTH the measure and the render
/// pass — and `String(describing:)` on a metatype demangles the runtime type
/// name, a runtime call that allocates a fresh `String` each time. Profiling
/// the `nested` RenderHarness tree (Time Profiler) put `String.init(describing:)`
/// at ~20% of total render time, almost entirely under
/// `RenderContext.withChildIdentity`. The set of view types is fixed at
/// compile time, so the first descent per type pays the demangle and every
/// later one is a dictionary lookup. The cached string is byte-for-byte
/// identical to `String(describing:)`, so identity paths — and therefore
/// `StateStorage` keys and focus IDs — are unchanged.
private let typeNameCache = Lock<[ObjectIdentifier: String]>(initialState: [:])

/// Returns `String(describing: type)`, memoized per type (see ``typeNameCache``).
func cachedTypeName<V>(_ type: V.Type) -> String {
    let key = ObjectIdentifier(type)
    return typeNameCache.withLock { cache in
        if let cached = cache[key] { return cached }
        let name = String(describing: type)
        cache[key] = name
        return name
    }
}

// MARK: - Public API

extension ViewIdentity {
    /// Returns a child identity by appending a type name and child index.
    ///
    /// Used by container views (`TupleView`, `ViewArray`) to assign
    /// identities to their children.
    ///
    /// - Parameters:
    ///   - type: The child view's type.
    ///   - index: The child's position within the container.
    /// - Returns: A new `ViewIdentity` for the child.
    public func child<V>(type: V.Type, index: Int) -> ViewIdentity {
        ViewIdentity(path: "\(path)/\(cachedTypeName(type)).\(index)")
    }

    /// Returns a child identity by appending a type name without an index.
    ///
    /// Used when traversing into a composite view's `body` where there
    /// is exactly one child (no sibling disambiguation needed).
    ///
    /// - Parameter type: The child view's type.
    /// - Returns: A new `ViewIdentity` for the child.
    public func child<V>(type: V.Type) -> ViewIdentity {
        ViewIdentity(path: "\(path)/\(cachedTypeName(type))")
    }

    /// Returns a child identity by appending a branch label.
    ///
    /// Used by ``ConditionalView`` to distinguish between the
    /// `true` and `false` branches of an `if-else`.
    ///
    /// - Parameter label: The branch label (`"true"` or `"false"`).
    /// - Returns: A new `ViewIdentity` for the branch.
    public func branch(_ label: String) -> ViewIdentity {
        ViewIdentity(path: "\(path)#\(label)")
    }

    /// Whether the given path is a descendant of this identity.
    ///
    /// Used by `StateStorage` to invalidate all state under a branch
    /// when a `ConditionalView` switches.
    ///
    /// - Parameter descendant: The path to check.
    /// - Returns: `true` if `descendant` starts with this identity's path.
    public func isAncestor(of descendant: ViewIdentity) -> Bool {
        descendant.path.hasPrefix(path + "/") || descendant.path.hasPrefix(path + "#")
    }
}
