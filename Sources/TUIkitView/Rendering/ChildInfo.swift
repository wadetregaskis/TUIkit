//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChildInfo.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Child Info

/// A type-erased wrapper for a child view that enables two-pass layout.
///
/// This wrapper stores the view and allows measuring without rendering,
/// then rendering with a specific size allocation.
@MainActor
public struct ChildView {
    /// The wrapped child, stored as an existential so the (often large,
    /// deeply-generic) view value is boxed ONCE here rather than copied into a
    /// pair of measure / render closure contexts. `measureChild` / `renderChild`
    /// open it back to a concrete type via implicit existential opening.
    private let view: any View
    /// The type whose name forms this child's identity-path component, or `nil`
    /// when the child descends under the parent identity (no disambiguation).
    private let identityType: Any.Type?
    private let childIndex: Int
    /// When set, the child's identity is keyed by this stable string (a
    /// `ForEach` element's id) instead of `childIndex` — identity then follows
    /// the element across reorders, as SwiftUI's `ForEach` contract requires.
    private let identityKey: String?
    /// The STATIC tuple slot of the provider this keyed child was spliced
    /// from, or `-1` for a child that was never spliced (a lone `ForEach` as
    /// a container's whole content) or is positionally identified.
    ///
    /// The identity namespace for sibling providers: two `ForEach` loops in
    /// one container whose rows share a content type and overlapping id
    /// strings would otherwise carry byte-identical identities — colliding in
    /// `StateStorage` and cross-serving each other's memoized row buffers.
    /// The slot is the provider's position in the enclosing `@ViewBuilder`
    /// tuple, which is stable however many children its siblings flatten to
    /// (an `if` occupies its slot whether or not it renders) — so reorders
    /// WITHIN a loop still keep identity through the key, exactly as before.
    /// Folded into the identity only, never into ``identityChildKey``, which
    /// scroll seeking matches against the raw user id.
    ///
    /// An `Int32` with a `-1` sentinel rather than `Optional<Int>`, and it is
    /// load-bearing: the optional grew the struct from 97 to 105 bytes (a
    /// 96→112 stride step), and this struct is built and copied per child per
    /// pass — the growth alone cost the all-invalidating `churn` scenario
    /// ~16% of its frame. The `Int32` packs into existing padding: 97 again.
    ///
    /// - Note: The struct measures **105 bytes / 112 stride** today, not the
    ///   97 above — later fields have re-crossed the boundary. Shrinking it
    ///   back was tried on 2026-08-25 and **measured as nothing**: the only
    ///   way down is to shrink `childIndex` and `spacerMinLength` to `Int32`
    ///   too (a pure field REORDER measures 108/112, i.e. no help at all),
    ///   and those conversions cost per access what the smaller copy saves —
    ///   88 bytes/stride read `churn` +4.3% against a same-binary null test
    ///   of +3.7% on that scenario, with every other scenario flat. So the
    ///   number above is history, not a lever: do not re-derive it without a
    ///   clean-built A/B on both sides (§40.2 of the performance profile).
    private let providerSlot: Int32
    /// The identity this child renders and measures under, when it has been
    /// resolved ahead of use — see ``resolvingIdentity(under:)``. `nil` means
    /// ``childContext(_:)`` derives it from the context it is given.
    private let resolvedIdentity: ViewIdentity?

    /// Whether this child is a Spacer.
    public let isSpacer: Bool

    /// The minimum length of this spacer (only relevant if isSpacer is true).
    public let spacerMinLength: Int?

    /// The child's explicit z-index (`0` unless set via `View.zIndex(_:)`).
    /// Overlapping containers like `ZStack` draw children in ascending order
    /// of this value; ties keep their original tree order.
    public let zIndex: Double

    /// Whether this child carries an explicit alignment guide (set via
    /// `View.alignmentGuide(_:computeValue:)`).
    ///
    /// A stored flag rather than a cast: aligning containers ask it of every
    /// child on every frame, and it is `false` for all of them in almost every
    /// tree. Only when it is `true` does a container reach for the guide
    /// itself, through ``wrappedView``.
    public let providesAlignmentGuide: Bool

    /// Resolves a child's spacer flag and minimum length without a speculative
    /// runtime conformance cast on the common (non-spacer) path.
    ///
    /// The static witness ``View/_isSpacer`` answers the detection per type
    /// (`false` for everything but `Spacer`); only the rare spacer is then cast
    /// to `SpacerProtocol` to read its `spacerMinLength`.
    static func spacerInfo<V: View>(of view: V) -> (isSpacer: Bool, minLength: Int?) {
        guard V._isSpacer else { return (false, nil) }
        return (true, (view as? SpacerProtocol)?.spacerMinLength)
    }

    /// Resolves a child's z-index without a speculative runtime conformance
    /// cast on the common path — same shape as ``spacerInfo(of:)``, using the
    /// static witness ``View/_providesZIndex``.
    static func zIndexInfo<V: View>(of view: V) -> Double {
        V._providesZIndex ? ((view as? ZIndexProviding)?.zIndexValue ?? 0) : 0
    }

