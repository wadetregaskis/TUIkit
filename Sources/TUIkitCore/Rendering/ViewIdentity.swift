//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// `IdentityNode`), one node per descent — a node holds its view's *type*
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

    /// The identity-chain step directly below `ancestor` on this identity's
    /// chain — the routing answer of "Locating things without drawing them"
    /// §5a: a container at depth *d* holding a target's identity reads step
    /// *d+1* and knows which child leads there, in O(depth), with nothing
    /// measured or drawn.
    ///
    /// Returns `nil` when `ancestor` is not on this chain (the target is
    /// `notMine`) or when the step below is a conditional branch (containers
    /// address children by index or key, never by branch).
    ///
    /// Raw-ROOTED chains work: at runtime a container's identity and its
    /// descendants' share one chain (the child steps are structural whatever
    /// the root is), so the climb-and-compare is exact. Two *independently
    /// built* raw identities ("A/B" vs "A/B/C" as single opaque nodes) have
    /// no shared steps to climb and correctly answer `nil` — unlike
    /// `isAncestor(of:)`, this never falls back to string comparison, because
    /// an opaque path holds no index/key payload to route by.
    ///
    /// - Parameter ancestor: The identity of the routing container.
    /// - Returns: The index or key of the ancestor's immediate child on the
    ///   way to this identity.
    public func childStep(below ancestor: ViewIdentity) -> ChildStep? {
        let ancestorDepth = ancestor.node.depth
        guard node.depth > ancestorDepth else { return nil }

        // Climb to depth ancestorDepth+1, remembering the node one below.
        var below = node
        var cursor: IdentityNode? = node
        while let n = cursor, n.depth > ancestorDepth {
            below = n
            cursor = n.parent
        }
        guard let candidate = cursor, IdentityNode.structurallyEqual(candidate, ancestor.node)
        else { return nil }

        switch below.step {
        case .typed(_, let index): return ChildStep(index: index, key: nil)
        case .keyed(_, let key): return ChildStep(index: nil, key: key)
        case .branch, .raw: return nil
        }
    }

    /// Whether this identity descends from `ancestor` through SINGLE-CHILD
    /// steps only — typed steps with no sibling index, or conditional
    /// branches — i.e. no multi-child container (no indexed or keyed step)
    /// sits between them.
    ///
    /// This is how a windowed stack decides it is the *direct* content of a
    /// ScrollView and may consume its published window: a stack that is one
    /// sibling among several is NOT at the scroll origin, and windowing
    /// against the scroll offsets there would blank the wrong rows.
    ///
    /// - Parameter ancestor: The candidate origin.
    /// - Returns: `true` when every step from `ancestor` down to this
    ///   identity is a single-child descent.
    public func isDirectDescent(from ancestor: ViewIdentity) -> Bool {
        let ancestorDepth = ancestor.node.depth
        guard node.depth >= ancestorDepth else { return false }

        var cursor: IdentityNode? = node
        while let n = cursor, n.depth > ancestorDepth {
            switch n.step {
            case .typed(_, let index):
                guard index == nil else { return false }
            case .branch:
                break
            case .keyed, .raw:
                return false
            }
            cursor = n.parent
        }
        guard let candidate = cursor else { return false }
        return IdentityNode.structurallyEqual(candidate, ancestor.node)
    }

    /// One routing step below a container on a target's identity chain:
    /// which child (by position or `ForEach` key) leads toward the target.
    public struct ChildStep: Sendable, Equatable {
        /// The child's positional index, when the step is positional
        /// (`nil` for a composite body's single, unindexed child too).
        public let index: Int?
        /// The child's stable `ForEach` key, when the step is keyed.
        public let key: String?
    }

    /// The view type this identity's last structural step names, or `nil` when
    /// the step names no type (a conditional branch label, a raw path).
    ///
    /// With ``parent`` this is enough to ask "is this the slot a child of that
    /// type would occupy?" without knowing which index it landed on — the
    /// question a flattening container has when a child has become `nil` and
    /// only the child's *type* is still statically known.
    public var leafType: Any.Type? {
        switch node.step {
        case .typed(let type, _): return type
        case .keyed(let type, _): return type
        case .branch, .raw: return nil
        }
    }

    /// How many steps below the root this identity is; the root is 0.
    public var depth: Int { node.depth }

    /// Whether this identity's root is a raw path string (``init(path:)``):
    /// such identities have no chain to climb — ancestry is a string prefix,
    /// and only ``isAncestor(of:)`` can answer it.
    public var isRawRooted: Bool { node.rootIsRaw }

    /// The structural hash — what ``hash(into:)`` combines — exposed so a
    /// caller holding many identities can index them by it (see
    /// ``RetainedSubtreeIndex``) and confirm with `==` only on a hit.
    public var structuralHash: Int { node.cachedHash }

    /// The identity one structural step up, or `nil` at the root.
    ///
    /// Answers "was this registered directly under that container?" without
    /// rendering either path — the question a container asks when it has to
    /// decide whether something it no longer contains is still on its way out.
    /// A raw-rooted identity (``init(path:)``) has no structure to climb and
    /// returns `nil`.
    public var parent: ViewIdentity? {
        guard let parentNode = node.parent else { return nil }
        return ViewIdentity(node: parentNode)
    }

    /// Whether `descendant` sits anywhere below this identity in the view
    /// tree — at any depth, not merely as a direct child (``parent``).
    ///
    /// The containment test the windowing containers rely on: a `ScrollView`
    /// or `List` that has rendered only part of its content asks it to decide
    /// whether a `@State` box or a cache entry belongs to a subtree it is
    /// still responsible for, and so must survive the pass's prune (see
    /// `StateStorage.retainSubtree(_:)`).
    ///
    /// Structural chains are compared step by step, so a name that merely
    /// *starts with* another's text is not mistaken for a descendant.
    /// Raw-rooted identities (``init(path:)``) carry their path as opaque
    /// string data with no structure to climb, so those fall back to a
    /// prefix comparison that respects the path's `/` and `#` boundaries.
    ///
    /// - Parameter descendant: The identity to test for containment.
    /// - Returns: `true` when `descendant` is below this one. An identity is
    ///   **not** its own ancestor.
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
        if let parent {
            self.rootIsRaw = parent.rootIsRaw
        } else if case .raw = step {
            self.rootIsRaw = true
        } else {
            self.rootIsRaw = false
        }
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
    /// Whether the chain's root is a raw path string. Stored at creation —
    /// the root never changes — because `isAncestor(of:)` asks it of both
    /// sides on every call, and walking to the root each time was 2.5% of a
    /// live frame on its own (`clearAffected` and `isRetained` ask
    /// `isAncestor` of every cached entry, every frame).
    let rootIsRaw: Bool

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

