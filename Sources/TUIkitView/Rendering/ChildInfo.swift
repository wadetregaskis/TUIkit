//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChildInfo.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Child Info

/// A view that can report the explicit identity key `View.id(_:)` bound
/// somewhere in its modifier chain.
///
/// `ModifiedView` is the sole conformer and it conforms UNCONDITIONALLY —
/// hence the optional answer, `nil` for the overwhelming majority that wrap
/// some other modifier. Unconditional because the tag has to be found through
/// the chain above it: `.id(k).padding()` is a `ModifiedView` whose own
/// modifier is the padding, and only a conformer can be asked for what is
/// inside it.
@MainActor
public protocol ExplicitIDProviding {
    /// The key `View.id(_:)` bound to this view, or `nil` if it bound none.
    var explicitIDKey: String? { get }
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
    /// Honoured in exactly three places, and a caller must go through one of
    /// them: the tuple splice (`TupleView.appendChildViews`, a conditional with
    /// siblings), ``resolveChildViews(from:context:)`` (a conditional that is a
    /// container's ONLY content, which `buildBlock` hands over bare), and the
    /// `List`'s and `Section`'s look-through (`ConditionalView.listRowsContext`
    /// in TUIkit, a conditional around a list's loop). The second was missing,
    /// so `VStack { if a { Row("1") } else { Row("2") } }` kept both branches at
    /// the stack's own identity. Asking a provider for `childViews(context:)`
    /// directly bypasses all three — `List` and `Section` did, and had the same
    /// hole.
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

// MARK: - Single-Content Wrappers

/// A view whose whole job is to wrap exactly ONE content view and adjust
/// something about how it renders — the shape `.foregroundStyle`, `.opacity`,
/// `.frame` and dozens of other modifier factories return.
///
/// It exists for one reason: a wrapper stands between a container and the
/// content it was handed, and when that content is SEVERAL views rather than
/// one, the container must still see the members. SwiftUI states the rule for
/// `Group` ("The modifier applies to all members of the group — and not to the
/// group itself") and it holds for layout as well as for paint — measured, not
/// assumed: `HStack { Group { Text("AA"); Text("BB") }.frame(width: 80) }` in
/// the real framework lays the two texts out at exactly the frames writing
/// `.frame(width: 80)` on each member separately produces.
///
/// ``ModifiedView`` reaches its members without this, because a `ViewModifier`
/// is a VALUE it can carry to each of them (see `ChildView.modified(by:)`). A
/// bare wrapper has no such value — re-wrapping means calling its own
/// initialiser, whose content type is the wrapper's generic parameter and so
/// cannot be bound to an `any View`. ``ContentRewrapping/rewrapping(_:)`` is
/// that initialiser call, written once per wrapper, and it is the ONLY member a
/// conformance has to spell: it is generic over the new content, so passing an
/// existential to it opens the existential instead of failing to convert.
///
/// Public because two of the wrappers that must conform are — `FlexibleFrameView`
/// (`.frame`) and `DisabledModifier` (`.disabled`) — and a public type's
/// conformance needs public witnesses. It joins ``ChildViewProvider``,
/// ``ChildInfoProvider``, ``ExplicitIDProviding`` and ``ZIndexProviding`` as
/// view-resolution infrastructure this module already publishes.
///
/// - Important: Conform a wrapper to ``ChildViewProvider`` only when its effect
///   is one every member should get. That is true of anything cosmetic, spatial
///   or environmental, and NOT true of a wrapper that performs an effect or
///   registers something: distributing it would multiply the effect by the
///   member count. `.onAppear` on a `ForEach` of fifty rows fires ONCE in
///   SwiftUI — also measured — so a blanket conformance would turn one call
///   into fifty while leaving every layout test green.
@MainActor
public protocol SingleContentWrapper {
    /// The type of the content this wrapper was built around.
    associatedtype WrappedContent: View