    /// Wraps `view` as a child that descends under its parent's identity.
    ///
    /// The transparent form: no identity component of its own, so the view
    /// keeps whatever identity the parent already established. Use it for a
    /// container's single content view, where there are no siblings to tell
    /// apart. A child that has siblings needs ``init(_:childIndex:)`` (or
    /// ``init(_:identityType:key:)`` for `ForEach` rows) so each gets a
    /// distinct identity and its own `@State`.
    ///
    /// The layout witnesses — spacer, z-index, alignment guide — are read
    /// once here from the static `View` witnesses rather than by casting on
    /// every layout pass.
    ///
    /// - Parameter view: The child view to wrap.
    public init<V: View>(_ view: V) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = V._providesAlignmentGuide
        self.view = view
        self.identityType = nil
        self.childIndex = 0
        self.identityKey = nil
        self.providerSlot = -1
        self.resolvedIdentity = nil
    }

    /// Creates a child view wrapper with an explicit child index for identity propagation.
    ///
    /// Use this initializer when wrapping children from a `TupleView` or similar
    /// container so that each child receives a unique `ViewIdentity` during
    /// measure and render passes.
    ///
    /// - Parameters:
    ///   - view: The child view to wrap.
    ///   - childIndex: The positional index used for identity disambiguation.
    public init<V: View>(_ view: V, childIndex: Int) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = V._providesAlignmentGuide
        self.view = view
        self.identityType = V.self
        self.childIndex = childIndex
        self.identityKey = nil
        self.providerSlot = -1
        self.resolvedIdentity = nil
    }

    /// Full-field copy initializer backing ``reindexed(to:providerSlot:)``.
    private init(
        view: any View,
        identityType: Any.Type?,
        childIndex: Int,
        identityKey: String?,
        providerSlot: Int32,
        isSpacer: Bool,
        spacerMinLength: Int?,
        zIndex: Double,
        providesAlignmentGuide: Bool,
        resolvedIdentity: ViewIdentity? = nil
    ) {
        self.view = view
        self.identityType = identityType
        self.childIndex = childIndex
        self.identityKey = identityKey
        self.providerSlot = providerSlot
        self.isSpacer = isSpacer
        self.spacerMinLength = spacerMinLength
        self.zIndex = zIndex
        self.providesAlignmentGuide = providesAlignmentGuide
        self.resolvedIdentity = resolvedIdentity
    }

    /// This child with its identity under `parent` worked out now, so the
    /// walks that use it share one identity node instead of each deriving
    /// its own — which, for a keyed row, was a namespaced key string and a
    /// node allocation per child per walk, five times a frame for a stack
    /// inside a scroll view. Only meaningful where every later use is under
    /// the same parent, which is what the per-pass child memo guarantees:
    /// its key carries the parent identity.
    func resolvingIdentity(under parent: ViewIdentity) -> Self {
        guard let identityType else { return self }
        // The identity directly, rather than through a throwaway `RenderContext`
        // built only to carry it. Constructing one is eleven stored properties
        // including the whole `EnvironmentValues`, which was affordable while
        // this ran on the memoised `ForEach` path alone and is not now that
        // every spliced child resolves.
        let resolved: ViewIdentity
        if let resolvedIdentity {
            resolved = resolvedIdentity
        } else if let identityKey {
            resolved = parent.child(
                erasedType: identityType,
                key: providerSlot >= 0 ? "\(providerSlot)#\(identityKey)" : identityKey)
        } else {
            resolved = parent.child(erasedType: identityType, index: childIndex)
        }
        return Self(
            view: view, identityType: identityType, childIndex: childIndex,
            identityKey: identityKey, providerSlot: providerSlot, isSpacer: isSpacer,
            spacerMinLength: spacerMinLength, zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide,
            resolvedIdentity: resolved)
    }

    /// A copy whose positional identity is rebased to `index`, and whose
    /// keyed identity is namespaced by the provider's static slot.
    ///
    /// When a provider's flattened children are spliced into an enclosing
    /// container's child list, their identity must reflect the FLATTENED
    /// position — two same-typed children contributed by different providers
    /// (two `Group`s, two `if` branches) would otherwise carry identical
    /// (type, inner-index) identities and collide in `StateStorage` (the
    /// second silently adopts the first's state and focus slots). Children
    /// with a stable `identityKey` (`ForEach` rows) keep it — identity must
    /// follow the element across reorders — but take the provider's slot as a
    /// namespace, because two sibling `ForEach` loops with overlapping ids
    /// are the same collision in keyed form (see ``providesAlignmentGuide``). A child
    /// with no identity type adopts its view's dynamic type, matching what it
    /// would get as a direct tuple child.
    func reindexed(to index: Int, providerSlot slot: Int) -> Self {
        reindexed(to: index, providerSlot: slot, under: nil)
    }

    /// ``reindexed(to:providerSlot:)`` and ``resolvingIdentity(under:)`` in one
    /// construction.
    ///
    /// Fused because the splice does both, on every child of every provider, and
    /// each of them copies the whole struct — including the `any View`
    /// existential, so a separate call is a second retain and release per child
    /// for nothing. Passing `nil` is the plain reindex.
    func reindexed(to index: Int, providerSlot slot: Int, under parent: ViewIdentity?) -> Self {
        if let identityKey {
            // The slot prefix is the namespace; see ``providesAlignmentGuide``.
            let resolved = parent.map {
                $0.child(
                    erasedType: identityType ?? type(of: view),
                    key: slot >= 0 ? "\(slot)#\(identityKey)" : identityKey)
            }
            return Self(
                view: view,
                identityType: identityType,
                childIndex: childIndex,
                identityKey: identityKey,
                providerSlot: Int32(slot),
                isSpacer: isSpacer,
                spacerMinLength: spacerMinLength,
                zIndex: zIndex,
                providesAlignmentGuide: providesAlignmentGuide,
                resolvedIdentity: resolved)
        }
        let resolvedType = identityType ?? type(of: view)
        return Self(
            view: view,
            identityType: resolvedType,
            childIndex: index,
            identityKey: nil,
            providerSlot: -1,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide,
            resolvedIdentity: parent.map { $0.child(erasedType: resolvedType, index: index) })
    }

    /// Creates a child wrapper that renders `view` but derives its per-child
    /// identity from a *different* type `IdentityType`.
    ///
    /// Used when a row is wrapped in a transparent helper (e.g. `_MemoizedRow`)
    /// that must not appear in the identity path: pass the wrapper as `view` and
    /// the original content type as `identityType`, so the child's
    /// `ViewIdentity` — and thus its `@State` / focus slots — is exactly what it
    /// would be unwrapped. The wrapper itself adds no identity (it is
    /// `Renderable`), so the inner content keeps the same identity either way.
    ///
    /// - Parameters:
    ///   - view: The (possibly wrapped) view to measure and render.
    ///   - identityType: The type whose name forms the identity path component.
    ///   - childIndex: The positional index used for identity disambiguation.
    public init<V: View, IdentityType>(
        _ view: V, identityType: IdentityType.Type, childIndex: Int
    ) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = V._providesAlignmentGuide
        self.view = view
        self.identityType = identityType
        self.childIndex = childIndex
        self.identityKey = nil
        self.providerSlot = -1
        self.resolvedIdentity = nil
    }

    /// Creates a child wrapper whose per-child identity is keyed by a stable
    /// string (a `ForEach` element's id) under `identityType`, rather than by
    /// a positional index — see ``ViewIdentity/child(erasedType:key:)``.
    public init<V: View, IdentityType>(
        _ view: V, identityType: IdentityType.Type, key: String
    ) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = V._providesAlignmentGuide
        self.view = view
        self.identityType = identityType
        self.childIndex = 0
        self.identityKey = key
        self.providerSlot = -1
        self.resolvedIdentity = nil
    }

    /// The wrapped child view itself, for containers that need to inspect the
    /// original view value — e.g. `List` peeling a `.badge(_:)` wrapper off a
    /// row — rather than measure or render it.
    public var wrappedView: any View { view }

    /// The identity this child measures and renders under — the address that
    /// "Locating things without drawing them" §5a routes by — computed without
    /// building or rendering anything. Identical to the identity the child
    /// receives on the real measure/render paths (same `childContext`).
    public func identity(under context: RenderContext) -> ViewIdentity {
        childContext(context).identity
    }

    /// The stable `ForEach` key this child's identity is disambiguated by,
    /// or `nil` for positionally-identified children.
    public var identityChildKey: String? { identityKey }

    /// The positional index this child's identity is disambiguated by, or
    /// `nil` when the child is keyed or descends transparently under the
    /// parent identity.
    public var identityChildIndex: Int? {
        (identityType == nil || identityKey != nil) ? nil : childIndex
    }

    /// Measures this child view without rendering.
    public func measure(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(view, proposal: proposal, context: childContext(context))
    }

    /// Renders this child view with the given size allocation.
    public func render(width: Int, height: Int, context: RenderContext) -> FrameBuffer {
        renderChild(view, width: width, height: height, context: childContext(context))
    }

    /// The context to measure / render the child in: the parent context with
    /// this child's identity appended, or the parent context unchanged when
    /// `identityType` is `nil` (the no-disambiguation initializer).
    private func childContext(_ context: RenderContext) -> RenderContext {
        guard let identityType else { return context }
        if let resolvedIdentity {
            var copy = context
            copy.identity = resolvedIdentity
            return copy
        }
        if let identityKey {
            // The slot prefix is injective: the slot is the digits before the
            // first "#", so no two (slot, key) pairs concatenate to one
            // string. `identityChildKey` stays the raw user key — scroll
            // seeking matches against it.
            let namespaced =
                providerSlot >= 0 ? "\(providerSlot)#\(identityKey)" : identityKey
            return context.withChildIdentity(erasedType: identityType, key: namespaced)
        }
        return context.withChildIdentity(erasedType: identityType, index: childIndex)
    }
}

