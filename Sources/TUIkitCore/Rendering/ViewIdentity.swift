//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewIdentity.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - View Identity

/// A stable identifier for a view based on its **structural position** in the
/// view tree.
///
/// `ViewIdentity` lets `StateStorage` persist `@State` across render passes and
/// keys the `RenderCache` memos. Each view's identity is the path of type
/// names and child indices from the root to the view.
///
/// ## Representation
///
/// The identity is stored as a **parent-linked chain of nodes** (see
/// ``IdentityNode``), one node per descent — a node holds its view's *type*
/// (an 8-byte metatype) and child index, not a string. The human-readable
/// path (`"ContentView/VStack.1/Menu"`) is rendered **on demand** by
/// ``path``, so descending the tree — which happens hundreds of times per
/// frame across the measure and render passes — never materialises or copies a
/// path string. Equality and hashing walk / fold the structural chain
/// (`ObjectIdentifier`-cheap), so `StateStorage` / `RenderCache` lookups don't
/// touch the path either.
///
/// Profiling motivated this: on the `nested` harness tree the old flat-`String`
/// path allocated ~400 KB of path strings per frame (each descent copied the
/// growing parent path, dominated by long demangled generic type names), about
/// the measured 6% of render CPU in `withChildIdentity`.
///
/// ## Construction
///
/// - ``init(rootType:)`` — the structural render root (renders its bare type
///   name, e.g. `"ContentView"`).
/// - ``child(type:index:)`` / ``child(type:)`` / ``branch(_:)`` — structural
///   descents (container child, composite body, conditional branch).
/// - ``init(path:)`` — a **raw string** identity. Retained for the empty-root
///   default and for tests; it renders as its literal string and compares by
///   it. Production builds identities structurally; structural children of a
///   raw root compose correctly because the raw string is simply the path
///   prefix. (Two identities with the same rendered `path` but different
///   construction — a structural root vs. a raw one — are *not* equal; this
///   never arises in practice, where a render tree is uniformly structural or
///   uniformly raw.)
///
/// ## Stability
///
/// The identity is **stable across render passes** as long as the tree
/// structure does not change. If a `ConditionalView` switches branches, the
/// old branch's state is invalidated (see ``isAncestor(of:)``).
public struct ViewIdentity: Hashable, Sendable, CustomStringConvertible {
    /// The structural node chain. The public face is ``path`` (rendered on
    /// demand) plus the `Hashable` / `Equatable` / ``isAncestor(of:)`` API.
    let node: IdentityNode

    /// Creates a root identity for the given view type.
    ///
    /// - Parameter type: The type of the root view.
    public init<V>(rootType type: V.Type) {
        self.node = IdentityNode(parent: nil, step: .typed(type, index: nil))
    }

    /// Creates an identity from a raw path string.
    ///
    /// Used for the empty-root default and by tests; production identities are
    /// built structurally (``init(rootType:)`` + ``child(type:index:)`` /
    /// ``branch(_:)``) so that descents don't allocate the path. A raw identity
    /// renders as its string and compares by it.
    ///
    /// - Parameter path: The full identity path.
    public init(path: String) {
        self.node = IdentityNode(parent: nil, step: .raw(path))
    }

    init(node: IdentityNode) { self.node = node }

    /// The structural path from root to this view, rendered on demand.
    ///
    /// Format: `"TypeA/TypeB.childIndex/TypeC"`. Computed from the node chain —
    /// not stored — so descents pay nothing; only focus-ID generation and
    /// debug logging materialise it.
    public var path: String { node.renderPath() }