    /// The content this wrapper was built around.
    var wrappedContent: WrappedContent { get }
}

/// The nearest thing at or inside `view` that conforms to `T`, looking through
/// any number of single-content wrappers.
///
/// This is the READ direction: metadata travelling UP to a container that is
/// asking, rather than an adjustment travelling DOWN to members. A wrapper
/// swallowed it before, so `.zIndex(1).padding(0)` silently lost its place in
/// the draw order — measured in the real framework, SwiftUI keeps it:
/// `ZStack { Color.red.zIndex(1).padding(0); Color.green }` renders red on top,
/// exactly as `.zIndex(1)` alone does, where without the z-index green wins.
///
/// - Important: NEVER call this without first checking the static witness that
///   gates it (``View/_providesZIndex`` and friends). The witness is a
///   compile-time constant chain and answers `false` for almost every child of
///   almost every container; this walk is a sequence of runtime conformance
///   casts on one of the hottest paths there is. The witness makes the walk
///   unreachable for a child that has nothing to find, which is the only reason
///   it is affordable.
///
/// The loop terminates because each step moves strictly inward through a
/// statically nested generic type, which is finite by construction — no view
/// can be its own content.
@MainActor
package func throughWrappers<T>(_ view: any View, as type: T.Type = T.self) -> T? {
    var current: any View = view
    while true {
        if let found = current as? T { return found }
        guard let wrapper = current as? any SingleContentWrapper else { return nil }
        current = wrapper.wrappedContent
    }
}

/// The static witnesses, forwarded through a wrapper so the walk above is
/// reachable at all.
///
/// Each is a compile-time constant chain, so a wrapper around a `Text` still
/// folds to `false` and costs nothing — which is what makes forwarding them
/// affordable where a runtime probe of every child would not be.
///
/// Only ``View/_providesZIndex`` is forwarded. The other two witnesses are NOT,
/// and neither omission is an oversight:
///
/// - ``View/_isSpacer`` is a claim about LAYOUT PARTICIPATION, and a wrapper is
///   entitled to change it. `Spacer().frame(width: 5)` is a fixed five-cell gap,
///   not a flexible one, and forwarding the flag would make the stack treat it
///   as flexible and ignore the frame. A spacer that must survive a wrapper
///   reaches its container by the other route, `ChildView.rewrapped(by:)`,
///   which carries the MEMBER's flag across rather than re-reading it off the
///   wrapper.
/// - ``View/_providesAlignmentGuide`` is worse than either, because it would
///   look like it worked. A guide is a closure EVALUATED AGAINST the dimensions
///   the view laid out at (`explicitAlignmentGuide(for:in:)`), and the walk
///   would hand the inner view's closure the OUTER, wrapped size — so
///   `.alignmentGuide(.leading) { $0.width }.padding(1)` would resolve against
///   a width two cells larger than the one the closure was written for, and
///   report a position from the wrong coordinate space. SwiftUI gets this right
///   by TRANSLATING the guide as each wrapper changes the geometry; TUIkit's
///   buffers carry no guide metadata for a wrapper to translate, which is the
///   reason `alignmentGuide(_:computeValue:)`'s own doc comment gives for the
///   "apply it as the outermost modifier" rule. A guide that silently reports
///   the wrong position is worse than one that documentedly does nothing, so
///   the rule stands for guides and is lifted only for z-indices. Forwarding it
///   through the wrappers that demonstrably do NOT change size would be sound
///   and is the obvious next step; it needs a witness for size-neutrality that
///   does not exist yet, and guessing per type is exactly how the wrong
///   coordinate space gets shipped.
extension View where Self: SingleContentWrapper {
    /// The content's answer: a z-index bound inside this wrapper is still a
    /// z-index, so the gate that decides whether to look for one has to say so.
    ///
    /// A z-index is the only one of the three witnesses that is safe to forward
    /// unconditionally, and the reason is that it is **dimension-independent**:
    /// `.zIndex(1)` means the same number whatever size the view ends up, so a
    /// wrapper cannot invalidate it. See the type-level note for the other two.
    public static var _providesZIndex: Bool { WrappedContent._providesZIndex }
}

/// A ``SingleContentWrapper`` that can also put a copy of itself around some
/// OTHER view — which is what a container needs to reach past it to the members
/// of multi-view content and still apply the adjustment to each of them.
///
/// Split from ``SingleContentWrapper`` because the two directions cost very
/// different things. Naming the content is one line and always safe; being
/// re-wrapped around each member is a decision per wrapper (see the note on
/// ``SingleContentWrapper``), and ``rewrapping(_:)`` is the only member of
/// either protocol that cannot be written mechanically. Keeping them apart lets
/// every single-content wrapper answer the READ question — where a wrapper
/// currently swallows a z-index, an alignment guide or a spacer flag — without
/// each one having to earn the right by answering the harder one.
@MainActor
public protocol ContentRewrapping: SingleContentWrapper {
    /// A copy of this wrapper around `view` instead of its own content.
    ///
    /// Generic over the new content, which is what makes it usable at all:
    /// the caller holds an `any View`, and passing an existential to a generic
    /// parameter opens it to its dynamic type (SE-0352). The result is the
    /// concrete wrapper the render path measures and renders, never a wrapper
    /// around an existential — which would not compile, since an existential
    /// does not conform to the protocol it erases.
    func rewrapping<V: View>(_ view: V) -> any View
}

/// Child resolution straight through a single-content wrapper, for any wrapper
/// whose content has members of its own.
///
/// Every member comes back wrapped in a copy of the wrapper, so the adjustment
/// still applies — to each member, which is the rule. Conforming is therefore
/// a one-line `extension X: ChildViewProvider where Content: ChildViewProvider {}`
/// on top of the ``SingleContentWrapper`` conformance: there is no body to
/// write, and no per-wrapper chance to get the identity bookkeeping wrong.
///
/// Conditional on the content having members, so nothing else changes: a
/// wrapper around an ordinary single view stays exactly as opaque as it was,
/// and the witness is a compile-time fact rather than a cast per child.
extension ChildViewProvider where Self: ContentRewrapping, WrappedContent: ChildViewProvider {
    /// The content's members, each one back inside a copy of this wrapper.
    ///
    /// - Parameter context: The rendering context, passed to the content
    ///   unchanged — the wrapper adjusts what it wraps, not where its content
    ///   resolves its children.
    /// - Returns: One ``ChildView`` per member of the content.
    public func childViews(context: RenderContext) -> [ChildView] {
        wrappedContent.childViews(context: context).map { $0.rewrapped(by: self) }
    }