/// A view that carries an explicit z-index for sibling draw ordering.
///
/// Implemented by the wrapper produced by `View.zIndex(_:)`. Container views
/// that overlap their children — notably `ZStack` — read this to decide the
/// order in which children are drawn.
@MainActor
public protocol ZIndexProviding {
    /// The z-index of the view. Higher values draw later (on top).
    var zIndexValue: Double { get }
}

/// Describes a child view within a stack for layout purposes.
public struct ChildInfo {
    /// The rendered buffer of this child (nil for spacers, computed later).
    public let buffer: FrameBuffer?

    /// Whether this child is a Spacer.
    public let isSpacer: Bool

    /// The minimum length of this spacer (only relevant if isSpacer is true).
    public let spacerMinLength: Int?

    /// The size this child needs (from sizeThatFits).
    /// Only available when using two-pass layout.
    public let size: ViewSize?

    /// The child's explicit z-index (`0` unless set via `View.zIndex(_:)`).
    ///
    /// Overlapping containers like `ZStack` draw children in ascending order
    /// of this value; ties keep their original tree order.
    public let zIndex: Double

    /// Creates a new child info.
    public init(
        buffer: FrameBuffer?,
        isSpacer: Bool,
        spacerMinLength: Int?,
        size: ViewSize?,
        zIndex: Double = 0
    ) {
        self.buffer = buffer
        self.isSpacer = isSpacer
        self.spacerMinLength = spacerMinLength
        self.size = size
        self.zIndex = zIndex
    }
}

