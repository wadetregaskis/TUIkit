//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewColumnWidthModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Column Width Preference

/// A preference key for column width values.
///
/// Read by ``NavigationSplitView``, which measures each of its columns inside a
/// pushed preference scope before deciding how wide to make it — a preference
/// rather than an environment value or a static conformance because the modifier
/// may sit anywhere inside the column, and the answer has to travel back up.
struct NavigationSplitViewColumnWidthKey: PreferenceKey {
    static let defaultValue: NavigationSplitViewColumnWidth? = nil

    static func reduce(value: inout NavigationSplitViewColumnWidth?, nextValue: () -> NavigationSplitViewColumnWidth?) {
        // Later values override earlier values
        if let next = nextValue() {
            value = next
        }
    }
}

/// Column width configuration for NavigationSplitView.
///
/// Stores the fixed width or min/ideal/max constraints for a column.
struct NavigationSplitViewColumnWidth: Equatable, Sendable {
    /// A fixed column width in characters.
    let fixed: Int?

    /// The minimum column width in characters.
    let min: Int?

    /// The ideal column width in characters.
    let ideal: Int?

    /// The maximum column width in characters.
    let max: Int?

    /// Creates a fixed-width column configuration.
    init(fixed: Int) {
        self.fixed = fixed
        self.min = nil
        self.ideal = nil
        self.max = nil
    }

    /// Creates a flexible column width configuration.
    init(min: Int?, ideal: Int?, max: Int?) {
        self.fixed = nil
        self.min = min
        self.ideal = ideal
        self.max = max
    }
}

// MARK: - Column Width Modifier

/// A view that sets the preferred width of a navigation split view column.
///
/// This view sets a preference that ``NavigationSplitView`` can read to
/// determine column widths.
struct NavigationSplitViewColumnWidthView<Content: View>: View {
    /// The content view.
    let content: Content

    /// The column width configuration.
    let columnWidth: NavigationSplitViewColumnWidth

    var body: Never {
        fatalError("NavigationSplitViewColumnWidthView renders via Renderable")
    }
}

extension NavigationSplitViewColumnWidthView {
    /// Publishes this column's width request into the enclosing preference
    /// scope, having first declared it as a per-pass side effect.
    ///
    /// The declaration is not bookkeeping: the preference stack is rebuilt every
    /// pass and the measure memo is per-pass scratch, so a memoizing ancestor
    /// that served a cached buffer — or a cached measurement — would silently
    /// drop this write from the frame's collection, and the column would snap
    /// back to the style default. ``PreferenceModifier`` declares its write the
    /// same way.
    private func publishColumnWidth(context: RenderContext) {
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        context.environment.preferenceStorage?.setValue(
            columnWidth, forKey: NavigationSplitViewColumnWidthKey.self)
    }
}

extension NavigationSplitViewColumnWidthView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        publishColumnWidth(context: context)
        return TUIkit.renderToBuffer(content, context: context)
    }
}

extension NavigationSplitViewColumnWidthView: Layoutable {
    /// Publishes the column-width *preference* and then measures as `content`,
    /// which it renders unchanged.
    ///
    /// Publishing during a MEASURE, not just during the render, is what makes
    /// the modifier work at all: ``NavigationSplitView`` has to know what a
    /// column asked for *before* it can render that column into the resulting
    /// width, so it reads this key by measuring each column inside a pushed
    /// preference scope. Unlike ``PreferenceModifier``, which gates its write on
    /// `!context.isMeasuring` because an accumulating `reduce` would double-apply
    /// there, this key's `reduce` keeps the last value: writing it twice in a
    /// pass is idempotent.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        publishColumnWidth(context: context)
        return measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - View Extension

extension View {
    /// Sets the preferred width for a navigation split view column.
    ///
    /// Use this modifier on a column's content to specify an exact width
    /// in characters.
    ///
    /// ```swift
    /// NavigationSplitView {
    ///     List { ... }
    ///         .navigationSplitViewColumnWidth(30)
    /// } detail: {
    ///     DetailView()
    /// }
    /// ```
    ///
    /// The column is held at that width: the split view opens it there instead
    /// of at its style's proportional share (or its content width under
    /// ``NavigationSplitViewStyle/sizeToFitFromLeft``), and dragging or
    /// arrow-resizing its divider settles straight back to it — a fixed width is
    /// the degenerate `min…max` band. The layout's own limits still apply: every
    /// column keeps at least ten cells and leaves at least that many for each
    /// column to its right.
    ///
    /// Applies to any column but the trailing one, which always absorbs the
    /// width the columns before it leave.
    ///
    /// - Parameter width: The preferred column width in characters.
    /// - Returns: A view with the column width preference set.
    public func navigationSplitViewColumnWidth(_ width: Int) -> some View {
        NavigationSplitViewColumnWidthView(
            content: self,
            columnWidth: NavigationSplitViewColumnWidth(fixed: width)
        )
    }

    /// Sets flexible width constraints for a navigation split view column.
    ///
    /// Use this modifier on a column's content to specify minimum, ideal,
    /// and maximum width constraints in characters.
    ///
    /// ```swift
    /// NavigationSplitView {
    ///     List { ... }
    ///         .navigationSplitViewColumnWidth(min: 20, ideal: 30, max: 50)
    /// } detail: {
    ///     DetailView()
    /// }
    /// ```
    ///
    /// The column opens at `ideal` — or, with no `ideal`, at the width it would
    /// have had anyway (its style's proportional share, or its content width
    /// under ``NavigationSplitViewStyle/sizeToFitFromLeft``) — and every width it
    /// takes afterwards, including one the user drags or arrow-resizes it to, is
    /// held inside `min…max`. An omitted bound constrains nothing. The layout's
    /// own limits still apply: every column keeps at least ten cells and leaves
    /// at least that many for each column to its right.
    ///
    /// Applies to any column but the trailing one, which always absorbs the
    /// width the columns before it leave.
    ///
    /// - Parameters:
    ///   - min: The minimum column width in characters (optional).
    ///   - ideal: The ideal column width in characters (optional).
    ///   - max: The maximum column width in characters (optional).
    /// - Returns: A view with the column width preference set.
    public func navigationSplitViewColumnWidth(
        min: Int? = nil,
        ideal: Int? = nil,
        max: Int? = nil
    ) -> some View {
        NavigationSplitViewColumnWidthView(
            content: self,
            columnWidth: NavigationSplitViewColumnWidth(min: min, ideal: ideal, max: max)
        )
    }
}