    /// The content's answer: whether the resolution is worth remembering is a
    /// property of how many children it produces, which the wrapper does not
    /// change.
    public var childViewsAreWorthMemoising: Bool { wrappedContent.childViewsAreWorthMemoising }

    /// Forwarded, or a wrapped `if`/`else` would resolve both of its branches
    /// against one identity and the two arms would share a `@State` box — the
    /// defect ``ChildViewProvider/identityBranchLabel`` exists to prevent, one
    /// wrapper further out.
    public var identityBranchLabel: String? { wrappedContent.identityBranchLabel }
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
    let zIndex = ChildView.zIndexInfo(of: view)
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
    memoizedMeasure(view, proposal: proposal, context: context, remembersDescendants: true)
}

/// ``measureChild(_:proposal:context:)`` for a question nothing else in the
/// pass will ask: this pass's memo keeps the answer, and none of the answers
/// the measure found on the way to it.
///
/// For a probe — a measure made to learn one thing about a subtree that is
/// drawn, and so measured, somewhere else, at another identity or from a
/// view value built afresh. Every node a measure visits leaves an entry in
/// the per-pass memo, and a probe's are dead weight: nothing but the probe
/// measures there, and the probe's own entry already answers a repeat of it.
/// They are not free, either. The memo is one dictionary, emptied every pass
/// with its capacity kept, so what a probe adds to the biggest pass is paid
/// until the scratch trimmer next looks, and enough of it tips the table past
/// a power of two — a doubled table kept for hundreds of frames, and the old
/// one alive beside the new one while it rehashes.
///
/// Lookups still read the memo, the probe's own and every one beneath it: an
/// answer another measure stored is as good here as anywhere, and the subtree
/// a probe asks about has usually just been measured by the render that laid
/// it out. Only storing stops — beneath the probe a miss is measured and kept
/// nowhere, which a probe inside a probe finds too (``RenderCache/isProbing``).
@MainActor
package func measureChildRememberingOnlyItself<V: View>(
    _ view: V, proposal: ProposedSize, context: RenderContext
) -> ViewSize {
    memoizedMeasure(view, proposal: proposal, context: context, remembersDescendants: false)
}

/// The body of ``measureChild(_:proposal:context:)`` and its probe twin
/// ``measureChildRememberingOnlyItself(_:proposal:context:)``: the
/// deep-nesting guard, this pass's measure memo, and the measure itself.
///
/// Inlined into both, so the flag is a constant each folds away:
/// `measureChild` is on the path deep nesting recurses through, and a branch
/// or a larger frame there is paid by every measured node.
@inline(__always)
@MainActor
private func memoizedMeasure<V: View>(
    _ view: V, proposal: ProposedSize, context: RenderContext, remembersDescendants: Bool
) -> ViewSize {
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
        let key = measureKey(for: view, proposal: proposal, context: context)
        if let served = servedMeasure(view, key: key, proposal: proposal, context: context, cache: cache) {
            return served
        }
        // The same gate `EquatableView`/`_MemoizedRow` use: a subtree that
        // declares a render side effect or reads a per-frame-volatile value is
        // measured, but not remembered.
        let unsafeBefore = tracker.cacheUnsafeCount
        let size: ViewSize
        if remembersDescendants {
            size = measureChildUncached(view, proposal: proposal, context: context)
        } else {
            // The memo detached from everything beneath, and read-only there:
            // the probe's subtree reads it (below) but stores nothing, and this
            // measure's own store below is the one entry a probe keeps.
            // Detached rather than held by a count every store would test:
            // that check, on the store path every measured node takes, cost
            // `churn` 2.1% and `gradients` 1.2% with no probe in the tree at
            // all. Put back as found, for a tracker installed beneath a probe
            // (`withVolatileReadTracker`) with a probe of its own under it.
            let wasProbing = cache.isProbing
            cache.volatileReadTracker = nil
            cache.isProbing = true
            size = measureChildUncached(view, proposal: proposal, context: context)
            cache.isProbing = wasProbing
            cache.volatileReadTracker = tracker
        }
        if tracker.cacheUnsafeCount == unsafeBefore {
            cache.storeMeasure(
                key: key,
                proposalWidthWasSpecified: proposal.width != nil,
                proposalHeight: proposal.height,
                availableHeight: context.availableHeight,
                size: size)
        }
        return size
    }
    // Beneath a probe: asked only where the gate above found no tracker, so an
    // ordinary measure in the render loop, which always has one, never reads it.
    if let cache = context.renderCache, cache.isProbing {
        return measureBeneathProbe(view, proposal: proposal, context: context, cache: cache)
    }
    return measureChildUncached(view, proposal: proposal, context: context)
}