// MARK: - Child Info Provider

/// Internal protocol that allows stack containers to extract individual
/// child info from their content (which is typically a TupleView).
@MainActor
public protocol ChildInfoProvider {
    /// Returns an array of ``ChildInfo``, one per child view.
    ///
    /// - Parameter context: The rendering context for child rendering.
    /// - Returns: An array of child descriptions for layout.
    func childInfos(context: RenderContext) -> [ChildInfo]
}

// MARK: - Child View Provider

/// Protocol for views that can provide type-erased children for two-pass layout.
///
/// This enables measuring children before rendering them with final sizes.
@MainActor
public protocol ChildViewProvider {
    /// Returns an array of type-erased child views for two-pass layout.
    ///
    /// - Parameter context: The rendering context (for child identity).
    /// - Returns: An array of ``ChildView`` wrappers.
    func childViews(context: RenderContext) -> [ChildView]

    /// Whether ``childViews(context:)`` is worth remembering for the rest of
    /// the pass — see ``resolveChildViews(from:context:)``. `false` by
    /// default: a tuple of three views resolves in less time than the memo
    /// takes to look it up. `ForEach` answers `true` once it has enough rows
    /// for the reverse to hold.
    var childViewsAreWorthMemoising: Bool { get }

    /// A label naming WHICH content this provider is currently offering, when
    /// it can offer more than one and they must not share an identity.
    ///
    /// Only `ConditionalView` answers it. An `if`/`else` renders one branch or
    /// the other, and `renderToBuffer` distinguishes them with
    /// `withBranchIdentity` — but a stack does not reach that method: it
    /// FLATTENS the conditional through `childViews`, which resolved both
    /// branches against the same context. Two same-typed branches then landed
    /// on one identity and shared a `@State` box, so flipping the condition
    /// carried the old branch's state into the new one.
    ///
    /// A label on the provider rather than a field on `ChildView`, because
    /// `ChildView` is built and copied per child per pass and its size is
    /// load-bearing — the last field added to it cost `churn` ~16% (see
    /// `ChildView.providerSlot`). This costs a word on a protocol nothing
    /// else implements.
    var identityBranchLabel: String? { get }
}

extension ChildViewProvider {
    /// Not worth it, unless a provider says otherwise.
    public var childViewsAreWorthMemoising: Bool { false }

    /// Nothing to distinguish, unless a provider says otherwise.
    public var identityBranchLabel: String? { nil }
}

/// Creates a ChildInfo for a single view.
///
/// If the view conforms to ``SpacerProtocol``, the returned info marks it as such
/// with its minimum length. Otherwise the view is rendered into a
/// ``FrameBuffer`` via ``renderToBuffer(_:context:)``.
///
/// - Parameters:
///   - view: The child view.
///   - context: The rendering context.
/// - Returns: A ``ChildInfo`` describing the view.
@MainActor
public func makeChildInfo<V: View>(for view: V, context: RenderContext) -> ChildInfo {
    // Static witnesses gate the rare conformance casts: only a z-index wrapper
    // is cast to `ZIndexProviding`, only a spacer to `SpacerProtocol`. The common
    // child (neither) does no speculative cast at all.
    let zIndex = V._providesZIndex ? ((view as? ZIndexProviding)?.zIndexValue ?? 0) : 0
    if V._isSpacer {
        return ChildInfo(
            buffer: nil,
            isSpacer: true,
            spacerMinLength: (view as? SpacerProtocol)?.spacerMinLength,
            size: nil,
            zIndex: zIndex
        )
    }
    return ChildInfo(
        buffer: renderToBuffer(view, context: context),
        isSpacer: false,
        spacerMinLength: nil,
        size: nil,
        zIndex: zIndex
    )
}

