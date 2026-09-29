//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PrimitiveViews.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - EmptyView

/// A view that displays no content.
///
/// `EmptyView` is useful for placeholders or when a view
/// should display nothing under certain conditions.
///
/// ```swift
/// if showContent {
///     Text("Content")
/// } else {
///     EmptyView()
/// }
/// ```
public struct EmptyView: View, Equatable {
    /// Creates an empty view.
    public init() {}

    public var body: Never {
        fatalError("EmptyView has no body")
    }
}

// MARK: - ConditionalView

/// A view that represents either the true or false branch of a conditional.
///
/// This type is used internally by `ViewBuilder` for if-else statements.
///
/// - Important: This is framework infrastructure. Created automatically by
///   `@ViewBuilder` for `if`/`else` branches. Do not instantiate directly.
public enum ConditionalView<TrueContent: View, FalseContent: View>: View {
    /// The true branch was executed.
    case trueContent(TrueContent)

    /// The false branch was executed.
    case falseContent(FalseContent)

    public var body: Never {
        fatalError("ConditionalView renders its children directly")
    }
}

// MARK: - ViewArray

/// A view that contains an array of identical views.
///
/// This type is used internally by `ViewBuilder` for for-in loops.
///
/// ```swift
/// ForEach(items) { item in
///     Text(item.name)
/// }
/// ```
///
/// - Important: This is framework infrastructure. Created automatically by
///   `@ViewBuilder` for array content. Do not instantiate directly.
public struct ViewArray<Element: View>: View {
    /// The contained views.
    let elements: [Element]

    /// Creates a ViewArray from an array of views.
    ///
    /// - Parameter elements: The views this container holds.
    public init(_ elements: [Element]) {
        self.elements = elements
    }

    public var body: Never {
        fatalError("ViewArray renders its children directly")
    }
}

// MARK: - AnyView

/// A type-erased view for conditional returns.
///
/// Use `AnyView` when you need to return different view types
/// from a conditional expression.
///
/// ```swift
/// func content(showDetail: Bool) -> AnyView {
///     if showDetail {
///         return AnyView(DetailView())
///     } else {
///         return AnyView(SummaryView())
///     }
/// }
/// ```
public struct AnyView: View {
    /// The wrapped child, stored as a single existential so the (often large,
    /// deeply-generic) view value is boxed ONCE here rather than captured into a
    /// pair of escaping measure / render closure contexts. The `Renderable` /
    /// `Layoutable` conformances open it back to the concrete type via implicit
    /// existential opening — identical dispatch to the old captured closures.
    /// Mirrors `ChildView` (see `ChildInfo.swift`).
    ///
    /// The value hash reads it as the plan reads any existential field: its
    /// content's type, then the content by its own plan — opened from the
    /// existential by Swift, never read out of its container, and never the
    /// address of the box holding it, which names a value only while that
    /// value is alive (a freed box's comes straight back for the next one).
    /// The type is mixed because nothing else in the key says it: the key's
    /// own view type is `AnyView` for every erased view.
    private let view: any View

    /// Creates an AnyView wrapping the given view.
    ///
    /// - Parameter view: The view to type-erase.
    public init<V: View>(_ view: V) {
        self.view = view
    }

    public var body: Never {
        fatalError("AnyView renders via Renderable")
    }
}

// MARK: - AnyView's Value

extension AnyView {
    /// `AnyView`'s whole job is to put its content somewhere else and hold the
    /// address, so its own bytes are that address — see ``View/_valueIsBoxed``.
    public static var _valueIsBoxed: Bool { true }

    /// A hash of the CONTENT, for the per-pass memo keys.
    ///
    /// `AnyView`'s whole job is to put its content somewhere else and hold the
    /// address, so its own bytes are that address — and an address names a
    /// value only while that value is alive. `viewValueHash` asks this instead.
    var erasedValueHash: Int { erasedViewValueHash(view) }
}

// MARK: - ConditionalView's Value

extension ConditionalView: _ValueHashing {
    /// The branch, then its content by its own plan — read by a `switch`,
    /// never from the case's byte, and never the other branch's payload,
    /// which holds whatever the memory held before. `nonisolated`, as every
    /// step is (see `ValueHashPlans`).
    package nonisolated static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .trueContent(let content):
            hash = mixHashWord(hash, ValueHashMark.firstBranch)
            return plans.mixValue(content, into: &hash)
        case .falseContent(let content):
            hash = mixHashWord(hash, ValueHashMark.secondBranch)
            return plans.mixValue(content, into: &hash)
        }
    }
}