/// A measure beneath a probe: served from this pass's memo when it can be, and
/// measured and kept nowhere when it cannot. See
/// ``measureChildRememberingOnlyItself(_:proposal:context:)``.
///
/// Out of line, so the path an ordinary measure takes is only the call to it,
/// behind a test it never passes.
@inline(never)
@MainActor
private func measureBeneathProbe<V: View>(
    _ view: V, proposal: ProposedSize, context: RenderContext, cache: RenderCache
) -> ViewSize {
    let key = measureKey(for: view, proposal: proposal, context: context)
    if let served = servedMeasure(view, key: key, proposal: proposal, context: context, cache: cache) {
        return served
    }
    cache.measuresBeneathProbes += 1
    if cache.probeMissLog != nil {
        cache.probeMissLog?.append(
            "\(V.self) \(key); held: \(cache.measureKeys(sharingTypeAndIdentityWith: key))")
    }
    return measureChildUncached(view, proposal: proposal, context: context)
}

/// This pass's measure-memo key for `view` asked `proposal` in `context`.
@inline(__always)
@MainActor
private func measureKey<V: View>(
    for view: V, proposal: ProposedSize, context: RenderContext
) -> RenderCache.MeasureKey {
    RenderCache.MeasureKey(
        identityHash: measureIdentityHash(context),
        effectiveWidth: proposal.width ?? context.availableWidth,
        availableWidth: context.availableWidth,
        hasExplicitWidth: context.hasExplicitWidth,
        hasExplicitHeight: context.hasExplicitHeight,
        viewType: ObjectIdentifier(V.self),
        valueHash: viewValueHash(view))
}