// MARK: - Two-Pass Layout Support

/// Measures a child view without rendering it.
///
/// Uses `sizeThatFits` if the view is `Layoutable`, otherwise falls back
/// to rendering and measuring the buffer.
///
/// - Parameters:
///   - view: The child view.
///   - proposal: The proposed size from the parent.
///   - context: The rendering context.
/// - Returns: The size this view needs.
@MainActor
public func measureChild<V: View>(_ view: V, proposal: ProposedSize, context: RenderContext) -> ViewSize {
    // Deep-nesting guard: if the recursion is about to overflow the stack, stop
    // descending and report the (untruncated part of the) subtree as zero-size
    // rather than crashing with SIGSEGV. See StackGuard — this measures the real
    // remaining stack, so it only ever trips on pathologically deep trees.
    if !StackGuard.hasHeadroom() { return ViewSize.fixed(0, 0) }

    // Serve this pass's memo if the same view has already been measured at the
    // same proposal. Two-pass layout re-measures a subtree once per enclosing
    // level, so a chain of N nested containers measures the tail N times —
    // O(depth²) work for O(depth) tree (measured: the `deep` stress scenario
    // costs 7.0ms / 78.2ms / 474.7ms per frame at 1×/4×/10× depth).
    //
    // Only when a `VolatileReadTracker` is already installed: the render loop
    // always installs one, and requiring it keeps this off standalone
    // measurement paths (and off the cost of minting one per call).
    //
    // Read off the CACHE, not out of the environment. It is the same object —
    // `EnvironmentValues.installVolatileReadTracker` puts it in both places —
    // but this gate is passed once per measured node, ~14,400 times on a
    // `fanout` frame, and an `EnvironmentValues` read of a present key is a
    // hash, an `[ObjectIdentifier: Any]` probe, a `swift_dynamicCast` and a
    // retain, where the mirror is a load from a class this context already
    // holds as a stored field. The same hoist `renderCache` and `stateStorage`
    // got, one level further in.
    if let cache = context.renderCache, let tracker = cache.volatileReadTracker {
        // Debug-only, and the whole reason reading the mirror is sound: if some
        // path installed a tracker into the environment WITHOUT mirroring it,
        // the counters snapshotted below belong to a different object than the
        // one this subtree's volatile reads record to, and every unsafe
        // measurement would be stored as safe — wrong sizes, no diagnostic.
        // Costs exactly the environment probe this change removes, in builds
        // where nothing is being measured.
        assert(
            context.environment.volatileReadTracker === tracker,
            "the pass's volatile-read tracker was installed without mirroring it onto the render "
                + "cache — install one with EnvironmentValues.installVolatileReadTracker(_:)")
        let key = RenderCache.MeasureKey(
            identityHash: measureIdentityHash(context),
            effectiveWidth: proposal.width ?? context.availableWidth,
            availableWidth: context.availableWidth,
            hasExplicitWidth: context.hasExplicitWidth,
            hasExplicitHeight: context.hasExplicitHeight,
            viewType: ObjectIdentifier(V.self),
            valueHash: viewValueHash(view))
        let widthWasSpecified = proposal.width != nil
        // What this query can accept without a clamp — the gate a stored
        // ``ViewSize/isNaturalSize`` answer has to clear to serve it.
        let verticalBudget = min(proposal.height ?? Int.max, context.availableHeight)
        if let cached = cache.lookupMeasure(
            key: key,
            proposalWidthWasSpecified: widthWasSpecified,
            proposalHeight: proposal.height,
            availableHeight: context.availableHeight,
            verticalBudget: verticalBudget)
        {
            if RenderCache.verifiesMeasureMemo {
                let fresh = measureChildUncached(view, proposal: proposal, context: context)
                if fresh != cached {
                    cache.noteMeasureMemoMismatch(
                        viewType: String(describing: V.self), served: cached, fresh: fresh,
                        proposal: proposal, availableWidth: context.availableWidth,
                        availableHeight: context.availableHeight,
                        identity: context.identity.path)
                }
            }
            return cached
        }
        // The same gate `EquatableView`/`_MemoizedRow` use: a subtree that
        // declares a render side effect or reads a per-frame-volatile value is
        // measured, but not remembered.
        let unsafeBefore = tracker.cacheUnsafeCount
        let size = measureChildUncached(view, proposal: proposal, context: context)
        if tracker.cacheUnsafeCount == unsafeBefore {
            cache.storeMeasure(
                key: key,
                proposalWidthWasSpecified: widthWasSpecified,
                proposalHeight: proposal.height,
                availableHeight: context.availableHeight,
                size: size)
        }
        return size
    }
    return measureChildUncached(view, proposal: proposal, context: context)
}

