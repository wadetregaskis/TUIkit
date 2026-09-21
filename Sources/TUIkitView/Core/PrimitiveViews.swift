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

// MARK: - AnyView Rendering

extension AnyView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(view, context: context)
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
/// from keeps one slot, drawn by ``Optional`` itself, until the removal has
/// played out — and then goes back to contributing nothing.
///
/// The slot borrows `Wrapped`'s identity rather than `Optional`'s, so it lands
/// on exactly the address the present view rendered at and finds what that view
/// left behind. It is claimed only when the store confirms a live departure at
/// that address, which is what keeps every `nil` in every app that animates
/// nothing costing exactly what it did before: one dictionary-empty check.
extension Optional: ChildViewProvider where Wrapped: View {
    public func childViews(context: RenderContext) -> [ChildView] {
        switch self {
        case .some(let wrapped):
            return resolveChildViews(from: wrapped, context: context)
        case .none:
            guard let storage = context.stateStorage,
                storage.departures.hasDeparture(
                    directlyUnder: context.identity, ofType: Wrapped.self,
                    nowNanos: context.environment.frameNowNanos,
                    frameAnimation: context.environment.canAnimate
                        ? context.environment.transaction.effectiveAnimation : nil)
            else { return [] }
            // `childIndex` is provisional: the enclosing container rebases it to
            // the flattened position, which is the same position the present
            // view held as long as nothing before it also came or went.
            return [ChildView(self, identityType: Wrapped.self, childIndex: 0)]
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
    /// Forwards measurement to the wrapped view — see the note above.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(view, proposal: proposal, context: context)
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
