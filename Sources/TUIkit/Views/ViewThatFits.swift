//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// A candidate whose reported extent *tracks* the space it is offered carries no
/// ideal to compare against, so it is accepted on that axis — a view that fills
/// the extent it is given cannot overflow it. A row holding a `Spacer`, a
/// `List`, a `Table` with a `.ratio(_:)` column, `.frame(maxWidth: .infinity)`:
/// all of those win at every width, and no candidate listed after one of them is
/// ever reached. A candidate that flexes but names a *fixed* minimum — a bare
/// `Slider`, `TextField` or `NavigationSplitView`, each of which answers an
/// unspecified proposal with its own ideal — is still held to that minimum and
/// can still lose. To make a filling candidate lose where it is too narrow,
/// bound it (`.frame(maxWidth: 60)`) or list it after the ones to try first.
///
/// - Note: This deviates from SwiftUI, whose stacks report a rigid ideal for an
///   unproposed axis and which therefore rejects a filling candidate whose rigid
///   content overflows. That report is not available here: `_HStackCore` derives
///   its width from the budget it distributes, and `ContainerViewCore` derives a
///   bordered container's own fill flag from what its body *reported* while the
///   render path derives it from what the body *drew* — so reporting a rigid
///   ideal would make every bordered panel around a `Spacer` row measure as
///   hugging while still rendering filled, breaking measure/render equivalence.
///   Until those two are reconciled, a filling candidate wins at every width and
///   clips rather than falling back.
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
        // Two probes, one cell apart, both far wider than any terminal. The
        // first is the candidate's ideal, as before. The second answers a
        // question the first cannot ask.
        //
        // On a flexible axis a `ViewSize`'s extent is a MINIMUM (the flexibility
        // contract on ``ViewSize``), and the views that distribute their extent
        // report the budget they were handed as that "minimum": `_HStackCore`
        // gives a `Spacer` the surplus and reports the sum, `_ListCore`,
        // `_ProgressViewCore`, `_TextEditorCore` and `_GeometryReaderCore`
        // answer `proposal ?? availableWidth` outright, and a `Table` with a
        // `.ratio(_:)` column reports `Int(Double(contentWidth) * ratio)` — a
        // FRACTION of it. Comparing any of those against the real extent
        // rejected the candidate at every terminal size, so
        // `ViewThatFits { HStack { Text("Name"); Spacer(); Text("Size") };
        // column }` always drew the column, however wide the terminal.
        //
        // A report that MOVES when the budget moves by one cell is the budget's
        // number, not the candidate's: it says nothing about fit, and a view
        // that fills the extent it is offered cannot overflow it, so it fits. A
        // report that is identical at both probes is a real minimum (a bare
        // `Slider`, `TextField` or `NavigationSplitView` answers an unspecified
        // proposal with its own ideal) and is still held to it.
        //
        // Deliberately NOT a magnitude test against the probe extent: the
        // `.ratio` table above reports 300_000 at a 1_000_000 probe and 30_000
        // at `.ratio(0.03)`, so every threshold silently keeps the bug for some
        // greedy view — and the symptom, "the fallback was chosen", looks like a
        // layout decision rather than a defect.
        let probeExtent = 1_000_000
        var probeContext = context
        probeContext.availableWidth = probeExtent
        probeContext.availableHeight = probeExtent

        for (index, candidate) in candidates.enumerated() {
            let size = candidate.measure(proposal: .unspecified, context: probeContext)
            let testsWidth = axes.contains(.horizontal)
            let testsHeight = axes.contains(.vertical)
            // Only a candidate that is flexible on a tested axis AND over-reports
            // it can be the case above, so the second probe is never paid for by
            // the rigid candidates that are the common shape.
            let overReportsWidth =
                testsWidth && size.isWidthFlexible && size.width > context.availableWidth
            let overReportsHeight =
                testsHeight && size.isHeightFlexible && size.height > context.availableHeight
            var narrower = size
            if overReportsWidth || overReportsHeight {
                var narrowerProbe = context
                narrowerProbe.availableWidth = probeExtent - 1
                narrowerProbe.availableHeight = probeExtent - 1
                narrower = candidate.measure(proposal: .unspecified, context: narrowerProbe)
            }
            let fitsWidth =
                !testsWidth
                || (size.isWidthFlexible && narrower.width != size.width)
                || size.width <= context.availableWidth
            let fitsHeight =
                !testsHeight
                || (size.isHeightFlexible && narrower.height != size.height)
                || size.height <= context.availableHeight
            if fitsWidth && fitsHeight {
                return index
            }
        }
        return candidates.count - 1
    }
}