/// What this pass's measure memo holds at `key` for this query, or `nil` when
/// it holds nothing that can serve it.
///
/// Under ``RenderCache/verifiesMeasureMemo`` a hit is measured afresh and the
/// fresh size returned, with any difference from the served one noted.
@inline(__always)
@MainActor
private func servedMeasure<V: View>(
    _ view: V, key: RenderCache.MeasureKey, proposal: ProposedSize, context: RenderContext,
    cache: RenderCache
) -> ViewSize? {
    // What this query can accept without a clamp — the gate a stored
    // ``ViewSize/isNaturalSize`` answer has to clear to serve it.
    let verticalBudget = min(proposal.height ?? Int.max, context.availableHeight)
    guard
        let cached = cache.lookupMeasure(
            key: key,
            proposalWidthWasSpecified: proposal.width != nil,
            proposalHeight: proposal.height,
            availableHeight: context.availableHeight,
            verticalBudget: verticalBudget)
    else { return nil }
    if RenderCache.verifiesMeasureMemo {
        // The fresh size, not the served one: a debugging aid the layout
        // shows, as the render verifier draws its fresh render.
        let fresh = measureChildUncached(view, proposal: proposal, context: context)
        if fresh != cached {
            cache.noteMeasureMemoMismatch(
                viewType: String(describing: V.self), served: cached, fresh: fresh,
                proposal: proposal, availableWidth: context.availableWidth,
                availableHeight: context.availableHeight,
                identity: context.identity.path)
        }
        return fresh
    }
    return cached
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
    measureIdentityHash(context.identity, generation: context.measureGeneration)
}

