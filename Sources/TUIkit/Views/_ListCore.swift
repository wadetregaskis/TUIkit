//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore.swift
//
//  Created by LAYERED.work
//  License: MIT

// `_ListCore` is a single cohesive render core (the windowed row source, the
// list core, and the content view that draws it) whose pieces are tightly
// coupled through the row/selection/overflow model; splitting it across files
// purely to satisfy the length ceiling would scatter that model for no clarity
// gain — the same rationale by which `type_body_length` is disabled project-wide.
// swiftlint:disable file_length

/// The horizontal cells `renderPlainLine`/`renderLineWithBadge` add around a
/// row's content: a 1-cell gutter on the left and at least 1 cell of padding on
/// the right. Row-width proposals must subtract this so a width-greedy row
/// still fits the interior after composition.
private let listRowGutter = 2

// MARK: - Row Source (windowed materialisation)

/// A windowed view over a `List`'s rows.
///
/// Every row's ``ListRowType`` (and thus its id) is known eagerly and cheaply —
/// that's all the scroll/selection handler needs for off-screen rows. Each row's
/// content *buffer*, by contrast, is materialised lazily and memoised, so only
/// the rows the overflow check and the visible window actually walk get built.
/// For a large flat `List` that's O(viewport) row boxes per frame instead of
/// O(total) — the dominant idle cost on long lists was allocating a content box
/// for every row every frame even though ~viewport are shown.
///
/// The eager paths (Sections, heterogeneous content) wrap their already-built
/// rows via ``eager(_:)``; ``row(at:)`` simply hands those back.
@MainActor
private final class RowSource<SelectionValue: Hashable & Sendable> {
    /// The number of rows. Known cheaply — O(1) for the windowed path
    /// (`ForEach.listRowCount`); the array length for the eager paths.
    let count: Int

    /// Whether every row is selectable content — true for the windowed `ForEach`
    /// path and the all-content fallbacks, false only for a heterogeneous row set
    /// (Sections, which interleave non-selectable header/footer rows). The
    /// handler reads this to skip building a per-row id map and selectable-index
    /// set for the all-content case, which is what keeps a huge flat list O(1) to
    /// set up. See ``_ListCore/resolvePopulatedHandler``.
    let allContent: Bool

    /// Resolves a row's type/id on demand — builds no content. O(1) per call, so
    /// the windowed path resolves ids only for the rows the handler / window
    /// actually touch (the visible window + the focused row), not all N.
    private let typeAt: (Int) -> ListRowType<SelectionValue>

    /// Builds the deferred content box for a row index.
    private let make: (Int) -> LazyListRowContent

    /// Per-frame memo so a row touched by both the overflow check and the visible
    /// window (or re-read by the compose pass) is built — and rendered — once.
    private var materialized: [Int: SelectableListRow<SelectionValue>] = [:]

    init(
        count: Int,
        allContent: Bool,
        typeAt: @escaping (Int) -> ListRowType<SelectionValue>,
        make: @escaping (Int) -> LazyListRowContent
    ) {
        self.count = count
        self.allContent = allContent
        self.typeAt = typeAt
        self.make = make
    }

    /// Wraps an already-built, materialised row array (the eager Section /
    /// fallback paths). The set is small, so indexing it for `typeAt` and
    /// scanning it for `allContent` are both cheap.
    static func eager(_ rows: [SelectableListRow<SelectionValue>]) -> RowSource {
        RowSource(
            count: rows.count,
            allContent: rows.allSatisfy(\.isSelectable),
            typeAt: { rows[$0].type },
            make: { rows[$0].content })
    }

    // `count` is the stored row count (an `Int`), not a Collection, so the
    // empty_count rule misfires — `isEmpty` is precisely what we're defining.
    // swiftlint:disable:next empty_count
    var isEmpty: Bool { count == 0 }

    /// The row's type/id at `index` — cheap, builds no content.
    func type(at index: Int) -> ListRowType<SelectionValue> { typeAt(index) }

    /// The fully-formed row at `index`, materialising (and memoising) its content
    /// box on first access. Reading the row's `.buffer` renders it once (cached).
    func row(at index: Int) -> SelectableListRow<SelectionValue> {
        if let existing = materialized[index] { return existing }
        let row = SelectableListRow(type: typeAt(index), content: make(index))
        materialized[index] = row
        return row
    }
}

// MARK: - List Core (Internal Rendering)

/// Internal core view that handles list rendering inside a
/// ContainerView.
///
/// # Interaction model
///
/// Selection, focus, and scroll position are three independent
/// concepts:
///
/// - **Scroll position** is moved by the mouse wheel (3 lines per
///   tick by default — see ``ViewConstants/mouseWheelScrollLines``).
///   Wheel scrolling NEVER changes the selection or the focused
///   row; it can scroll either out of view. This matches every
///   major desktop list-view convention (Finder, Explorer, VS
///   Code, etc.). The previous "wheel = arrow key" implementation
///   made unfocused lists look unscrollable until the invisible
///   selection bumped the viewport edge — exactly the wrong UX.
///
/// - **Selection / focus** is moved by the arrow keys when the
///   list itself has focus, and by clicking a row. Pressing an
///   arrow on a focused list whose selection has been scrolled
///   off-screen scrolls the viewport back to the new selection,
///   via the usual ``ItemListHandler/ensureFocusedItemVisible``
///   path.
///
/// - **Selection visibility when unfocused** defaults to hidden
///   (a desaturated highlight is too noisy in many contexts).
///   Opt-in with ``View/unfocusedSelectionVisibility(_:)``.
struct _ListCore<SelectionValue: Hashable & Sendable, Content: View, Footer: View>: View, Renderable, Layoutable {
    let title: String?
    let content: Content
    let footer: Footer?
    let singleSelection: Binding<SelectionValue?>?
    let multiSelection: Binding<Set<SelectionValue>>?
    let selectionMode: SelectionMode
    let focusID: String?
    let isDisabled: Bool
    let emptyPlaceholder: String
    let showFooterSeparator: Bool
    /// Row activation ("open") — Enter on the focused row (via the handler)
    /// or a double-click (via the container mouse handler). See
    /// ``List/onRowActivate(_:)``.
    let primaryAction: ((SelectionValue) -> Void)?

