//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    private let _render: (RenderContext) -> FrameBuffer
    private let _measure: (ProposedSize, RenderContext) -> ViewSize

    /// Creates an AnyView wrapping the given view.
    ///
    /// - Parameter view: The view to type-erase.
    public init<V: View>(_ view: V) {
        self._render = { context in
            TUIkitView.renderToBuffer(view, context: context)
        }
        // Capture the wrapped view's measurement too, so AnyView can forward
        // `sizeThatFits` to it (see the `Layoutable` conformance) rather than
        // falling into measureChild's render-to-measure fallback.
        self._measure = { proposal, context in
            measureChild(view, proposal: proposal, context: context)
        }
    }

    public var body: Never {
        fatalError("AnyView renders via Renderable")
    }
}

// MARK: - AnyView Rendering

extension AnyView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        _render(context)
    }
}

// MARK: - EmptyView Rendering

extension EmptyView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer()
    }
}

// MARK: - ConditionalView Rendering

extension ConditionalView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let stateStorage = context.environment.stateStorage!

        // On the render path, only invalidate the now-inactive branch when the
        // case actually FLIPPED since the last rendered frame. On a non-flip
        // frame the inactive branch was never rendered (or was already pruned by
        // `endRenderPass` when it last left the tree), so it holds no persisted
        // state and `invalidateDescendants` would be a no-op — eliding it, and
        // the branch identity-node alloc it needs, is byte-identical.
        //
        // During measurement we must not mutate the branch-tracking map
        // (measure-side-effect rule). The Layoutable conformance handles the
        // measure pass and never renders here; a measure that *does* reach this
        // path (a Renderable parent rendering us in measuring mode) keeps the
        // original unconditional invalidate so output stays identical.
        let isTrueBranch: Bool
        switch self {
        case .trueContent: isTrueBranch = true
        case .falseContent: isTrueBranch = false
        }

        let shouldInvalidate: Bool
        if context.isMeasuring {
            shouldInvalidate = true
        } else {
            shouldInvalidate = stateStorage.recordConditionalBranch(
                context.identity, isTrueBranch: isTrueBranch)
        }

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

// AnyView forwards its measurement to the wrapped view (via the captured
// `_measure`), so its type-erased subtree is measured structurally — like the
// transparent wrappers above — instead of through measureChild's render-to-
// measure fallback (which rendered the whole erased subtree to measure it).
// This is behaviour-correct: the flexibility contract (`ViewSize`) settled that
// `sizeThatFits` is canonical and the fallback's old "+8" probe *over-reported*
// flexibility for wrapping content; with the stacks/containers reconciled to the
// contract, the forwarded measure agrees with the render (the measure/render
// equivalence harness — the oracle — covers AnyView(Text) and AnyView(flexFrame),
// and any wrapped content it covers). The earlier "forwarded measure differs"
// objection was against that imprecise +8 probe, not the render.
//
// ⚠️ Changing AnyView's stored layout (it now holds a second closure) requires a
// CLEAN build (`swift package clean`). AnyView is a non-resilient struct used
// across TUIkitView → TUIkit → consumers; a size change does not bump
// TUIkitView's public interface hash, so an INCREMENTAL build may not recompile
// cross-module dependents — they keep the old, smaller layout and corrupt memory
// at runtime. This is an incremental-compilation (Swift driver / SwiftPM) bug,
// not a codegen bug (witnesses are correct in -Onone IR). Clean builds are fine,
// so this is benign in practice: clean-build after pulling a change to AnyView's
// storage.

extension AnyView: Layoutable {
    /// Forwards measurement to the wrapped view — see the note above.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        _measure(proposal, context)
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
