//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewThatFits.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Axis

/// The horizontal or vertical dimension of a layout.
public enum Axis: Sendable, CaseIterable, Equatable {
    /// The horizontal dimension.
    case horizontal

    /// The vertical dimension.
    case vertical

    /// A set of axes — horizontal, vertical, or both.
    public struct Set: OptionSet, Sendable, Equatable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The horizontal axis.
        public static let horizontal = Self(rawValue: 1 << 0)

        /// The vertical axis.
        public static let vertical = Self(rawValue: 1 << 1)
    }
}

// MARK: - ViewThatFits

/// A view that picks the first of its child views that fits the available
/// space, falling back to the last child when none of them fit.
///
/// `ViewThatFits` lets a layout adapt to the space it is given — most often
/// to switch a row to a column when the terminal is too narrow. List the
/// candidate layouts widest-/largest-first; `ViewThatFits` measures each in
/// turn and renders the first one whose ideal size fits.
///
/// ```swift
/// ViewThatFits {
///     // Preferred: everything on one row.
///     HStack {
///         Text("Name"); Text("Size"); Text("Modified")
///     }
///     // Fallback: stack vertically when the row is too wide.
///     VStack(alignment: .leading) {
///         Text("Name"); Text("Size"); Text("Modified")
///     }
/// }
/// ```
///
/// By default both axes are considered. Pass `in:` to constrain the test to
/// a single axis — for example `ViewThatFits(in: .horizontal)` only checks
/// whether a candidate fits horizontally and ignores its height.
///
/// - Important: A `ViewThatFits`'s size depends on the **available width**, not
///   the proposal alone — it reports (and renders) whichever candidate currently
///   fits. It satisfies the flexibility contract (``ViewSize``) — measured and
///   rendered sizes agree *at a given width* — but unlike an ordinary fixed view
///   its size is not constant across widths. A parent that measures it at one
///   width and then renders it at a narrower one can therefore land on different
///   candidates and mis-size it; measure and render it at the **same** width. (A
///   panel sized to its widest child then rendering a narrower child at the panel
///   width must clamp the rendered buffer back to the child's natural width
///   rather than re-render it narrower — see `TabView`'s content centring.)
public struct ViewThatFits<Content: View>: View {
    /// The axes along which candidate fit is evaluated.
    let axes: Axis.Set

    /// The candidate views, preferred first.
    let content: Content

    /// Creates a view that picks the first child that fits.
    ///
    /// - Parameters:
    ///   - axes: The axes to evaluate fit on (default: both).
    ///   - content: A ``ViewBuilder`` listing the candidate views,
    ///     most-preferred first.
    public init(
        in axes: Axis.Set = [.horizontal, .vertical],
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.content = content()
    }

    public var body: some View {
        _ViewThatFitsCore(axes: axes, content: content)
    }
}

// MARK: - Equatable Conformance

extension ViewThatFits: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: ViewThatFits<Content>, rhs: ViewThatFits<Content>) -> Bool {
        lhs.axes == rhs.axes && lhs.content == rhs.content
    }
}

// MARK: - Internal Core

/// Internal view that measures the candidates and renders the chosen one.
private struct _ViewThatFitsCore<Content: View>: View, Renderable, Layoutable {
    let axes: Axis.Set
    let content: Content

    var body: Never {
        fatalError("_ViewThatFitsCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let candidates = resolveChildViews(from: content, context: context)
        guard !candidates.isEmpty else { return ViewSize.fixed(0, 0) }
        let index = chosenIndex(candidates, context: context)
        return candidates[index].measure(proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let candidates = resolveChildViews(from: content, context: context)
        guard !candidates.isEmpty else { return FrameBuffer() }
        let index = chosenIndex(candidates, context: context)
        return candidates[index].render(
            width: context.availableWidth,
            height: context.availableHeight,
            context: context
        )
    }

    /// Returns the index of the first candidate whose ideal size fits the
    /// available space along the configured axes, or the last index when
    /// none fit.
    private func chosenIndex(_ candidates: [ChildView], context: RenderContext) -> Int {
        // Measure each candidate against effectively-unbounded space so it
        // reports its true ideal size — containers like HStack otherwise
        // cap their reported width at the available width, which would make
        // every candidate appear to fit.
        var probeContext = context
        probeContext.availableWidth = 1_000_000
        probeContext.availableHeight = 1_000_000

        for (index, candidate) in candidates.enumerated() {
            let size = candidate.measure(proposal: .unspecified, context: probeContext)
            let fitsWidth = !axes.contains(.horizontal) || size.width <= context.availableWidth
            let fitsHeight = !axes.contains(.vertical) || size.height <= context.availableHeight
            if fitsWidth && fitsHeight {
                return index
            }
        }
        return candidates.count - 1
    }
}
