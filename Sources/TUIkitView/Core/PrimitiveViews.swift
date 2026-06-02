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

// NOTE: AnyView is deliberately NOT made Layoutable, and its storage must NOT
// change. The single render closure above is the only form that does not
// crash. Changing AnyView's storage in *any* of these ways trips a Swift
// compiler codegen defect that corrupts the value at runtime:
//   - adding a second (measure) closure capturing the wrapped view,
//   - adding a stored property (even an inert tuple pad), or
//   - boxing the view in an abstract-base + generic-subclass class.
// Each manifests as a garbage pointer in the *compiler-generated* copy/destroy
// machinery — e.g.
//     swift_retain  <-  initializeWithCopy for AnyView  <-  renderToBuffer
//     swift_release <-  (class-box variant), SIGSEGV/SIGBUS —
// retaining/releasing a non-pointer (the bad "object" is small ASCII text
// data, e.g. 0x61/0x78 = 'a'/'x', from the rendered subtree). The value
// witnesses themselves are correctly generated (verified in -Onone IR: the
// copy retains exactly the right offsets), so the corruption is upstream in
// codegen, not app logic. It is single-threaded (reproduces with
// `--no-parallel`, so not a data race) and not stack overflow (shallow ~20
// frames). Adding an inert 24-byte pad makes it DETERMINISTIC (crashes every
// run, suite and standalone); the two-closure form is flakier. Confirmed on
// Swift 6.2.4 via lldb + swiftpm-testing-helper .ips reports, reproduced by
// AlignmentBoxSquishTests / AnyViewTests. AnyView therefore keeps the
// render-to-measure fallback (it is also far less common than `if/else`,
// which the ConditionalView conformance below already covers). Do NOT change
// AnyView's storage without confirming the crash is gone on the toolchain in
// use; the smallest repro is a one-line inert pad field here + the full suite.

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