// MARK: - Asking "is this under any of these roots?" of many identities

/// The retained subtree roots of a pass, indexed so that asking whether an
/// identity lies below any of them is one climb of that identity's chain
/// rather than one climb per root.
///
/// A cache prunes what a pass did not mark active, and a memo hit at a
/// subtree root marks nothing below it — it declares the subtree retained
/// instead. So at the end of every pass the prune asks, of every entry not
/// marked, whether some retained root is its ancestor: on a page of a dozen
/// memoised cards that was 764 of 788 entries, each climbing to every root's
/// depth for every root, and all of them retained. Here the roots' structural
/// hashes go in a set, the entry's chain is climbed once from its parent, and
/// `==` (the structural walk) runs only on a hash hit.
public struct RetainedSubtreeIndex {
    private let roots: [ViewIdentity]
    private let hashes: Set<Int>
    private let shallowest: Int
    private let anyRootIsRaw: Bool

    /// - Parameter roots: The pass's retained subtree roots, in any order.
    public init(roots: [ViewIdentity]) {
        self.roots = roots
        self.hashes = Set(roots.map(\.structuralHash))
        self.shallowest = roots.map(\.depth).min() ?? .max
        self.anyRootIsRaw = roots.contains(where: \.isRawRooted)
    }

    /// Whether nothing is retained at all — the caller can skip the ask.
    public var isEmpty: Bool { roots.isEmpty }

    /// Whether some root is a strict ancestor of `identity`.
    public func retains(_ identity: ViewIdentity) -> Bool {
        guard !roots.isEmpty else { return false }
        // A raw-rooted identity has no chain: ancestry is a path-string prefix
        // that only `isAncestor(of:)` can see, so it takes the walk.
        if anyRootIsRaw || identity.isRawRooted {
            return roots.contains { $0.isAncestor(of: identity) }
        }
        var cursor = identity.parent
        while let candidate = cursor, candidate.depth >= shallowest {
            if hashes.contains(candidate.structuralHash),
                roots.contains(where: { $0.depth == candidate.depth && $0 == candidate })
            {
                return true
            }
            cursor = candidate.parent
        }
        return false
    }
}