    public var description: String { path }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        IdentityNode.structurallyEqual(lhs.node, rhs.node)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(node.cachedHash)
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
        ViewIdentity(node: node.appending(.typed(type, index: index)))
    }

    /// Type-erased form of ``child(type:index:)`` for when the child's type is
    /// only known dynamically (e.g. a `ChildView` that stores `any View`). The
    /// node keys on the same `ObjectIdentifier`, so the identity is byte-for-byte
    /// the same as the generic form for the same concrete type.
    public func child(erasedType type: Any.Type, index: Int) -> ViewIdentity {
        ViewIdentity(node: node.appending(.typed(type, index: index)))
    }

    /// Returns a child identity by appending a type name without an index.
    ///
    /// Used when traversing into a composite view's `body` where there
    /// is exactly one child (no sibling disambiguation needed).
    ///
    /// - Parameter type: The child view's type.
    /// - Returns: A new `ViewIdentity` for the child.
    public func child<V>(type: V.Type) -> ViewIdentity {
        ViewIdentity(node: node.appending(.typed(type, index: nil)))
    }

    /// Returns a child identity by appending a type name and a stable string
    /// key — the id-keyed sibling of ``child(erasedType:index:)``.
    ///
    /// Used by `ForEach` so each row's identity follows its element's `id`
    /// rather than its position: reordering, inserting or removing elements
    /// then moves each row's `@State` / focus / lifecycle with the element,
    /// as SwiftUI's `ForEach` identity contract requires. (Positional
    /// identity handed every row its *neighbour's* state on reorder.)
    ///
    /// - Parameters:
    ///   - type: The row content's type.
    ///   - key: A stable, per-sibling-unique key (the element id's string
    ///     form). Duplicate ids collapse onto one identity and alias state —
    ///     the same app bug it is in SwiftUI.
    /// - Returns: A new `ViewIdentity` for the keyed child.
    public func child(erasedType type: Any.Type, key: String) -> ViewIdentity {
        ViewIdentity(node: node.appending(.keyed(type, key: key)))
    }

    /// Returns a child identity by appending a branch label.
    ///
    /// Used by ``ConditionalView`` to distinguish between the
    /// `true` and `false` branches of an `if-else`.
    ///
    /// - Parameter label: The branch label (`"true"` or `"false"`).
    /// - Returns: A new `ViewIdentity` for the branch.
    public func branch(_ label: String) -> ViewIdentity {
        ViewIdentity(node: node.appending(.branch(label)))
    }

    /// Whether the given identity is a strict descendant of this one.
    ///
    /// Used by `StateStorage` / `RenderCache` to invalidate all state under a
    /// branch when a `ConditionalView` switches.
    ///
    /// **Structural fast path** (the only form production builds ever take — the
    /// render tree's identities are uniformly structural, rooted at
    /// ``init(rootType:)`` with typed/branch descents): decide ancestry by
    /// walking the structural parent chain. `descendant` is strictly below `self`
    /// iff `self`'s node lies on `descendant`'s *strict* parent chain — we climb
    /// `descendant`'s chain to `self`'s depth, then compare that node to `self`'s
    /// node structurally. An O(depth) pointer/value walk with **zero** path-string
    /// materialisation. This is invoked once per stored key on a `@State` /
    /// `@Published` change (`StateStorage.invalidateDescendants`), so eliminating
    /// the per-key `renderPath()` allocation matters.
    ///
    /// **Raw fall-back**: a ``init(path:)`` identity is an opaque path *string*
    /// (the whole path lives in one `.raw` node), so structural ancestry can't
    /// see its `/` / `#` component boundaries. When either chain is raw-rooted we
    /// fall back to the rendered-path prefix comparison, preserving the exact
    /// prior semantics for the empty-root default and the identity tests. (A
    /// render tree is uniformly structural or uniformly raw, so the two worlds
    /// never mix in practice.)
    ///
    /// - Parameter descendant: The identity to check.
    /// - Returns: `true` if `descendant` is strictly below this identity.
    public func isAncestor(of descendant: ViewIdentity) -> Bool {
        // Raw-rooted identities carry their path as opaque string data; only the
        // string-prefix comparison can see their component boundaries.
        guard !node.rootIsRaw, !descendant.node.rootIsRaw else {
            let prefix = path
            let candidate = descendant.path
            return candidate.hasPrefix(prefix + "/") || candidate.hasPrefix(prefix + "#")
        }

        let ancestorDepth = node.depth
        // A node is its ancestor's *strict* descendant only if it sits deeper in
        // the chain. Equal-or-shallower can't be a strict descendant.
        guard descendant.node.depth > ancestorDepth else { return false }

        // Climb the descendant's chain up to the ancestor's depth.
        var cursor: IdentityNode? = descendant.node
        while let n = cursor, n.depth > ancestorDepth {
            cursor = n.parent
        }
        guard let candidate = cursor else { return false }

        // `candidate` is the descendant's ancestor at exactly `ancestorDepth`.
        // It must structurally equal `self`'s node for `self` to be an ancestor.
        return IdentityNode.structurallyEqual(candidate, node)
    }
}