// MARK: - AnyView Rendering

extension AnyView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIkitView.renderToBuffer(view, context: contentContext(noting: context))
        // Its content drew at this identity, unchanged: a transition in it
        // left the picture a slot that held this `AnyView` would play. Said
        // here, by value, because the slot knows only the type `AnyView`.
        context.noteDepartureDrawnWhole(byErasing: type(of: view))
        return buffer
    }
}

// MARK: - AnyView Cache Coherency

extension AnyView {
    /// The context the content is drawn and measured in, after telling the
    /// render cache what TYPE of content it is.
    ///
    /// An `AnyView` draws its content at its own identity, and so does every
    /// modifier inside it. Swapping the content for one of another type —
    /// `AnyView(row.foregroundStyle(.red))` one frame, `AnyView(row)` the next,
    /// the usual type-erased conditional — therefore leaves every memo below
    /// at the identity it had, keyed by a value that did not change. It was
    /// served drawn in the style of the content that had gone. The type is
    /// noted (`RenderCache.noteErasedContent`), and a change clears the
    /// subtree, on whichever walk sees it first.
    ///
    /// Not by giving the content a child identity named by its type, which is
    /// what SwiftUI's identity amounts to: a node built on every visit cost
    /// `anyview` +21% and `deep` +5.8%, where this costs a table probe.
    ///
    /// The depth goes up for the content, as an environment modifier's does,
    /// so two `AnyView`s nested at one identity note under two keys rather
    /// than the outer answering for both.
    fileprivate func contentContext(noting context: RenderContext) -> RenderContext {
        var contentContext = context
        contentContext.environmentApplicationDepth += 1
        guard let cache = context.renderCache else { return contentContext }
        if cache.noteErasedContent(
            ObjectIdentifier(type(of: view)), identity: context.identity,
            depth: context.environmentApplicationDepth)
        {
            cache.clearAffected(by: context.identity)
        }
        return contentContext
    }
}

// MARK: - EmptyView Rendering

extension EmptyView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer()
    }
}

// MARK: - ConditionalView Child Flattening

/// A conditional's active branch flattens into the enclosing stack — SwiftUI
/// semantics: `if`/`else` around a `ForEach` (or several views) contributes
/// the branch's CHILDREN to the parent, it does not bundle them into one
/// opaque block. Without this, a `ForEach` under an `if` reached the
/// bare-`ForEach` render path, which is deliberately empty (`ForEach` has no
/// standalone rendering), and the rows silently vanished.
extension ConditionalView: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        switch self {
        case .trueContent(let content):
            resolveChildViews(from: content, context: context)
        case .falseContent(let content):
            resolveChildViews(from: content, context: context)
        }
    }

    /// The branch step `renderToBuffer` applies, made available to the
    /// FLATTENING path — which is the one a stack takes, and which had no way
    /// to tell the branches apart. The labels match that method's exactly, or
    /// an identity built by one would not equal an identity built by the other.
    public var identityBranchLabel: String? {
        switch self {
        case .trueContent: "true"
        case .falseContent: "false"
        }
    }
}