/// The identity half of a ``RenderCache/MeasureKey``: the identity's structural
/// hash, with ``RenderContext/measureGeneration`` folded in when a container has
/// set one.
///
/// Folded here rather than carried as its own key field because the key is
/// probed around two thousand times a frame and copied on every probe: an eighth
/// field grew it by a word and cost **+2.1% on the `anyview` stress scenario**,
/// for a value that is 0 for every view in almost every pass. This way the
/// common path is one integer compare.
/// Branchless, and deliberately: generation 0 multiplies to zero and the xor is
/// the identity, so the common path is one multiply and one xor with no
/// prediction to get wrong. A `guard generation != 0` here measured +1.5% on the
/// `modifiers` stress scenario, which is the shape with the most `measureChild`
/// calls per row.
@inline(__always)
private func measureIdentityHash(_ context: RenderContext) -> Int {
    let structural = UInt64(bitPattern: Int64(context.identity.structuralHash))
    // The golden-ratio odd constant: each of the 255 non-zero generations gets a
    // distinct, well-spread mask, and generation 0 gets none at all.
    let generation = UInt64(context.measureGeneration) &* 0x9E37_79B9_7F4A_7C15
    return Int(truncatingIfNeeded: structural ^ generation)
}

/// Hashes a view value's raw storage, to tell two values of one type apart
/// inside a single render pass.
///
/// `measureChild` is generic over `V: View` and so cannot demand `Equatable`,
/// which is why the only value-keyed memo in the tree sits behind
/// `EquatableView`. The bytes are the conformance-free substitute: no
/// reflection (which would cost what the memo saves), just the struct's own
/// storage, which for a view is a handful of words.
///
/// See ``RenderCache/MeasureKey/valueHash`` for why raw bytes are sound within
/// a pass but were not across frames.
///
/// `Hasher` is the obvious spelling and the wrong one here. It is SipHash-1-3 —
/// keyed, randomised per process, and built to resist an adversary choosing
/// collisions. Nothing here has an adversary: this is a discriminator inside a
/// per-pass memo whose key ALSO carries the identity's hash, the view's type
/// and two widths, so a value collision on its own cannot serve a wrong answer.
/// What it is, is hot — a whole-struct hash on every measured child, **3.4% of
/// a `menus` frame between this and the `withUnsafeBytes` around it**.
///
/// So: FNV-style mixing over whole words with a splitmix64 finalizer, which
/// avalanches the low bits a `Dictionary` probes on. A side effect worth having
/// is that it is deterministic — `Hasher`'s seed is randomised per process, so
/// the memo's key stream (and any bug that depends on it) differed run to run.
@MainActor
private func viewValueHash<V: View>(_ view: V) -> Int {
    withUnsafeBytes(of: view) { bytes in
        var hash = hashFoldSeed
        let count = bytes.count
        var index = 0
        while index + 8 <= count {
            hash = mixHashWord(hash, bytes.loadUnaligned(fromByteOffset: index, as: UInt64.self))
            index += 8
        }
        // The tail, packed into one word so a short struct still mixes every
        // byte it has. A view is a handful of words, so this runs at most once.
        if index < count {
            var tail: UInt64 = 0
            var shift: UInt64 = 0
            while index < count {
                tail |= UInt64(bytes[index]) &<< shift
                shift &+= 8
                index += 1
            }
            hash = mixHashWord(hash, tail)
        }
        return finalizeHashWord(hash)
    }
}

/// ``measureChild`` without the per-pass memo — the measurement itself.
@MainActor
private func measureChildUncached<V: View>(
    _ view: V, proposal: ProposedSize, context: RenderContext
) -> ViewSize {
    // Measure what will be DRAWN: an `Animatable` view mid-animation is a
    // different size from the one the tree describes, and a measure that used
    // the target would lay out for a frame that is not on screen yet. Here
    // rather than in `measureChild` so it falls INSIDE that memo's
    // cache-unsafe window — an animating subtree must be measured every frame,
    // not remembered. Reads the store without writing it.
    //
    // Branched, not folded, for the reason `renderToBuffer` gives: rebinding
    // `view` unconditionally copies the struct on every measured child, and
    // deep nesting measures the tail once per enclosing level.
    if V._isAnimatable, let animated = resolvingAnimation(view, context: context, isMeasuring: true)
    {
        return measureResolved(animated, proposal: proposal, context: context)
    }
    return measureResolved(view, proposal: proposal, context: context)
}