// MARK: - Structural Node

/// One link in a ``ViewIdentity``'s parent-linked chain.
///
/// Immutable and `Sendable`. A node stores its view's type (an 8-byte
/// metatype, not a name string) plus its child index, a back-pointer to its
/// parent, its depth, and a precomputed structural hash. The readable path is
/// rendered on demand from the chain (``renderPath()``); equality and hashing
/// use the chain directly.
final class IdentityNode: Sendable {
    /// One structural step.
    enum Step: Sendable {
        /// A typed descent: the view's type, and its child index when it has
        /// siblings (`nil` for a composite body's single child).
        case typed(Any.Type, index: Int?)
        /// A conditional branch (`ConditionalView`): the branch label.
        case branch(String)
        /// A typed descent disambiguated by a stable string key instead of a
        /// positional index — `ForEach` rows keyed by their element's `id`.
        case keyed(Any.Type, key: String)
        /// A raw, pre-rendered path string — the root of a non-structural
        /// identity (``ViewIdentity/init(path:)``). Only ever a chain's root.
        case raw(String)
    }

    let parent: IdentityNode?
    let step: Step
    let depth: Int
    /// Structural hash, `combine(parent.cachedHash, step)`, computed once.
    /// Feeds ``ViewIdentity/hash(into:)`` and fast-rejects unequal nodes in
    /// ``structurallyEqual(_:_:)`` — so keying a `StateStorage` / `RenderCache`
    /// dictionary never walks or renders the path.
    let cachedHash: Int

    /// Chains deeper than this stop growing (``appending(_:)`` returns the same
    /// node) instead of allocating without bound — graceful degradation for a
    /// pathological tree. 2^16 is far past any real UI, and a tree that deep
    /// would be unusably slow to render regardless.
    static let maxDepth = 1 << 16

    init(parent: IdentityNode?, step: Step) {
        self.parent = parent
        self.step = step
        self.depth = (parent?.depth ?? -1) + 1
        var hasher = Hasher()
        hasher.combine(parent?.cachedHash ?? 0)
        switch step {
        case .typed(let type, let index):
            hasher.combine(0)
            hasher.combine(ObjectIdentifier(type))
            hasher.combine(index)
        case .branch(let label):
            hasher.combine(1)
            hasher.combine(label)
        case .raw(let raw):
            hasher.combine(2)
            hasher.combine(raw)
        case .keyed(let type, let key):
            hasher.combine(3)
            hasher.combine(ObjectIdentifier(type))
            hasher.combine(key)
        }
        self.cachedHash = hasher.finalize()
    }

    /// Returns a child node, or `self` once ``maxDepth`` is reached (cap).
    func appending(_ step: Step) -> IdentityNode {
        guard depth < Self.maxDepth else { return self }
        return IdentityNode(parent: self, step: step)
    }

    /// Whether this chain is rooted in a `.raw` (opaque-string) node.
    ///
    /// A `.raw` step is only ever a chain's *root* (see ``Step/raw(_:)``), so the
    /// answer is fixed by walking to the root once. ``ViewIdentity/isAncestor(of:)``
    /// uses this to decide between the structural walk (structural chains) and the
    /// string-prefix fall-back (raw chains, whose `/` / `#` boundaries live inside
    /// the opaque string).
    var rootIsRaw: Bool {
        var cursor: IdentityNode = self
        while let parent = cursor.parent { cursor = parent }
        if case .raw = cursor.step { return true }
        return false
    }