/// An optional view (an `if` without `else`) flattens the same way: present
/// content contributes its children, `nil` contributes nothing — *unless* what
/// was there is still leaving.
///
/// ## Why `nil` is sometimes not nothing
///
/// A removal transition has no view to play it: the body no longer produces
/// one. What plays it is whatever still stands in its place, and for an
/// optional rendered directly (a page's body, a modifier's content) that is the
/// `nil` itself — see ``DepartureStore``.
///
/// Flattening took even that away. `if` inside a stack is the commonest way a
/// view comes and goes, and flattening `nil` to *no children at all* meant the
/// instant the condition went false there was no slot left to draw into: such
/// views animated in and jumped out. So a `nil` that something is still leaving
/// from keeps one slot — a `DepartureSlot`, drawing the picture that view left
/// behind — until the removal has played out, and then goes back to
/// contributing nothing.
///
/// The slot borrows `Wrapped`'s identity rather than `Optional`'s, so it lands
/// on exactly the address the present view rendered at and finds what that view
/// left behind. It is claimed only when the store confirms a live departure at
/// that address, LEFT BY a view of that type or by one inside it that it draws
/// unchanged (`departingPictureType(heldAs:)`) — the transition must be the
/// view the `if` held, give or take wrappers that draw nothing of their own,
/// or the picture would be drawn without what stood around it (see
/// `DepartureStore.departing(at:ofType:nowNanos:frameAnimation:)`). The
/// store's emptiness is checked first, which is what keeps every `nil` in every
/// app that animates nothing costing exactly what it did before.
///
/// ## The present view is addressed the way the `nil` will be
///
/// "Exactly the address the present view rendered at" holds only if the
/// present view is given that address outright, as `(Wrapped, 0)` under the
/// context this is handed — the same child the `nil` below builds. Handed over
/// as a bare child instead, its address was worked out later from whatever it
/// had become by then, and two ordinary shapes made that something else:
///
/// - Under a wrapper that distributes over its content's members (`.frame`,
///   `.opacity`, `.disabled` — ``ContentRewrapping``), the member is re-wrapped
///   before anything addresses it, so it rendered as `FlexibleFrameView<Wrapped>`
///   while the `nil` looked for `Wrapped`. `(show ? panel : nil).frame(…)` in a
///   stack animated in and jumped out.
/// - As a container's only content, or a lone branch's, a bare child is
///   TRANSPARENT — it renders at the container's own identity — while the
///   `nil` claims a step below it. `VStack { if show { panel } }` did the same.
///
/// Content that is itself a provider still flattens through that provider, and
/// its members are addressed by it rather than by this. Where it holds ONE view
/// with nothing drawn between — a nested `if`, a `Group` of one view, an
/// `if`/`else` — the provider says where it put that view
/// (`DepartingSlotAddressing`), and the `nil` claims that instead. A `Group`
/// of one view comes back transparent, so it is pinned to `(its type, 0)` here,
/// the step a tuple splice would give it, or as a container's only content it
/// rendered at the container's own identity. Content with several members (a
/// tuple, a `ForEach`) has no single slot to keep; ``View/transition(_:)``
/// lists it among the removals that still jump.
extension Optional: ChildViewProvider where Wrapped: View {
    public func childViews(context: RenderContext) -> [ChildView] {
        switch self {
        case .some(let wrapped):
            guard let provider = wrapped as? ChildViewProvider else {
                return [ChildView(wrapped, childIndex: 0)]
            }
            let children = resolveChildViews(from: wrapped, as: provider, context: context)
            guard children.count == 1 else { return children }
            return [children[0].addressedIfTransparent(under: context.identity)]
        case .none:
            // The fast path, and all an app that animates nothing pays.
            guard let storage = context.stateStorage, !storage.departures.isEmpty else { return [] }
            // The present view's address — `(Wrapped, 0)` for a plain view,
            // wherever its provider put it otherwise. A splice keeps a
            // positional child's inner index and a resolved child's identity,
            // so both land on the same step under the same parent.
            return TUIkitView.departingSlot(
                heldAs: Wrapped.self, context: context, transparentAtScope: false
            ).map { [$0] } ?? []
        }
    }
}

// MARK: - ConditionalView Rendering

extension ConditionalView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let stateStorage = context.stateStorage!

        // On the render path, only invalidate the now-inactive branch when the
        // case actually FLIPPED since the last rendered frame. On a non-flip
        // frame the inactive branch was never rendered (or was already pruned by
        // `endRenderPass` when it last left the tree), so it holds no persisted
        // state and `invalidateDescendants` would be a no-op — eliding it, and
        // the branch identity-node alloc it needs, is byte-identical.
        //
        // A measure invalidates NOTHING. Measuring must not mutate persistent
        // state, and a measure that reaches this path does — `_ButtonCore` (and
        // every other `measureFixedByRendering` view) measures by rendering, so
        // a plain `Button` inside an `if` ran a full sweep of the state store on
        // every measure of every frame. It was also pure waste: the branch that
        // is about to flip is invalidated by the RENDER below before the new
        // branch draws, so dropping the inactive branch's state early cannot
        // change what any frame contains.
        //
        // The saving is not just the sweep. `invalidateDescendants` scans both
        // state dictionaries end to end and allocates an array of matches for
        // each, and the branch identity it is handed costs an identity-node
        // allocation — all of it now skipped on the measure path.
        let isTrueBranch: Bool
        switch self {
        case .trueContent: isTrueBranch = true
        case .falseContent: isTrueBranch = false
        }

        let shouldInvalidate =
            !context.isMeasuring
            && stateStorage.recordConditionalBranch(
                context.identity, isTrueBranch: isTrueBranch)

        switch self {
        case .trueContent(let content):
            if shouldInvalidate {
                stateStorage.invalidateDescendants(of: context.identity.branch("false"))
            }
            return TUIkitView.renderToBuffer(content, context: context.withBranchIdentity("true"))
        case .falseContent(let content):
            if shouldInvalidate {
                stateStorage.invalidateDescendants(of: context.identity.branch("true"))
            }
            return TUIkitView.renderToBuffer(content, context: context.withBranchIdentity("false"))
        }
    }
}