    var body: Never {
        fatalError("_ListCore renders via Renderable")
    }

    /// The List is greedy on both axes: it fills the width it is offered and pads
    /// to fill the height. So its size is simply the offered space — and crucially
    /// no rows are built or measured here. Previously, being `Renderable`-only,
    /// the layout measure pass discovered the List's size by rendering the whole
    /// list (windowed, but still the visible rows) every frame; now the measure
    /// pass is O(1).
    ///
    /// Both axes are reported *flexible* (the offered extent is a minimum, per
    /// the ``ViewSize`` contract, which names `List` as the canonical
    /// height-filling view). Reporting the filled height as *fixed* — as this
    /// once did — made every unframed List an immovable full-height demand, so
    /// sibling Lists in a `VStack` starved: the distributor's overflow branch
    /// placed the first at full height and collapsed the rest to zero (issue
    /// #6). Flexible height instead lands in the weighted-share branch, which
    /// splits the column evenly. Hugging content is opt-in via
    /// `.fixedSize(horizontal:)`, which proposes an unbounded width.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let height = proposal.height ?? context.availableHeight
        // Default: greedy on both axes, no rows built — the O(1) measure that
        // makes the layout pass cheap.
        guard context.environment.fixedSizeWidth else {
            return ViewSize(
                width: proposal.width ?? context.availableWidth, height: height,
                isWidthFlexible: true, isHeightFlexible: true)
        }
        // `.fixedSize(horizontal:)`: hug content — the widest of ALL rows, stable
        // across scroll. Opt-in, so building the rows to measure them is fine, and
        // the reported width is fixed (not flexible) so a stack hugs around it.
        return ViewSize.fixed(allRowsContentWidth(context: context), height)
    }

    /// The List's hugged width: the widest of every row (plus a title and the
    /// border), independent of the scroll position. Only used on the
    /// `.fixedSize(horizontal:)` path. Clears the fixed-size flag for the rows so
    /// the request doesn't leak into their own content.
    private func allRowsContentWidth(context: RenderContext) -> Int {
        var rowContext = context
        rowContext.environment.fixedSizeWidth = false
        let source = extractRows(from: content, context: rowContext)
        let widest = (0..<source.count).map { source.row(at: $0).buffer.width }.max() ?? 0
        let titleWidth = title.map { $0.strippedLength + 2 } ?? 0
        let borderOverhead = context.environment.listStyle.showsBorder ? 2 : 0
        // The widest row still gets its gutters when composed, so the hugged
        // width must include them or the row's trailing cells are clipped.
        return max(widest + listRowGutter, titleWidth) + borderOverhead
    }

    /// Captures the populated-state values that the mouse-
    /// handler attachment needs from the content rendering
    /// pass. `nil` in the empty-list case.
    private struct PopulatedRenderState {
        let handler: ItemListHandler<SelectionValue>
        let focusID: String
        let visibleRowYRanges: [VisibleRowRange]
        /// The rows behind ``visibleRowYRanges``, index-aligned with it (both
        /// are built from the same visible-window walk). Their buffers carry
        /// the rows' own hit-test regions, which `attachMouseHandlers` merges
        /// into the list's buffer.
        let visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)]
        /// The buffer column of the scrollbar and its line-height, when one is
        /// drawn (`nil` column = no bar). Drives the bar's mouse handler in
        /// `attachMouseHandlers`.
        var scrollbarColumn: Int?
        var scrollbarHeight = 0
    }

    private typealias VisibleRowRange = (
        rowIndex: Int, yStart: Int, height: Int, type: ListRowType<SelectionValue>
    )

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let style = context.environment.listStyle
        let stateStorage = context.environment.stateStorage!

        // Two border cells or none, on each axis: top + bottom rows, and left +
        // right columns.
        let borderOverhead = style.showsBorder ? 2 : 0

        // `.fixedSize(horizontal:)` makes the List hug its content; clear the flag
        // before extracting so it doesn't leak into the rows' own content. The
        // List's own honouring of it reads `context.environment.fixedSizeWidth`
        // (still set) in `buildPopulatedContent`.
        //
        // On the ordinary fill path, propose each row the width it actually gets
        // on screen: the interior minus the row gutters that `renderPlainLine`
        // adds around it. Extracting rows at the List's own full width let a
        // width-greedy row (`HStack { … Spacer() … }`) fill all of it, only for
        // the gutter + border clamp to chop the trailing cells — silently hiding
        // a right-flushed trailing view (issue #5).
        var rowContext = context
        if context.environment.fixedSizeWidth {
            rowContext.environment.fixedSizeWidth = false
        } else {
            rowContext.availableWidth = max(
                1, context.availableWidth - borderOverhead - listRowGutter)
        }
        let source = extractRows(from: content, context: rowContext)

        // Vertical chrome around the scrollable content; reserve
        // only what is actually present.
        let footerHeight = footer != nil ? 2 : 0  // footer line + separator
        let titleOverhead = title != nil ? 1 : 0
        let targetContentHeight = max(
            1,
            context.availableHeight - borderOverhead - titleOverhead - footerHeight
        )

        let contentLines: [String]
        let renderState: PopulatedRenderState?
        if source.isEmpty {
            contentLines = buildEmptyStateLines(context: context)
            renderState = nil
        } else {
            let result = buildPopulatedContent(
                source: source,
                context: context,
                stateStorage: stateStorage,
                palette: palette,
                style: style,
                targetContentHeight: targetContentHeight
            )
            contentLines = result.lines
            renderState = result.state
        }

        // Pad content to fill the available height (SwiftUI
        // behavior: List is greedy).
        var paddedContentLines = contentLines
        if paddedContentLines.count < targetContentHeight {
            let extra = targetContentHeight - paddedContentLines.count
            paddedContentLines.append(contentsOf: Array(repeating: "", count: extra))
        }

        var buffer = renderContainer(
            title: title,
            config: ContainerConfig(
                borderStyle: context.environment.appearance.borderStyle,
                borderColor: palette.border,
                titleColor: nil,
                padding: style.rowPadding,
                showFooterSeparator: showFooterSeparator,
                hasBorder: style.showsBorder
            ),
            content: _ListContentView(lines: paddedContentLines),
            footer: footer,
            context: context
        )

        if let state = renderState {
            attachMouseHandlers(
                to: &buffer,
                context: context,
                state: state,
                paddingTop: style.rowPadding.top
            )
        }
        return buffer
    }

    // MARK: - Empty-state placeholder

    /// Builds the single-line empty-state content for a list
    /// with no rows. The placeholder is padded out to the
    /// available width so an empty list keeps its full size
    /// instead of collapsing to the title's width.
    private func buildEmptyStateLines(context: RenderContext) -> [String] {
        let placeholderWidth = emptyPlaceholder.strippedLength
        // +2 for the "─ … ─" border decorations around the title.
        let titleWidth = title.map { $0.strippedLength + 2 } ?? 0
        let intrinsicWidth = max(placeholderWidth, titleWidth)
        let targetWidth: Int
        if context.hasExplicitWidth {
            // Subtract the two border columns only when the style draws a border;
            // a borderless (`.plain`) list fills the full available width.
            let borderOverhead = context.environment.listStyle.showsBorder ? 2 : 0
            targetWidth = max(intrinsicWidth, context.availableWidth - borderOverhead)
        } else {
            targetWidth = intrinsicWidth
        }
        let extra = max(0, targetWidth - placeholderWidth)
        return [emptyPlaceholder + String(repeating: " ", count: extra)]
    }

    // MARK: - Populated content

    /// Renders the populated-state content lines and captures
    /// the state the mouse handler needs (the handler itself,
    /// the persisted focus ID, and the per-row y-ranges so
    /// clicks can be translated back to a row index).
    private func buildPopulatedContent(
        source: RowSource<SelectionValue>,
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        style: any ListStyle,
        targetContentHeight: Int
    ) -> (lines: [String], state: PopulatedRenderState) {
        // A list only scrolls (and shows indicators) when its rows
        // don't all fit in the content area.
        let overflowing = rowsOverflow(source, targetContentHeight: targetContentHeight)

        // A scrollbar (opt-in via `.scrollbarVisibility`) supersedes the "N more"
        // text indicators: it marks the off-screen rows itself, so the rows then
        // fill the whole content area with no reserved indicator line. Decided up
        // front so the handler resolver can skip the offset-1 snap (which only
        // saves an indicator line a bar doesn't have — see resolvePopulatedHandler).
        let barVisibility = context.environment.scrollbarVisibility
        let wantsScrollbar =
            barVisibility != .hidden && (barVisibility == .visible || overflowing)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "list",
            propertyIndex: 1  // focusID
        )
        let handler = resolvePopulatedHandler(
            source: source,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: targetContentHeight,
            overflowing: overflowing,
            showsScrollbar: wantsScrollbar
        )
        FocusRegistration.register(context: context, handler: handler)
        let listHasFocus = FocusRegistration.isFocused(
            context: context, focusID: persistedFocusID)

        // Reserve a line for each scroll indicator that is actually
        // present at this offset, so the rows plus indicators fill
        // the content area exactly — no wasted blank line at the
        // ends (which used to push the "N more below" indicator one
        // row too high), and no overflow in the middle. With a bar,
        // the whole content area is the viewport (no reservation).
        let visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)]
        if wantsScrollbar {
            visibleRows = calculateVisibleRows(
                source: source, handler: handler, viewportHeight: targetContentHeight)
        } else {
            visibleRows = resolveVisibleWindow(
                source: source,
                handler: handler,
                contentHeight: targetContentHeight,
                overflowing: overflowing
            )
        }
        // Sync the viewport to the rows actually shown so the
        // handler's indicator predicates match the rendering.
        handler.viewportHeight = max(1, visibleRows.count)

        // Row width — the List is greedy on width (SwiftUI parity): fill the
        // available interior, growing past it only when a row is itself wider
        // than the space offered. Sizing to the widest *visible* row (the old
        // non-explicit path) made the List's box jump width as you scrolled past
        // wider/narrower rows; filling keeps it stable.
        //
        // `.fixedSize(horizontal:)` instead hugs content: the widest of ALL rows
        // (not just the visible ones — that's what keeps it stable), so the box is
        // content-sized and constant.
        let maxRowWidth = visibleRows.map { $0.row.buffer.width }.max() ?? 0
        let rowWidth: Int
        if context.environment.fixedSizeWidth {
            rowWidth = (0..<source.count).map { source.row(at: $0).buffer.width }.max() ?? 0
        } else {
            // Fill the interior: full available width when borderless (`.plain`),
            // minus the two border columns when bordered.
            let borderOverhead = style.showsBorder ? 2 : 0
            rowWidth = max(maxRowWidth, context.availableWidth - borderOverhead)
        }

        let lines: [String]
        let visibleRowYRanges: [VisibleRowRange]
        var scrollbarColumn: Int?
        var scrollbarHeight = 0
        if wantsScrollbar {
            let bar = listScrollbarCells(
                source: source,
                handler: handler,
                visibleRows: visibleRows,
                contentHeight: targetContentHeight,
                context: context,
                palette: palette
            )
            let contentRowWidth = max(1, rowWidth - 1)
            (lines, visibleRowYRanges) = composeScrollbarRowLines(
                visibleRows: visibleRows,
                handler: handler,
                listHasFocus: listHasFocus,
                contentRowWidth: contentRowWidth,
                bar: bar,
                style: style,
                context: context,
                palette: palette
            )
            // The bar is the last interior column: border (1) + left padding, then
            // the content, then the bar cell. Matches the `1 + paddingTop` content
            // inset used for click mapping (see attachMouseHandlers).
            scrollbarColumn = 1 + style.rowPadding.leading + contentRowWidth
            scrollbarHeight = bar.count
        } else {
            (lines, visibleRowYRanges) = composeRowLines(
                handler: handler,
                visibleRows: visibleRows,
                listHasFocus: listHasFocus,
                rowWidth: rowWidth,
                style: style,
                context: context,
                palette: palette
            )
        }

        return (
            lines: lines,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRowYRanges: visibleRowYRanges,
                visibleRows: visibleRows,
                scrollbarColumn: scrollbarColumn,
                scrollbarHeight: scrollbarHeight
            )
        )
    }

    /// Whether the rows can't all fit in `targetContentHeight` lines — i.e.
    /// whether the list scrolls and shows indicators.
    ///
    /// Exactly the old `totalRowLines > targetContentHeight` test, but it stops
    /// summing the moment the running total exceeds the area instead of first
    /// rendering *every* row. For the common case (rows are at least one line
    /// tall) that short-circuits after ~`targetContentHeight` rows, so a
    /// 2,000-row List in a 40-line area renders ~40 rows here, not 2,000 — and
    /// when the list isn't scrolled those are the very rows about to be shown,
    /// whose buffers ``LazyListRowContent`` memoises (no re-render downstream).
    /// It walks all rows only when their total height genuinely fits the area
    /// (a short list, which is rendered in full anyway).
    private func rowsOverflow(
        _ source: RowSource<SelectionValue>,
        targetContentHeight: Int
    ) -> Bool {
        var totalRowLines = 0
        for index in 0..<source.count {
            totalRowLines += source.row(at: index).buffer.height
            if totalRowLines > targetContentHeight { return true }
        }
        return false
    }

    /// Fetches (or creates) the persistent ``ItemListHandler``
    /// and syncs its per-frame inputs to match the current
    /// rows, selection bindings, focus state, and disabled
    /// state.
    ///
    /// Intentionally does NOT call
    /// ``ItemListHandler/ensureFocusedItemVisible()`` — wheel
    /// scrolling is independent of the focused row (matches
    /// Finder / Explorer / VS Code), and the focus-changing
    /// paths inside the handler already call it themselves.
    private func resolvePopulatedHandler(
        source: RowSource<SelectionValue>,
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext,
        contentHeight: Int,
        overflowing: Bool,
        showsScrollbar: Bool = false
    ) -> ItemListHandler<SelectionValue> {
        // Clamp the offset against the largest possible visible-row
        // count (one indicator, at an end); the exact viewport is
        // finalised in resolveVisibleWindow once the offset is known.
        let provisionalViewport =
            overflowing ? max(1, contentHeight - 1) : contentHeight
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: 0)
        let handlerBox: StateBox<ItemListHandler<SelectionValue>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID,
                itemCount: source.count,
                viewportHeight: provisionalViewport,
                selectionMode: selectionMode,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        handler.itemCount = source.count
        handler.contentHeight = contentHeight
        handler.viewportHeight = provisionalViewport
        handler.canBeFocused = !isDisabled
        // Captured at render so Shift+arrow can accelerate the focus cursor at
        // event time, when the environment is no longer reachable.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.wheelEdgeHold.delayNanos = context.environment.scrollChainingDelay.wheelDelayNanos
        // List rows can be any height (the renderer already windows by real
        // line heights), so the focus-reveal AND offset-clamp arithmetic must
        // accumulate the same heights — otherwise a Down past the fold leaves
        // the focused multi-line row off screen ("selection disappears"), and
        // the tail rows are unreachable. Wired BEFORE the clamp below so this
        // frame's clamp uses this frame's rows. Lazy + memoised: only a
        // viewport's worth of rows is ever queried, so single-line lists pay
        // nothing new and windowed lists stay O(visible).
        handler.rowHeight = { source.row(at: $0).buffer.height }
        // Captured at render for the same reason as the shift multiplier:
        // wheel events arrive when the environment is out of reach.
        handler.scrollGranularity = context.environment.scrollGranularity
        // Mutating the *persistent* scroll position must happen only on the
        // real render pass, never while measuring. A `List` with no explicit
        // height that shares space with a flexible sibling (e.g. a trailing
        // `Spacer`) is measured with the FULL available height — much larger
        // than the height it ends up rendering into — so a measure-pass
        // `clampScrollOffset()` would clamp `scrollOffset` against a viewport
        // (and therefore a `maxOffset`) far smaller than the real one, pulling
        // the offset back every frame. The symptom: the list can't be scrolled
        // (wheel / arrows / Page Down / End) the last screenful to its bottom.
        // The render pass below runs last and clamps with the true viewport, so
        // legitimate clamping (e.g. a filter shrinking the row count) still
        // happens every frame.
        if !context.isMeasuring {
            handler.clampScrollOffset()
            handler.clampTopClip()
            // An "above" indicator that hides exactly one row wastes its
            // line: that line could just show the row. So never rest at
            // offset 1 — snap to 0, where the first row shows with no
            // indicator. Removing the indicator frees a line, so the row
            // that was at the bottom of the viewport is still shown. A
            // scrollbar shows no such indicator line, so it has nothing to
            // save — and the snap would otherwise undo a single up/down-arrow
            // click on the bar (0↔1). Skip it when the bar is shown. Also
            // skip under line granularity with multi-line rows: a wheel step
            // there legitimately RESTS at row 1 (e.g. one three-line tick
            // over three-line rows), and the snap would undo the scroll —
            // making the list unscrollable whenever ticks land row-aligned.
            let lineGranular =
                handler.scrollGranularity == .line
                && (handler.scrollTopClipLines > 0 || source.row(at: 0).buffer.height > 1)
            if overflowing, !showsScrollbar, handler.scrollOffset == 1, !lineGranular {
                handler.scrollOffset = 0
            }
        }

        // Wire up id resolution + the selectable-index set. For an all-content
        // windowed list (the hot path) both are O(1): ids resolve lazily per
        // visible row through `idAt`, and an empty `selectableIndices` already
        // means "every row is selectable" (see ItemListHandler) — so we never
        // materialise a 50k-entry id array or a 50k-index Set per frame. The id
        // reads that remain are O(visible). A heterogeneous row set (Sections,
        // with non-selectable headers/footers) is small, so it builds the
        // explicit maps eagerly as before.
        if source.allContent {
            handler.idAt = { index in
                if case .content(let id) = source.type(at: index) { return id }
                return nil
            }
            handler.itemIDs = []
            handler.selectableIndices = []
        } else {
            var selectableIndices = Set<Int>()
            var itemIDs: [SelectionValue?] = []
            itemIDs.reserveCapacity(source.count)
            for index in 0..<source.count {
                if case .content(let id) = source.type(at: index) {
                    itemIDs.append(id)
                    selectableIndices.insert(index)
                } else {
                    itemIDs.append(nil)
                }
            }
            handler.idAt = nil
            handler.itemIDs = itemIDs
            handler.selectableIndices = selectableIndices
        }
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection
        handler.primaryAction = primaryAction
        return handler
    }

    /// Stitches together the row content with top / bottom
    /// scroll indicators and returns both the rendered lines
    /// and the y-ranges each visible row occupies inside that
    /// list (used by the click hit-test to find the row index
    /// for a given click position).
    private func composeRowLines(
        handler: ItemListHandler<SelectionValue>,
        visibleRows: [(Int, SelectableListRow<SelectionValue>)],
        listHasFocus: Bool,
        rowWidth: Int,
        style: any ListStyle,
        context: RenderContext,
        palette: any Palette
    ) -> (lines: [String], ranges: [VisibleRowRange]) {
        var lines: [String] = []
        var ranges: [VisibleRowRange] = []

        if handler.hasContentAbove || handler.scrollTopClipLines > 0 {
            lines.append(renderScrollIndicator(
                direction: .up,
                count: max(1, handler.rowsAbove),
                width: rowWidth,
                palette: palette
            ))
        }

        var sectionContentIndex = 0
        for (rowIndex, row) in visibleRows {
            if case .header = row.type { sectionContentIndex = 0 }
            let isFocused = handler.isFocused(at: rowIndex) && listHasFocus
            let isSelected = handler.isSelected(at: rowIndex)
            var styledLines = renderRow(
                row: row,
                isFocused: isFocused,
                isSelected: isSelected,
                rowWidth: rowWidth,
                sectionContentIndex: sectionContentIndex,
                style: style,
                context: context,
                palette: palette
            )
            // Line granularity: the top visible row enters partially, its
            // first `clip` lines scrolled off above the viewport.
            if rowIndex == handler.scrollOffset, handler.scrollTopClipLines > 0 {
                styledLines.removeFirst(min(handler.scrollTopClipLines, styledLines.count - 1))
            }
            let yStart = lines.count
            lines.append(contentsOf: styledLines)
            ranges.append((
                rowIndex: rowIndex,
                yStart: yStart,
                height: styledLines.count,
                type: row.type
            ))
            if case .content = row.type { sectionContentIndex += 1 }
        }

        if handler.hasContentBelow {
            lines.append(renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                width: rowWidth,
                palette: palette
            ))
        }
        return (lines, ranges)
    }

    /// The vertical scrollbar cells for a list, one styled single-cell string per
    /// content line. Metrics are in *lines* (the user's spec — a five-line row
    /// scrolls as five units).
    ///
    /// Cost discipline: when every visible row is one line (the common case, and
    /// every windowed mega-list), line == row, so the extent is just the row count
    /// and nothing extra is materialised. Only a list actually showing a taller
    /// row sums the true line heights — and only because a bar is displayed; a
    /// `.hidden` list (the default) never reaches here at all.
    private func listScrollbarCells(
        source: RowSource<SelectionValue>,
        handler: ItemListHandler<SelectionValue>,
        visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        contentHeight: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        let extentLines: Int
        let offsetLines: Int
        if visibleRows.allSatisfy({ $0.row.buffer.height == 1 }) {
            extentLines = source.count
            offsetLines = handler.scrollOffset
        } else {
            // A line-granularity top clip adds its hidden lines to the
            // offset, so the thumb tracks fine wheel steps exactly.
            extentLines = (0..<source.count).reduce(0) { $0 + source.row(at: $1).buffer.height }
            offsetLines =
                (0..<handler.scrollOffset).reduce(0) { $0 + source.row(at: $1).buffer.height }
                + handler.scrollTopClipLines
        }

        return ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: extentLines, viewport: contentHeight, offset: offsetLines,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: ScrollbarColors(
                thumb: palette.foregroundSecondary, track: palette.foregroundQuaternary,
                arrow: palette.foregroundTertiary))
    }

    /// Like ``composeRowLines`` but draws a vertical scrollbar (`bar`, one styled
    /// cell per content line) in the rightmost column instead of the "N more" text
    /// indicators. Each rendered line gets its own bar cell, so a tall row covers
    /// as many bar cells as it is lines tall.
    private func composeScrollbarRowLines(
        visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        handler: ItemListHandler<SelectionValue>,
        listHasFocus: Bool,
        contentRowWidth: Int,
        bar: [String],
        style: any ListStyle,
        context: RenderContext,
        palette: any Palette
    ) -> (lines: [String], ranges: [VisibleRowRange]) {
        let contentHeight = bar.count
        let emptyCell = ANSIRenderer.colorize(" ", background: palette.foregroundQuaternary)
        func barCell(at line: Int) -> String { line < bar.count ? bar[line] : emptyCell }

        var lines: [String] = []
        var ranges: [VisibleRowRange] = []
        var sectionContentIndex = 0
        for (rowIndex, row) in visibleRows {
            if case .header = row.type { sectionContentIndex = 0 }
            let isFocused = handler.isFocused(at: rowIndex) && listHasFocus
            let isSelected = handler.isSelected(at: rowIndex)
            var styledLines = renderRow(
                row: row,
                isFocused: isFocused,
                isSelected: isSelected,
                rowWidth: contentRowWidth,
                sectionContentIndex: sectionContentIndex,
                style: style,
                context: context,
                palette: palette
            )
            // Line granularity: the top visible row enters partially (see
            // composeRowLines).
            if rowIndex == handler.scrollOffset, handler.scrollTopClipLines > 0 {
                styledLines.removeFirst(min(handler.scrollTopClipLines, styledLines.count - 1))
            }
            let yStart = lines.count
            for rowLine in styledLines {
                // An intrinsically over-wide row must not push the bar cell past
                // the interior (where the container clamp would cut the bar off);
                // hard-clip it to the content column, matching the container's
                // own clipping of over-wide rows on the bar-less path.
                let fitted =
                    rowLine.strippedLength > contentRowWidth
                    ? rowLine.ansiAwarePrefix(visibleCount: contentRowWidth)
                    : rowLine
                let pad = max(0, contentRowWidth - fitted.strippedLength)
                lines.append(fitted + String(repeating: " ", count: pad) + barCell(at: lines.count))
            }
            ranges.append((
                rowIndex: rowIndex,
                yStart: yStart,
                height: styledLines.count,
                type: row.type
            ))
            if case .content = row.type { sectionContentIndex += 1 }
        }
        // Fill the area below the last row so the bar spans the full height.
        while lines.count < contentHeight {
            lines.append(String(repeating: " ", count: contentRowWidth) + barCell(at: lines.count))
        }
        return (lines, ranges)
    }

    // MARK: - Mouse handler wiring

    /// Registers the list's container-wide mouse handler and
    /// emits its hit-test region (inserted at the front of the
    /// regions array so interactive children inside rows still
    /// win their clicks — this region is the fallback).
    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        paddingTop: Int
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        // The bordered container places content at y = 1 (top
        // border) plus the configured top padding. The captured
        // row y-ranges are already relative to the content (they
        // include the scroll-indicator's own row when present),
        // so this single inset is the entire translation needed.
        let topInset = 1 + paddingTop

        // The scrollbar's own handler goes in first so the container's later
        // insert(at: 0) pushes it to a higher index — hit-tested ahead of the
        // container (reverse iteration) for its single column. The bar's metrics
        // are in lines while its offset is in rows, so dragging is exact for
        // uniform 1-line rows and proportional for taller rows (arrows/track stay
        // exact). Its own repeat token lets it auto-repeat independently.
        if let barColumn = state.scrollbarColumn, state.scrollbarHeight > 0 {
            let barHandler = ScrollbarRenderer.verticalMouseHandler(
                for: state.handler, length: state.scrollbarHeight,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                behavior: context.environment.scrollbarClickBehavior)
            let barHandlerID = mouseDispatcher.register(barHandler)
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: barColumn, offsetY: topInset,
                    width: 1, height: state.scrollbarHeight, handlerID: barHandlerID),
                at: 0
            )
            ScrollbarRenderer.driveAutoRepeat(
                state: state.handler,
                token: "list-scrollbar-repeat-\(context.identity.path)", context: context)
        }

        let mouseHandlerID = mouseDispatcher.register(
            containerMouseHandler(
                state: state,
                focusManager: focusManager,
                topInset: topInset
            )
        )
        // Insert at index 0 so any interactive child inside a
        // row (Button, TextField, Stepper) still wins the
        // dispatcher's reverse-iteration match. This region is
        // the fallback — it fires only when nothing more
        // specific matched.
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: mouseHandlerID
            ),
            at: 0
        )

        // Rows render into standalone (per-frame memoised) buffers, so their
        // own hit-test regions — per-row `.onMouseEvent`, Buttons and other
        // interactive children — must be carried into the list's buffer
        // explicitly, translated to each row's on-screen position. Without
        // this merge the container fallback above is the ONLY region that
        // ever sees a click, and the "children win" contract is vacuously
        // false. Rows re-render every frame (the row memo lives on the
        // per-frame RowSource), so the handler ids are current. Appended
        // after the container's insert(at: 0) — higher indices, which the
        // dispatcher's reverse iteration matches first.
        let style = context.environment.listStyle
        // Border column (when drawn) + the leading space `renderPlainLine`
        // prefixes to every row line.
        let rowContentX = (style.showsBorder ? 1 : 0) + style.rowPadding.leading + 1
        let topClip = state.handler.scrollTopClipLines
        for (position, visible) in zip(state.visibleRowYRanges, state.visibleRows) {
            // Line granularity: the top row's first `clip` lines are scrolled
            // off above the viewport, so its row-local coordinates shift up
            // by that much. Every other row has no clip.
            let clip = visible.index == state.handler.scrollOffset ? topClip : 0
            for region in visible.row.buffer.hitTestRegions {
                // Rows can be partially visible — the top row clipped above
                // (line granularity), the last row clipped below: intersect
                // each region with the row-local window of lines actually
                // shown, [clip, clip + position.height).
                let start = max(region.offsetY, clip)
                let end = min(region.offsetY + region.height, clip + position.height)
                guard end > start else { continue }
                buffer.hitTestRegions.append(
                    HitTestRegion(
                        offsetX: rowContentX + region.offsetX,
                        offsetY: topInset + position.yStart + (start - clip),
                        width: region.width,
                        height: end - start,
                        handlerID: region.handlerID
                    )
                )
            }

            // Overlay layers need the same explicit carry: a modal/alert
            // presented from row content (or a popover anchored to it) is
            // emitted into the row's standalone buffer and would otherwise
            // never reach the root compositor — an invisible dialog that
            // still grabs focus. Anchored layers translate to the row's
            // on-screen position (`shifted` leaves screen-centred layers
            // untouched); no clipping — floating above the in-flow content
            // is the point of an overlay.
            buffer.overlays.append(
                contentsOf: visible.row.buffer.shiftedOverlays(
                    byX: rowContentX, y: topInset + position.yStart - clip))
        }
    }

    /// Builds the closure that the container-wide hit-test
    /// region invokes. Routes wheel to the handler's scroll
    /// position (never the selection), left-release to row hit-
    /// testing + focus, and rejects everything else.
    private func containerMouseHandler(
        state: PopulatedRenderState,
        focusManager: FocusManager?,
        topInset: Int
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        let rowRanges = state.visibleRowYRanges
        let capturedPrimaryAction = primaryAction
        return { event in
            // Wheel scrolling moves the viewport, NEVER the
            // selection — same model as Finder / Explorer /
            // VS Code; arrow keys handle selection. Routed
            // through the shared ScrollableOffsetState
            // helper so the math lives in one place.
            if captureHandler.handleWheelEvent(event) { return true }

            if event.button == .left {
                guard event.phase == .released else {
                    return event.phase == .pressed
                }
                // Translate event.y → row index by walking the
                // captured y-ranges. Clicks on a row select it
                // and focus the list; clicks on chrome / empty
                // area just focus.
                let yInLines = event.y - topInset
                if let hit = rowRanges.first(where: {
                    yInLines >= $0.yStart && yInLines < $0.yStart + $0.height
                }) {
                    if case .content(let id) = hit.type {
                        // A double-click fires the row's activation ("open");
                        // a single click selects with macOS semantics (plain
                        // = sole selection, shift = range, ctrl/option =
                        // toggle) — see handleClickSelection.
                        if event.clickCount >= 2, let action = capturedPrimaryAction {
                            captureHandler.focusedIndex = hit.rowIndex
                            action(id)
                        } else {
                            captureHandler.handleClickSelection(at: hit.rowIndex, event: event)
                        }
                    }
                }
                focusManager?.focus(id: captureFocusID)
                return true
            }
            return false
        }
    }

    // MARK: - Row Extraction

    private func extractRows(from content: Content, context: RenderContext) -> RowSource<SelectionValue> {
        // Section first (it conforms to both Section- and List-RowExtractor, and
        // its row set — header/content/footer — is small and built eagerly).
        if let section = content as? SectionRowExtractor {
            return .eager(extractSectionRows(from: section, context: context))
        }

        // Windowed path (ForEach): the row count is known in O(1) and each row's
        // id is resolved lazily, so the handler/window touch only ~viewport ids
        // (plus the focused row) instead of all N. A row's content box is still
        // built only when the overflow check or the visible window walks to it.
        // This is the hot path for a large flat List and what makes per-frame
        // cost O(visible), not O(total). Falls through to the eager path when the
        // ids can't be expressed as SelectionValue.
        if let windowed = content as? WindowedListRowExtractor {
            let count = windowed.listRowCount
            // The conformer is id-homogeneous (see WindowedListRowExtractor), so
            // row 0's resolvability decides the whole list: probe it once rather
            // than resolving all N ids up front. An empty list windows trivially.
            if count == 0 || (windowed.listRowID(at: 0) as SelectionValue?) != nil {
                return RowSource(
                    count: count,
                    allContent: true,
                    typeAt: { index in
                        // Force-unwrap is safe: row 0 resolved and the data is
                        // id-homogeneous, so every index resolves as SelectionValue.
                        let id: SelectionValue = windowed.listRowID(at: index)!
                        return .content(id: id)
                    },
                    make: { index in windowed.makeListRowContent(at: index, context: context) })
            }
        }

        // Eager ListRowExtractor (e.g. a ForEach whose ids couldn't all resolve).
        if let extractor = content as? ListRowExtractor {
            let rows: [ListRow<SelectionValue>] = extractor.extractListRows(context: context)
            return .eager(
                rows.map { SelectableListRow(type: .content(id: $0.id), content: $0.content) })
        }

        // ChildInfoProvider (TupleView with multiple children).
        if let provider = content as? ChildInfoProvider {
            return .eager(extractFromChildren(provider: provider, context: context))
        }

        // Fallback: render as a single content row.
        let buffer = TUIkit.renderToBuffer(content, context: context)
        if let zeroID = 0 as? SelectionValue {
            return .eager([SelectableListRow(type: .content(id: zeroID), buffer: buffer)])
        }
        return .eager([])
    }

    /// Extracts rows from a ChildInfoProvider, handling Sections specially.
    private func extractFromChildren(
        provider: ChildInfoProvider,
        context: RenderContext
    ) -> [SelectableListRow<SelectionValue>] {
        var result: [SelectableListRow<SelectionValue>] = []
        let infos = provider.childInfos(context: context)

        for (index, info) in infos.enumerated() {
            guard let buffer = info.buffer else { continue }

            // Try to extract original view for Section detection
            // ChildInfo only has buffer, so we check the provider type
            if let indexID = index as? SelectionValue {
                result.append(SelectableListRow(type: .content(id: indexID), buffer: buffer))
            }
        }

        return result
    }

    /// Extracts typed rows from a Section (header + content + footer).
    private func extractSectionRows(
        from section: SectionRowExtractor,
        context: RenderContext
    ) -> [SelectableListRow<SelectionValue>] {
        var rows: [SelectableListRow<SelectionValue>] = []
        let info = section.extractSectionInfo(context: context)

        // Header (non-selectable)
        if let headerBuffer = info.headerBuffer {
            rows.append(SelectableListRow(type: .header, buffer: headerBuffer))
        }

        // Content rows (selectable)
        if let extractor = section as? ListRowExtractor {
            let contentRows: [ListRow<SelectionValue>] = extractor.extractListRows(context: context)
            for row in contentRows {
                // Thread the lazy box through — don't force `.buffer` / `.badge`.
                rows.append(SelectableListRow(type: .content(id: row.id), content: row.content))
            }
        } else {
            // Fallback: render content as single row (if Section content is not ForEach)
            // Use the content buffer from SectionInfo
            // Note: This row is still selectable but uses index-based ID
            if !info.contentBuffer.lines.isEmpty, let indexID = 0 as? SelectionValue {
                rows.append(SelectableListRow(type: .content(id: indexID), buffer: info.contentBuffer))
            }
        }

        // Footer (non-selectable)
        if let footerBuffer = info.footerBuffer {
            rows.append(SelectableListRow(type: .footer, buffer: footerBuffer))
        }

        return rows
    }

    // MARK: - Visible Row Calculation

    /// Determines which rows are visible, reserving a line for each
    /// scroll indicator that is actually present at the current
    /// offset.
    ///
    /// The reservation is dynamic: at the top or bottom only one
    /// indicator shows, so one more row fits than in the middle
    /// (where both show). This is what keeps the rows-plus-indicators
    /// height equal to ``contentHeight`` everywhere — eliminating the
    /// wasted blank line at the ends that used to bump the "N more
    /// below" indicator one row too high.
    private func resolveVisibleWindow(
        source: RowSource<SelectionValue>,
        handler: ItemListHandler<SelectionValue>,
        contentHeight: Int,
        overflowing: Bool
    ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
        guard overflowing else {
            return calculateVisibleRows(
                source: source, handler: handler, viewportHeight: contentHeight)
        }
        // A line-granularity top clip means the top row is partially hidden,
        // which warrants the "above" indicator just like whole hidden rows.
        let contentAbove = handler.scrollOffset > 0 || handler.scrollTopClipLines > 0
        let aboveLines = contentAbove ? 1 : 0
        // First fill assuming no "below" indicator…
        let withoutBelow = calculateVisibleRows(
            source: source,
            handler: handler,
            viewportHeight: max(1, contentHeight - aboveLines))
        // …then, if rows remain past that window, a "below" indicator
        // is needed, so reserve its line and refill.
        let belowShown = handler.scrollOffset + withoutBelow.count < source.count
        guard belowShown else { return withoutBelow }
        return calculateVisibleRows(
            source: source,
            handler: handler,
            viewportHeight: max(1, contentHeight - aboveLines - 1))
    }

    private func calculateVisibleRows(
        source: RowSource<SelectionValue>,
        handler: ItemListHandler<SelectionValue>,
        viewportHeight: Int
    ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
        var result: [(Int, SelectableListRow<SelectionValue>)] = []
        // A line-granularity top clip hides the first `clip` lines of the top
        // row, freeing that many lines for content further down.
        var linesUsed = -handler.scrollTopClipLines
        var currentIndex = handler.scrollOffset

        // Only these rows are materialised — `source.row(at:)` builds (and
        // renders) the content box on demand and memoises it.
        while currentIndex < source.count && linesUsed < viewportHeight {
            let row = source.row(at: currentIndex)
            let rowHeight = row.buffer.height

            if linesUsed + rowHeight <= viewportHeight {
                result.append((currentIndex, row))
                linesUsed += rowHeight
                currentIndex += 1
            } else {
                result.append((currentIndex, row))
                break
            }
        }

        return result
    }

    // MARK: - Row Rendering

    private func renderRow(
        row: SelectableListRow<SelectionValue>,
        isFocused: Bool,
        isSelected: Bool,
        rowWidth: Int,
        sectionContentIndex: Int,
        style: any ListStyle,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        let backgroundColor = rowBackgroundColor(
            rowType: row.type,
            isFocused: isFocused,
            isSelected: isSelected,
            sectionContentIndex: sectionContentIndex,
            style: style,
            context: context,
            palette: palette
        )

        // Check for badge on the row (only for content rows, on first line only)
        let badge = row.badge
        let shouldRenderBadge = badge != nil && !badge!.isHidden && row.isSelectable

        // Render each line with padding and optional badge
        return row.buffer.lines.enumerated().map { lineIndex, line in
            if shouldRenderBadge && lineIndex == 0 {
                return renderLineWithBadge(
                    line: line,
                    badge: badge!,
                    rowWidth: rowWidth,
                    backgroundColor: backgroundColor,
                    palette: palette
                )
            } else {
                return renderPlainLine(
                    line: line,
                    rowWidth: rowWidth,
                    backgroundColor: backgroundColor
                )
            }
        }
    }

    /// Determines the background color for a row based on its type and visual state.
    private func rowBackgroundColor(
        rowType: ListRowType<SelectionValue>,
        isFocused: Bool,
        isSelected: Bool,
        sectionContentIndex: Int,
        style: any ListStyle,
        context: RenderContext,
        palette: any Palette
    ) -> Color? {
        switch rowType {
        case .header, .footer:
            return nil

        case .content:
            if isFocused && isSelected {
                let dimAccent = palette.accent.opacity(ViewConstants.focusPulseMin)
                return SelectionIndicator.resolve(isFocused: true, context: context)
                    .color(dim: dimAccent, bright: palette.accent.opacity(ViewConstants.focusPulseMax))
            } else if isFocused {
                return palette.focusBackground
            } else if isSelected {
                // Selected row while the list itself doesn't have
                // focus. Controlled by the
                // `unfocusedSelectionVisibility` environment value
                // (default `.automatic` → visible). Setting
                // `.hidden` suppresses the desaturated highlight
                // and falls through to the alternating-row /
                // no-background path — useful for transient lists
                // (pop-up pickers, quick-pick palettes) where the
                // ambient highlight is more noise than signal.
                if context.environment.unfocusedSelectionVisibility == .hidden {
                    return alternatingBackgroundIfAny(
                        sectionContentIndex: sectionContentIndex,
                        style: style,
                        palette: palette
                    )
                }
                return palette.accent.opacity(ViewConstants.selectedBackground)
            } else {
                return alternatingBackgroundIfAny(
                    sectionContentIndex: sectionContentIndex,
                    style: style,
                    palette: palette
                )
            }
        }
    }

    /// Returns the alternating-row tint when this row qualifies
    /// for it, or nil otherwise. Extracted so the unfocused-
    /// selection-hidden path and the unselected-row path can both
    /// fall back to it without duplicating the condition.
    private func alternatingBackgroundIfAny(
        sectionContentIndex: Int,
        style: any ListStyle,
        palette: any Palette
    ) -> Color? {
        if style.alternatingRowColors && sectionContentIndex.isMultiple(of: 2) {
            return palette.accent.opacity(ViewConstants.alternatingRowBackground)
        }
        return nil
    }

    /// Renders a line with a right-aligned badge.
    /// Layout: [1 pad][content][fill padding][badge][1 pad]
    private func renderLineWithBadge(
        line: String,
        badge: BadgeValue,
        rowWidth: Int,
        backgroundColor: Color?,
        palette: any Palette
    ) -> String {
        let lineLength = line.strippedLength
        let badgeText = badge.displayText
        let styledBadge = ANSIRenderer.colorize(badgeText, foreground: palette.foregroundTertiary)

        let badgeWidth = badgeText.strippedLength
        let usedWidth = 1 + lineLength + badgeWidth + 1
        let fillPadding = max(1, rowWidth - usedWidth)
        let paddedLine = " " + line + String(repeating: " ", count: fillPadding) + styledBadge + " "

        return paddedLine.withPersistentBackground(backgroundColor)
    }

    /// Renders a plain line without badge.
    /// Layout: [1 pad][content][right padding]
    private func renderPlainLine(
        line: String,
        rowWidth: Int,
        backgroundColor: Color?
    ) -> String {
        let lineLength = line.strippedLength
        let usedWidth = 1 + lineLength
        let rightPadding = max(1, rowWidth - usedWidth)
        let paddedLine = " " + line + String(repeating: " ", count: rightPadding)

        return paddedLine.withPersistentBackground(backgroundColor)
    }
}

// MARK: - List Content View

/// Simple view that renders pre-computed lines.
struct _ListContentView: View, Renderable {
    let lines: [String]

    var body: Never {
        fatalError("_ListContentView renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: lines)
    }
}