    /// Renders the readable `"TypeA/TypeB.1/TypeC"` path. Iterative (root→leaf)
    /// so even a maximally deep chain cannot overflow the stack. A typed root
    /// (no parent) renders its bare name; deeper typed steps prepend `/`.
    func renderPath() -> String {
        var chain: [IdentityNode] = []
        var cursor: IdentityNode? = self
        while let node = cursor {
            chain.append(node)
            cursor = node.parent
        }

        var result = ""
        for node in chain.reversed() {
            switch node.step {
            case .raw(let raw):
                result += raw
            case .typed(let type, let index):
                if node.parent == nil {
                    result += cachedTypeName(type)
                } else {
                    result += "/" + cachedTypeName(type)
                    if let index { result += ".\(index)" }
                }
            case .branch(let label):
                result += "#" + label
            case .keyed(let type, let key):
                if node.parent == nil {
                    result += cachedTypeName(type)
                } else {
                    result += "/" + cachedTypeName(type)
                }
                result += "[\(key)]"
            }
        }
        return result
    }

    private static func stepsEqual(_ lhs: Step, _ rhs: Step) -> Bool {
        switch (lhs, rhs) {
        case let (.typed(lt, li), .typed(rt, ri)):
            return ObjectIdentifier(lt) == ObjectIdentifier(rt) && li == ri
        case let (.branch(ll), .branch(rl)):
            return ll == rl
        case let (.raw(lr), .raw(rr)):
            return lr == rr
        case let (.keyed(lt, lk), .keyed(rt, rk)):
            return ObjectIdentifier(lt) == ObjectIdentifier(rt) && lk == rk
        default:
            return false
        }
    }

    /// Structural equality: the chains match step-for-step. `cachedHash`
    /// fast-rejects (equal structure ⇒ equal hash, so unequal hashes ⇒ unequal
    /// without walking); a hash collision falls through to the full walk, so
    /// equality is exact — no `@State` aliasing.
    static func structurallyEqual(_ lhs: IdentityNode, _ rhs: IdentityNode) -> Bool {
        var x: IdentityNode? = lhs
        var y: IdentityNode? = rhs
        while let xn = x, let yn = y {
            if xn === yn { return true }
            if xn.cachedHash != yn.cachedHash || xn.depth != yn.depth { return false }
            guard stepsEqual(xn.step, yn.step) else { return false }
            x = xn.parent
            y = yn.parent
        }
        return x == nil && y == nil
    }
}

// MARK: - Type-name memo

/// Process-wide memo of `String(describing:)` for view types, keyed by the
/// type's `ObjectIdentifier`.
///
/// Rendering a `ViewIdentity` path stringifies each segment's type name, and
/// `String(describing:)` on a metatype demangles the runtime type name — a
/// runtime call that allocates. The set of view types is fixed at compile
/// time, so the first render per type pays the demangle and every later one is
/// a dictionary lookup.
///
/// ## Lifecycle
///
/// Never flushed — a permanent memo, not an invalidating cache, and it needs
/// no eviction:
///
/// - **Entries can't go stale.** The value (`String(describing: T)`) is a pure
///   function of the type, fixed for the life of the process. And the key
///   (`ObjectIdentifier(T.self)` — the type-metadata pointer) is stable and
///   unique process-wide: unlike `ObjectIdentifier` of a class *instance*
///   (whose address can be freed and reused), the Swift runtime never
///   deallocates *type* metadata, so two types can't collide on a key and a
///   type's key never changes. (The only way to reuse a type-metadata address
///   is unloading a dynamic image via `dlclose`, which this library never
///   does.)
/// - **It's bounded.** One entry per distinct concrete view type whose
///   identity is rendered — a set fixed at compile time (Swift has no runtime
///   type creation; generics are specialized during the build) — so it reaches
///   steady state and stops growing.
///
/// Contrast `RenderCache`, which *does* invalidate: it caches rendered buffers
/// that depend on mutable `@State` / environment, not a pure function.
private let typeNameCache = Lock<[ObjectIdentifier: String]>(initialState: [:])

/// Returns `String(describing: type)`, memoized per type (see ``typeNameCache``).
func cachedTypeName(_ type: Any.Type) -> String {
    let key = ObjectIdentifier(type)
    return typeNameCache.withLock { cache in
        if let cached = cache[key] { return cached }
        let name = String(describing: type)
        cache[key] = name
        return name
    }
}