// MARK: - ViewArray Rendering

extension ViewArray: Renderable, ChildInfoProvider {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(verticallyStacking: childInfos(context: context).compactMap(\.buffer))
    }

    public func childInfos(context: RenderContext) -> [ChildInfo] {
        elements.enumerated().map { index, element in
            makeChildInfo(
                for: element,
                context: context.withChildIdentity(type: type(of: element), index: index)
            )
        }
    }
}

// MARK: - Transparent-wrapper Layout

// These wrappers impose no geometry of their own — their size is exactly
// the size of the view they wrap. Declaring `Layoutable` (forwarding the
// measurement to the child) keeps the wrapped subtree out of measureChild's
// render-to-measure fallback, which would otherwise render it to measure it
// (historically twice — a second render probed flexibility, since retired) on
// top of the real render. The render paths are unchanged, so output is
// identical; only the measure pass gets cheaper.

// AnyView forwards its measurement to the wrapped view (opening the stored
// `any View` existential to its concrete type), so its type-erased subtree is
// measured structurally — like the transparent wrappers above — instead of
// through measureChild's render-to-measure fallback (which rendered the whole
// erased subtree to measure it). This is behaviour-correct: the flexibility
// contract (`ViewSize`) settled that `sizeThatFits` is canonical and the
// fallback's old "+8" probe *over-reported* flexibility for wrapping content;
// with the stacks/containers reconciled to the contract, the forwarded measure
// agrees with the render (the measure/render equivalence harness — the oracle —
// covers AnyView(Text) and AnyView(flexFrame), and any wrapped content it
// covers). The earlier "forwarded measure differs" objection was against that
// imprecise +8 probe, not the render.
//
// ⚠️ Changing AnyView's stored layout (it holds a single `any View`
// existential — a fixed 5-word inline buffer + metadata + witness table) requires
// a CLEAN build (`swift package clean`). AnyView is a non-resilient struct used
// across TUIkitView → TUIkit → consumers; a size change does not bump
// TUIkitView's public interface hash, so an INCREMENTAL build may not recompile
// cross-module dependents — they keep the old layout and corrupt memory at
// runtime. This is an incremental-compilation (Swift driver / SwiftPM) bug, not
// a codegen bug (witnesses are correct in -Onone IR). Clean builds are fine, so
// this is benign in practice: clean-build after pulling a change to AnyView's
// storage.

extension AnyView: Layoutable {
    /// Forwards measurement to the wrapped view — see the note above — after
    /// noting its type, as the render does (`contentContext(noting:)`): the
    /// measure walk runs first, and a swap noticed only by the render would
    /// already have served a stale size.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(view, proposal: proposal, context: contentContext(noting: context))
    }
}

extension EmptyView: Layoutable {
    /// An empty view occupies no cells.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.fixed(0, 0)
    }
}

extension ConditionalView: Layoutable {
    /// Measures whichever branch is present, using the same branch identity
    /// the render pass uses so `@State` resolves identically. The inactive-
    /// branch state invalidation in `renderToBuffer` is a render-time
    /// side-effect and is intentionally not repeated during measurement.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        switch self {
        case .trueContent(let content):
            return measureChild(content, proposal: proposal, context: context.withBranchIdentity("true"))
        case .falseContent(let content):
            return measureChild(content, proposal: proposal, context: context.withBranchIdentity("false"))
        }
    }
}