/// ``measureChildUncached(_:proposal:context:)`` once the animation
/// substitution is settled.
@MainActor
private func measureResolved<V: View>(
    _ view: V, proposal: ProposedSize, context: RenderContext
) -> ViewSize {
    // Use Layoutable if available (mark as measuring to suppress side-effects).
    //
    // Spacer is handled here too: it conforms to `Layoutable` and its
    // `sizeThatFits` returns the same fully-flexible size a dedicated
    // `SpacerProtocol` branch would build by hand — so checking `as?
    // SpacerProtocol` first only added a redundant runtime conformance cast to
    // EVERY measured child (Spacer is the sole conformer and is `Layoutable`).
    // `SpacerProtocol` is still used by the stacks for fill distribution.
    // The common path, and the one deep nesting recurses through. When the
    // parent is already measuring, the context is unchanged — skip the copy
    // that only flips `isMeasuring` (a no-op then), so a deep chain doesn't
    // re-copy the context at every level.
    if context.isMeasuring {
        if let size = V._measureSelf(view, proposal: proposal, context: context) {
            return size
        }
    } else {
        var measureContext = context
        measureContext.isMeasuring = true
        if let size = V._measureSelf(view, proposal: proposal, context: measureContext) {
            return size
        }
    }

    // For composite views (Body != Never, NOT Renderable), descend into the
    // body — extracted into a separate, non-inlined function so materialising
    // `body` (a stack local as large as `V.Body`) stays OUT of this frame. The
    // common `Layoutable` path above then recurses with a smaller frame, which
    // matters under deep nesting where every level adds one.
    //
    // Skip Renderable views: their rendering logic (including environment
    // injection) lives in renderToBuffer, not in body. They fall through
    // to the single-render fallback below.
    if !(view is Renderable), V.Body.self != Never.self {
        return measureCompositeBody(view, proposal: proposal, context: context)
    }

    // Fallback: a `Renderable` view with no `Layoutable` conformance. Measure by
    // a SINGLE render, reported fixed.
    //
    // This used to render the view *twice* — once at the proposal, then again at
    // `naturalWidth + 8` to probe whether the view grows (and so is width-
    // flexible). That probe is now retired: every view whose measure depends on
    // width-flexibility (the stacks, frames, containers, controls, the
    // behavioural decorators, AnyView, …) conforms to `Layoutable` and is handled
    // above, where its `sizeThatFits` reports flexibility precisely. The probe was
    // also imprecise — it called any view that *reflows* wider (a wrapping `Text`)
    // "flexible", contradicting the `ViewSize` flexibility contract.
    //
    // What reaches here now is the fixed-size Renderable long tail: structural
    // wrappers that vertically stack (`TupleView`, `ViewArray`), and leaf cores
    // rendered within already-`Layoutable` parents or directly by the render loop
    // (the status bar, table rows, list content, the alert button row, …). For
    // these a single render is size-exact; they don't fill, so reporting fixed is
    // correct. A NEW Renderable view that genuinely fills its width must conform
    // to `Layoutable` to advertise that — the equivalence harness
    // (`MeasureRenderEquivalenceTests`) is the guard that catches one that doesn't.
    return measureFixedByRendering(view, proposal: proposal, context: context)
}

/// Measures a composite view (`Body != Never`, not `Renderable`) by descending
/// into its body to find an inner `Layoutable`. This handles cases like
/// `TextField<Text>` whose body is `_TextFieldCore<Text>` which IS `Layoutable`.
///
/// Kept a **separate, non-inlined** function (called by ``measureChild``) so the
/// `body` stack local — as large as `V.Body` — does not inflate every
/// `measureChild` frame, only the frames that actually descend into a composite.
/// Under deep nesting, where each level contributes a frame, keeping the common
/// path's frame small is what buys the extra depth.
///
/// Descends under the SAME child identity `renderToBuffer` uses (it appends the
/// body type via `withChildIdentity`). Measuring under the parent identity
/// instead made the measure pass hydrate a composite view's `@State` from a
/// different slot than the render pass, so a state-dependent view could measure
/// a different size than it rendered. Hydration still keys off `context` (the
/// parent), exactly as render does; only the recursion descends with the child
/// identity.
@inline(never)
@MainActor
private func measureCompositeBody<V: View>(
    _ view: V, proposal: ProposedSize, context: RenderContext
) -> ViewSize {
    let childContext = context.withChildIdentity(type: V.Body.self)
    // Resolve `@Environment` into its boxes exactly as the render path does.
    // This used to be a `StateRegistration.withHydration` task local instead,
    // which was both slower and *wrong* here: hydration publishes an environment
    // for the fallback to find but never fills the boxes, so a measure-time
    // `@Environment` read that happened to consult its box got the default. A
    // view branching on `\.terminalWidth` would measure the subtree it would
    // have rendered at 80 columns, whatever the terminal actually was.
    resolveEnvironmentProperties(of: view, in: context.environment)
    bindStateProperties(
        of: view, identity: context.identity, storage: context.stateStorage!)
    return measureChild(view.body, proposal: proposal, context: childContext)
}

