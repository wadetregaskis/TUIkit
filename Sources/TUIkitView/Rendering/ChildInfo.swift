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
    /// from, or `ProviderSlot.unnamespaced` for a child that was never spliced
    /// (a lone `ForEach` as a container's whole content) or is positionally
    /// identified.
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
    /// A keyed child a splice RESOLVED — one a deeper splice had already
    /// namespaced, or one under an `if`/`else` branch — is stamped with a slot
    /// too, but that stamp is never read into a key again (the resolved
    /// identity wins): it marks the row as addressed, so the next splice out
    /// keeps its identity instead of flattening it back to a slot-prefixed key.
    /// See `spliced(fromSlot:under:branched:)`.
    ///
    /// A keyed row that an `if`/`else` resolved for itself, before any splice saw
    /// it, carries `ProviderSlot.resolvedInBranch` for the same reason. In `Group
    /// { if … else … }` beside a sibling the `Group` has no branch label, so the
    /// mark is all that tells the splice this row's identity holds a branch step.
    /// It is a mark in this field rather than a field of its own because the
    /// struct's size is load-bearing (below). The splice decides on the mark and
    /// never on whether `resolvedIdentity` is set: the child memo resolves a
    /// loop's rows from sixteen rows on, and those rows still take the flat key,
    /// so deciding on the identity would move them as the loop grew past fifteen.
    ///
    /// An `Int32` with sentinels (`ProviderSlot`) rather than `Optional<Int>`, and it is
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
    ///   clean-built A/B on both sides (§41.1 of the performance profile).
    private let providerSlot: Int32

    /// The values of `providerSlot` that are not a tuple slot.
    private enum ProviderSlot {
        /// Nothing has namespaced this child: a row straight out of its
        /// `ForEach`, or a positional child.
        static let unnamespaced: Int32 = -1
        /// A keyed row an `if`/`else` resolved for itself: its identity holds the
        /// branch step, which a flat slot-prefixed key has nowhere to put. It
        /// always has a `resolvedIdentity`.
        static let resolvedInBranch: Int32 = -2
    }

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
        guard V._providesZIndex else { return 0 }
        return throughWrappers(view, as: (any ZIndexProviding).self)?.zIndexValue ?? 0
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
        self.providerSlot = ProviderSlot.unnamespaced
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
        self.providerSlot = ProviderSlot.unnamespaced
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

    /// This child as the content of a conditional's branch whose identity is
    /// `branch` — the identity `ConditionalView.renderToBuffer` renders that
    /// branch's content at, so the flattened and whole-view paths agree.
    ///
    /// ``resolvingIdentity(under:)``, except for a TRANSPARENT child (no step
    /// of its own: the branch was one plain view). That one is not left
    /// untouched but pinned to `branch` itself. Left untouched it derives its
    /// identity later from the context the container renders it in, which is
    /// the container's own whichever branch it came from — and two branches at
    /// one identity share a `@State` box. A child that already carries a
    /// resolved identity keeps it: it was resolved under this branch, or under
    /// a deeper one (a nested conditional, a memoised `ForEach`).
    ///
    /// A keyed row nothing has namespaced is also marked
    /// `ProviderSlot.resolvedInBranch`. Its identity now holds the branch step
    /// and a flat slot-prefixed key cannot, so a tuple splice further out has to
    /// keep it. Unmarked, `VStack { Text("h"); Group { if a { ForEach(ids) {
    /// Row($0) } } else { ForEach(ids) { Row($0) } } } }` flattened both arms'
    /// rows onto one `Row[1#id]` each, and the arm drawn second read the first
    /// arm's `@State`. The mark goes on in the construction that resolves the
    /// row, so it costs no extra copy.
    func resolvingIdentity(inBranch branch: ViewIdentity) -> Self {
        guard let identityType else {
            guard resolvedIdentity == nil else { return self }
            return Self(
                view: view, identityType: nil, childIndex: childIndex,
                identityKey: identityKey, providerSlot: providerSlot, isSpacer: isSpacer,
                spacerMinLength: spacerMinLength, zIndex: zIndex,
                providesAlignmentGuide: providesAlignmentGuide,
                resolvedIdentity: branch)
        }
        guard let identityKey, providerSlot == ProviderSlot.unnamespaced else {
            return resolvingIdentity(under: branch)
        }
        return Self(
            view: view, identityType: identityType, childIndex: childIndex,
            identityKey: identityKey, providerSlot: ProviderSlot.resolvedInBranch,
            isSpacer: isSpacer, spacerMinLength: spacerMinLength, zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide,
            resolvedIdentity: resolvedIdentity ?? branch.child(erasedType: identityType, key: identityKey))
    }

    /// This child with `modifier` wrapped around it — what a provider hands
    /// back when the modifier was written on the PROVIDER rather than on each
    /// of the members it resolves to.
    ///
    /// Everything but the view is carried across unchanged, which is the point:
    /// the identity a member already resolved to, its spacer flag, its z-index
    /// and its alignment-guide flag are properties of the MEMBER, and a wrapper
    /// now standing in front of it does not change any of them. Re-reading them
    /// off the wrapper would answer `false` / `0` to all three, because no
    /// single-content wrapper forwards the static `View` witnesses — so
    /// `HStack { Group { Text("A"); Spacer() }.padding() }` would quietly lose
    /// its spacer.
    /// This child inside a copy of `wrapper` — ``modified(by:)`` for the
    /// wrappers that are not `ViewModifier`s.
    ///
    /// Everything but the view is carried across unchanged, for the reason
    /// ``modified(by:)`` spells out: the identity a member already resolved to,
    /// its spacer flag, its z-index and its alignment-guide flag are properties
    /// of the MEMBER, and a wrapper now standing in front of it does not change
    /// any of them. The spacer flag is the one with teeth — measured in the
    /// real framework, a `Spacer` inside a MODIFIED `Group` still reaches the
    /// enclosing stack as a spacer, and re-reading the flag off the wrapper
    /// would answer `false`.
    ///
    /// The existential is opened by ``SingleContentWrapper/rewrapping(_:)``
    /// being generic, so no cast happens here and nothing is boxed twice.
    package func rewrapped(by wrapper: some ContentRewrapping) -> Self {
        Self(
            view: wrapper.rewrapping(view),
            identityType: identityType,
            childIndex: childIndex,
            identityKey: identityKey,
            providerSlot: providerSlot,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide,
            resolvedIdentity: resolvedIdentity)
    }

    package func modified<M: ViewModifier>(by modifier: M) -> Self {
        // Implicit existential opening, not a cast: passing the `any View` to a
        // generic parameter binds `V` to its dynamic type, so what is stored is
        // the concrete `ModifiedView<V, M>` the render path measures and
        // renders. It is NOT `ModifiedView<any View, M>`, which would not even
        // compile — an existential does not conform to the protocol it erases.
        func wrapped<V: View>(_ view: V) -> any View {
            ModifiedView(content: view, modifier: modifier)
        }
        return Self(
            view: wrapped(view),
            identityType: identityType,
            childIndex: childIndex,
            identityKey: identityKey,
            providerSlot: providerSlot,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide,
            resolvedIdentity: resolvedIdentity)
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
            providerSlot: ProviderSlot.unnamespaced,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide,
            resolvedIdentity: parent.map { $0.child(erasedType: resolvedType, index: index) })
    }

    /// This child as it leaves a provider that a `TupleView` is splicing in at
    /// static slot `slot` — the whole splice decision, in one place. `parent` is
    /// the provider's own identity step, carrying its branch when `branched`.
    ///
    /// Exactly one kind of entry is addressed from this level's slot alone. Every
    /// other kind keeps what the level below worked out, because only that level
    /// knew what told its children apart, and nothing handed up can rebuild it:
    ///
    /// - A keyed row nothing has namespaced yet, under no branch — a `ForEach`
    ///   that is itself the tuple element, or a `Group` or an `if` without `else`
    ///   holding one — takes the flat slot-prefixed key beside its parent's other
    ///   children. That is the hot shape, and it is injective: no other keyed row
    ///   comes out of this slot. A `Group` or an `if` holding an `if`/`else` of
    ///   loops does not qualify: the conditional below marked its rows
    ///   `ProviderSlot.resolvedInBranch`.
    /// - A keyed row that already carries a slot, or sits under a branch at this
    ///   level or one provider further in, keeps the identity it was resolved
    ///   to, or is resolved under `parent` with its inner slot still in its key.
    ///   Overwriting that slot with this one is what
    ///   put both loops of `Group { ForEach(0..<2); ForEach(0..<2) }` — spliced,
    ///   because a sibling sits beside the `Group` — on the same two identities,
    ///   and the row memo, which keys on identity and element, drew the first
    ///   loop's buffers where the second loop's rows belonged. A branch went the
    ///   same way: both arms of an `if`/`else` over one row type met on one key.
    /// - A positional child that is already resolved keeps its identity. It was
    ///   resolved under an inner provider's step, and re-resolving it under
    ///   `parent` at the index it had in there dropped that step: `Group { if a {
    ///   Counter() }; if b { Counter() } }` put both counters on `Counter.0` under
    ///   the `Group`, one `@State` box between them.
    /// - Any other positional child is resolved under `parent` at that index.
    ///
    /// A keyed row resolved here is stamped with `slot`, so the next splice out
    /// sees it as namespaced and keeps it. Keeping a resolved identity is as
    /// sound as the one-level resolution this always did: every provider in the
    /// framework builds its children in the context it is handed, so an identity
    /// resolved below sits under a scope descended from `parent`.
    func spliced(fromSlot slot: Int, under parent: ViewIdentity, branched: Bool) -> Self {
        guard let identityKey else {
            if resolvedIdentity != nil { return self }
            return reindexed(to: identityChildIndex ?? 0, providerSlot: slot, under: parent)
        }
        if providerSlot == ProviderSlot.unnamespaced, !branched {
            return reindexed(to: 0, providerSlot: slot, under: nil)
        }
        assert(
            providerSlot != ProviderSlot.resolvedInBranch || resolvedIdentity != nil,
            "a branch-resolved row lost its identity")
        let resolved =
            resolvedIdentity
            ?? parent.child(
                erasedType: identityType ?? type(of: view),
                key: providerSlot >= 0 ? "\(providerSlot)#\(identityKey)" : identityKey)
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
        self.providerSlot = ProviderSlot.unnamespaced
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
        self.providerSlot = ProviderSlot.unnamespaced
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
        renderContext(under: context).identity
    }

    /// The context this child measures and renders under: `context` with this
    /// child's identity step applied, and nothing else changed.
    ///
    /// For a container that hands the child to something *other than*
    /// ``measure(proposal:context:)`` / ``render(width:height:context:)`` and
    /// so cannot let those apply the step for it — `List` asking a `Section`
    /// child for its rows rather than for a buffer. This is not a variant of
    /// the render context: it is exactly the one those two methods use.
    public func renderContext(under context: RenderContext) -> RenderContext {
        childContext(context)
    }

    /// The stable `ForEach` key this child's identity is disambiguated by,
    /// or `nil` for positionally-identified children.
    public var identityChildKey: String? { identityKey }

    /// The key an explicit `View.id(_:)` bound to this child, or `nil` when
    /// nothing in its modifier chain bound one.
    ///
    /// Deliberately NOT folded into ``identityChildKey``: `.id(_:)` is a
    /// modifier, so the step it splices sits *below* this child's own and the
    /// child stays positionally identified. Reporting the tag as the child's
    /// identity key would tell every positional lookup — `LayoutPlacing`'s
    /// `ordinal(of:)` above all — that this child has no index to match.
    ///
    /// A cast rather than a stored field: this struct's size is load-bearing
    /// (see `providerSlot`), and the only caller is a scroll seek, which
    /// asks on the frames a `scrollTo` request arrives on and on no others.
    public var explicitIDKey: String? {
        (view as? ExplicitIDProviding)?.explicitIDKey
    }

    /// Whether this child is the seek target named by `key` — the one place
    /// the two spellings SwiftUI's `ScrollViewProxy.scrollTo(_:anchor:)`
    /// accepts are decided between.
    ///
    /// A child that HAS a stable identity answers by it and by nothing else:
    /// a `ForEach` row is identified by its element's `id`, so a `.id(_:)`
    /// written inside a row is not a second address for it. That is also what
    /// keeps the answer the same on every seek path — the uniform and anchored
    /// windows resolve a whole-`ForEach` stack from the data's keys and never
    /// build a row view, so a tag inside one is not theirs to see. Only an
    /// unkeyed child — a stack's own tuple children, which is where the tag is
    /// written — is asked for its tag, and only then is the cast behind
    /// ``explicitIDKey`` paid.
    ///
    /// `.tag(_:)` no longer follows that rule, and the difference is what the
    /// two modifiers are for: since 2026-09-20 a `.tag(_:)` on a `ForEach` row
    /// gives the row its `List` SELECTION value, overriding the element's
    /// `id`. It does not give the row an address — identity is still the `id`,
    /// which is what this matcher and every window resolve from.
    public func matchesSeekKey(_ key: String) -> Bool {
        if let identityKey { return identityKey == key }
        return explicitIDKey == key
    }

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

    /// The context to measure / render the child in: the identity resolved
    /// ahead of use when there is one, else the parent context with this
    /// child's identity appended, or the parent context unchanged when
    /// `identityType` is `nil` (the no-disambiguation initializer).
    ///
    /// The resolved identity is asked for FIRST, before the transparent early
    /// return, because a transparent child can carry one: the single view of a
    /// lone `if`/`else` branch is pinned to its branch while adding no step of
    /// its own (``resolvingIdentity(inBranch:)``). Asked second, the pin was
    /// never read. Every other child with a resolved identity also has an
    /// identity type, so the order changes nothing for them; an unresolved
    /// typed child still pays two checks, a transparent one pays one more.
    private func childContext(_ context: RenderContext) -> RenderContext {
        if let resolvedIdentity {
            var copy = context
            copy.identity = resolvedIdentity
            return copy
        }
        guard let identityType else { return context }
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
/// Lookups still read the memo: an answer another measure stored is as good
/// here as anywhere. Nothing beneath the probe reads or stores the memo: it is
/// detached for the measure below, which a probe inside a probe finds too.
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
        // The same gate `EquatableView`/`_MemoizedRow` use: a subtree that
        // declares a render side effect or reads a per-frame-volatile value is
        // measured, but not remembered.
        let unsafeBefore = tracker.cacheUnsafeCount
        let size: ViewSize
        if remembersDescendants {
            size = measureChildUncached(view, proposal: proposal, context: context)
        } else {
            // The memo detached from everything beneath: the probe's subtree
            // neither reads nor stores it, and this measure's own store below
            // is the one entry a probe keeps. Detached rather than held by a
            // count every store would test: that check, on the store path every
            // measured node takes, cost `churn` 2.1% and `gradients` 1.2% with
            // no probe in the tree at all.
            cache.volatileReadTracker = nil
            size = measureChildUncached(view, proposal: proposal, context: context)
            cache.volatileReadTracker = tracker
        }
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