/// `measureChild`'s key hash for `identity` measured under `generation` — also
/// what `RenderCache.forgetSizes(of:measureGeneration:)` matches a per-pass
/// entry by, so the two cannot disagree about where an entry lives.
@inline(__always)
func measureIdentityHash(_ identity: ViewIdentity, generation: UInt8) -> Int {
    let structural = UInt64(bitPattern: Int64(identity.structuralHash))
    // The golden-ratio odd constant: each of the 255 non-zero generations gets a
    // distinct, well-spread mask, and generation 0 gets none at all.
    let folded = UInt64(generation) &* 0x9E37_79B9_7F4A_7C15
    return Int(truncatingIfNeeded: structural ^ folded)
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
/// and two widths, so a value collision on its own is unlikely to serve a wrong
/// answer. Unlikely, and not impossible, which is what the `AnyView` arm below
/// is about: siblings measured at ONE identity — a `Form` sizing its label
/// column, say — have all four of those fields in common, and the bytes are the
/// only thing telling them apart.
/// What it is, is hot — a whole-struct hash on every measured child, **3.4% of
/// a `menus` frame between this and the `withUnsafeBytes` around it**.
///
/// So: FNV-style mixing over whole words with a splitmix64 finalizer, which
/// avalanches the low bits a `Dictionary` probes on. A side effect worth having
/// is that it is deterministic — `Hasher`'s seed is randomised per process, so
/// the memo's key stream (and any bug that depends on it) differed run to run.
@MainActor
private func viewValueHash<V: View>(_ view: V) -> Int {
    // The gate is a static witness and the arm is a cast to the ONE concrete
    // type, and both of those were arrived at by measurement. `measureChild` is
    // generic and public, so a caller in another module does not specialise it;
    // what it reads off `V` there is a witness-table access, and the cheapest
    // shapes are not the ones that read cheapest. `V.self == AnyView.self` in
    // place of the witness cost `deep` +2.7% and `modifiers` +4.6%, and hoisting
    // the loop below into a second function so this one could `return` it cost
    // another point on top. So: one witness, one branch, and the loop stays
    // where it was.
    if V._valueIsBoxed, let boxed = view as? AnyView {
        return boxed.erasedValueHash
    }
    return withUnsafeBytes(of: view) { bytes in
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

/// The value hash of an existential's payload: what it holds, opened back to
/// its concrete type, and the type beside it.
///
/// The type is hashed beside the bytes because the bytes alone do not carry it
/// here: the key's own `viewType` field says `AnyView` for every erased view,
/// whatever is inside. Without this, a `Text` and a `Divider` whose structs
/// happen to hold the same bytes would be one key.
///
/// Recursive by construction, through the gate rather than around it: the
/// payload of an `AnyView(AnyView(x))` is itself boxed, its dynamic type says
/// so, and it is asked the same question.
@MainActor
func erasedViewValueHash(_ view: any View) -> Int {
    var folded = mixHashWord(hashFoldSeed, UInt64(bitPattern: Int64(viewValueHash(view))))
    folded = mixHashWord(folded, UInt64(UInt(bitPattern: ObjectIdentifier(type(of: view)))))
    return finalizeHashWord(folded)
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
    let buffer = renderToBuffer(view, context: fixedMeasureContext(proposal: proposal, context: context))
    return ViewSize.fixed(buffer.width, buffer.height)
}

/// The context ``measureFixedByRendering(_:proposal:context:)`` draws in:
/// measuring, with no explicit width, and the proposal, where there is one, as
/// the space.
///
/// For a view that draws to measure and then asks a second question of what
/// it drew, which has to be asked under the same context for the two answers
/// to be about one drawing.
@MainActor
package func fixedMeasureContext(proposal: ProposedSize, context: RenderContext) -> RenderContext {
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
    return measureContext
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
    return resolveChildViews(from: content, as: provider, context: context)
}

/// ``resolveChildViews(from:context:)`` for content the caller has already
/// cast: `provider` is `content`, as a ``ChildViewProvider``.
///
/// For a caller that needed the cast for a decision of its own first, so the
/// conformance is looked up once rather than twice — an optional deciding
/// whether its present view flattens at all is one, on every walk.
///
/// - Parameters:
///   - content: The content view.
///   - provider: `content`, as a provider.
///   - context: The rendering context.
/// - Returns: An array of ``ChildView``.
@MainActor
package func resolveChildViews<V: View>(
    from content: V, as provider: ChildViewProvider, context: RenderContext
) -> [ChildView] {
    // An `if`/`else` handed over WHOLE: a container's only content, which
    // `buildBlock` passes through bare, so no tuple splice ran to apply the
    // branch step (``ChildViewProvider/identityBranchLabel``). Without it both
    // branches resolved against the container's context — and a branch that
    // is one plain view came back transparent, rendering at the container's
    // own identity whichever branch it was: `VStack { if a { Row("1") } else
    // { Row("2") } }` handed the second row the first one's `@State`.
    //
    // Written INTO each child, not merely used to build them: a `ChildView`
    // does not remember the context it was built in, it derives its identity
    // from the context the container later measures and renders it in, which
    // is the container's. Keyed `ForEach` rows take the step as well, unlike
    // in the tuple splice, which leaves keyed rows unstepped for speed — here
    // there is no sibling slot to namespace them by, and without the step two
    // branches looping over the same ids alias exactly as plain views do. They
    // are marked as holding it, too (`ChildView.resolvingIdentity(inBranch:)`):
    // when this conditional is a `Group`'s or an `if`'s whole content, a tuple
    // splice further out must keep the step rather than flatten it away.
    // Ahead of the memo and never through it: its key knows nothing of
    // branches, and no conditional opts into memoising.
    if let branch = provider.identityBranchLabel {
        let branchContext = context.withBranchIdentity(branch)
        let branchIdentity = branchContext.identity
        return provider.childViews(context: branchContext).map {
            $0.resolvingIdentity(inBranch: branchIdentity)
        }
    }
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