/// Measures a fixed-size view by rendering it ONCE in measuring mode and
/// reporting the result as a fixed size.
///
/// This is the measure used by a `Layoutable` view that never grows to fill — a
/// `Button`, `Toggle`, `Stepper`, a `Menu`, and the like — whose width can't be
/// derived structurally (it's assembled procedurally in `renderToBuffer`). It is
/// also exactly what `measureChild`'s fallback now does for the Renderable long
/// tail that isn't `Layoutable`: render once, report fixed. (Historically that
/// fallback rendered *twice* — a second render at `naturalWidth + 8` to probe
/// width-flexibility — but that probe was retired once the flexible views became
/// `Layoutable`; see `measureChild`.)
///
/// The single render goes through the same clamped `renderToBuffer(_:context:)`
/// the real layout pass uses, and sets `isMeasuring` / `hasExplicitWidth` so the
/// view reports its natural (minimum) size — identical to what render produces.
/// A view that needs to advertise width/height *flexibility* must not use this
/// alone (it always reports fixed): see how `_ToggleCore` combines it with a
/// structural label probe.
///
/// - Parameters:
///   - view: The fixed-size view.
///   - proposal: The proposed size from the parent.
///   - context: The rendering context.
/// - Returns: The view's size, always reported as fixed.
@MainActor
public func measureFixedByRendering<V: View>(_ view: V, proposal: ProposedSize, context: RenderContext) -> ViewSize {
    var measureContext = context
    measureContext.isMeasuring = true
    // Clear hasExplicitWidth so the view reports its natural (minimum) size
    // rather than expanding to fill the full available width.
    measureContext.hasExplicitWidth = false
    if let width = proposal.width {
        measureContext.availableWidth = width
    }
    if let height = proposal.height {
        measureContext.availableHeight = height
    }
    let buffer = renderToBuffer(view, context: measureContext)
    return ViewSize.fixed(buffer.width, buffer.height)
}

/// Renders a child view with a specific size allocation.
///
/// - Parameters:
///   - view: The child view.
///   - width: The allocated width.
///   - height: The allocated height.
///   - context: The rendering context.
/// - Returns: The rendered buffer.
@MainActor
public func renderChild<V: View>(_ view: V, width: Int, height: Int, context: RenderContext) -> FrameBuffer {
    // Deep-nesting guard (see measureChild): render a truncation marker instead
    // of recursing another level into a stack overflow.
    if !StackGuard.hasHeadroom() {
        return FrameBuffer(text: "⋯").clamped(toWidth: width, height: height)
    }
    var renderContext = context
    renderContext.availableWidth = width
    renderContext.availableHeight = height
    // Safety net: a child must never exceed the space allocated to it,
    // otherwise it would overwrite a sibling or overflow the stack.
    return renderToBuffer(view, context: renderContext).clamped(toWidth: width, height: height)
}

// MARK: - Child Info Resolution

/// Resolves child infos from a view's content.
///
/// If the content conforms to ``ChildInfoProvider`` (e.g. TupleViews),
/// it returns individual child infos. Otherwise it returns the content
/// as a single-element array.
///
/// - Parameters:
///   - content: The content view.
///   - context: The rendering context.
/// - Returns: An array of ``ChildInfo``.
@MainActor
public func resolveChildInfos<V: View>(from content: V, context: RenderContext) -> [ChildInfo] {
    if let provider = content as? ChildInfoProvider {
        return provider.childInfos(context: context)
    }
    return [makeChildInfo(for: content, context: context)]
}

// MARK: - Two-Pass Layout Resolution

/// Resolves child views from a view's content for two-pass layout.
///
/// If the content conforms to ``ChildViewProvider`` (e.g. TupleViews),
/// it returns individual child views. Otherwise it wraps the content
/// in a single-element array.
///
/// - Parameters:
///   - content: The content view.
///   - context: The rendering context.
/// - Returns: An array of ``ChildView``.
@MainActor
public func resolveChildViews<V: View>(from content: V, context: RenderContext) -> [ChildView] {
    guard let provider = content as? ChildViewProvider else { return [ChildView(content)] }
    // Once per PASS, not once per walk. A stack resolves its children in
    // `sizeThatFits` and again in `renderToBuffer`, and a stack inside a
    // `ScrollView` is measured for the enclosing stack's natural-size ask,
    // for each scrollbar probe, and for the render's own layout — five
    // resolutions of the same content value in one frame, each building a
    // `_MemoizedRow` per element: 26% of a `fanout` frame. Keyed the way the
    // measure memo is (identity, type, the content's raw bytes), and scratch
    // for the pass like it, so a content value that changed is resolved
    // afresh and nothing outlives the walk that could have made it stale.
    guard provider.childViewsAreWorthMemoising, let cache = context.renderCache else {
        return provider.childViews(context: context)
    }
    let key = RenderCache.ChildViewsKey(
        identityHash: context.identity.structuralHash, viewType: ObjectIdentifier(V.self),
        valueHash: viewValueHash(content))
    if let remembered = cache.lookupChildViews(key: key) { return remembered }
    // Identities resolved once here, for the same reason the array is: every
    // later use of this entry is under `context.identity` (it is in the key).
    let children = provider.childViews(context: context).map {
        $0.resolvingIdentity(under: context.identity)
    }
    cache.storeChildViews(key: key, children: children)
    return children
}
