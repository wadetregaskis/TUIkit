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

    /// Creates an AnyView wrapping the given view.
    ///
    /// - Parameter view: The view to type-erase.
    public init<V: View>(_ view: V) {
        self._render = { context in
            TUIkitView.renderToBuffer(view, context: context)
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
        switch self {
        case .trueContent(let content):
            stateStorage.invalidateDescendants(of: context.identity.branch("false"))
            return TUIkitView.renderToBuffer(content, context: context.withBranchIdentity("true"))
        case .falseContent(let content):
            stateStorage.invalidateDescendants(of: context.identity.branch("true"))
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
// render-to-measure fallback, which would otherwise render it twice per
// frame — once for its natural size and once more to probe flexibility —
// on top of the real render. The render paths are unchanged, so output is
// identical; only the measure pass gets cheaper.

// NOTE: AnyView is deliberately NOT made Layoutable; it keeps the
// render-to-measure fallback. Forwarding the measure to the wrapped view (as
// the wrappers above do) is NOT behaviour-equivalent for AnyView's *arbitrary*
// content: a child's own `sizeThatFits` is not always render-consistent for
// flexible / wrapping / nested content (e.g. `VStack`/`HStack` under-report
// width-flexibility vs what re-rendering 8 cells wider observes), and AnyView's
// fallback — which actually re-renders — is the behaviour that ships. A
// characterization test confirmed the forwarded measure differs (width and
// width-flexibility) for the nested-alignment-row and wrapping cases, though no
// current layout test regresses. The unlike-Conditional/Equatable distinction
// is that those wrap a single statically-known branch; AnyView erases anything.
//
// ⚠️ Also: changing AnyView's stored layout requires a CLEAN build. AnyView is
// a non-resilient struct used across TUIkitView → TUIkit → tests; a layout
// change via a private member (a second closure, a pad, …) changes its size but
// not TUIkitView's public interface hash, so an INCREMENTAL `swift build` does
// not recompile the cross-module dependents — they keep the old, smaller layout
// and corrupt memory at runtime. A clean build is fine. This is an
// incremental-compilation (Swift driver / SwiftPM) bug, NOT a codegen bug —
// AnyView's value witnesses are correctly generated (verified in -Onone IR).
// It masqueraded as a "compiler crash" through earlier investigation. Minimal
// repro + analysis: `anyview-incremental-repro/` (untracked) + the
// perf-optimisation handoff doc. So if you do change AnyView's storage,
// `rm -rf .build` before testing.

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
