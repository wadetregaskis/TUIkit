//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

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
        let widest = (0..<source.count).map { index in
            let row = source.row(at: index)
            // A badge is composed OUTSIDE the row's own buffer
            // (`renderLineWithBadge`: content, ≥1 fill, badge), so the hugged
            // width must reserve its cells too — in SwiftUI a badge is an
            // overlay outside layout, but a terminal cell grid has no
            // overlay: sizing a column to "fit" its rows must mean fitting
            // their badges, or the widest row always loses its badge.
            let badgeCells: Int =
                if let badge = row.badge, !badge.isHidden, row.isSelectable {
                    badge.displayText.strippedLength + 1
                } else {
                    0
                }
            return row.buffer.width + badgeCells
        }.max() ?? 0
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
        /// Where this frame was DRAWN from — the handler's raw scroll position
        /// with any absorbed top clip already resolved away
        /// (``ItemListHandler/resolvedWindowOrigin(firstRowHeight:)``). The
        /// click mapping must measure from this, not from the handler, or the
        /// absorbed frame puts every row a line off its hit band.
        let origin: WindowOrigin
        let visibleRowYRanges: [VisibleRowRange]
        /// The rows behind ``visibleRowYRanges``, index-aligned with it (both
        /// are built from the same visible-window walk). Their buffers carry
        /// the rows' own hit-test regions, which `attachMouseHandlers` merges
        /// into the list's buffer.
        let visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)]

        /// The rows' `.dropDestination(for:action:)` insertion action, if any —
        /// what makes this list a landing place for a drag from elsewhere.
        var dropInsertion: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)?
        /// The buffer column of the scrollbar and its line-height, when one is
        /// drawn (`nil` column = no bar). Drives the bar's mouse handler in
        /// `attachMouseHandlers`.
        var scrollbarColumn: Int?
        var scrollbarHeight = 0
    }

    private typealias VisibleRowRange = (
        rowIndex: Int, yStart: Int, height: Int, type: ListRowType<SelectionValue>
    )

    /// The first row of the window and how many of its lines are scrolled off
    /// above it — the one position the whole render path measures from. See
    /// ``ItemListHandler/resolvedWindowOrigin(firstRowHeight:)``.
    private typealias WindowOrigin = (offset: Int, topClip: Int)

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let style = context.environment.listStyle
        let stateStorage = context.environment.stateStorage!

        // Rows beyond the viewport are skipped, not gone: retain their state
        // (see StateStorage.retainSubtree). Render path only, per the
        // measure-side-effect rule.
        if !context.isMeasuring {
            stateStorage.retainSubtree(context.identity)
        }

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
        // A BORDERED container draws the title inside its top border row
        // (`ContainerView.chromeHeight` counts borders and the footer separator
        // and nothing else), so it costs no line of its own — charging one
        // anyway showed a titled list one row fewer than fits, with a stray
        // blank line at the bottom of the slot. Borderless (`.plain`) does
        // render the title as its own row (`renderBorderless`), so there the
        // line is real. `_ListCore`'s own click mapping already agreed: its
        // `topInset` counts the border and the padding, never a title.
        let titleOverhead = (title != nil && !style.showsBorder) ? 1 : 0
        let targetContentHeight = max(
            1,
            context.availableHeight - borderOverhead - titleOverhead - footerHeight
        )

        let contentLines: [String]
        let renderState: PopulatedRenderState?
        if source.isEmpty {
            contentLines = buildEmptyStateLines(context: context)
            // Empty is not inert. The list still occupies its frame, so it is
            // still somewhere a drag can be dropped — and everything that makes
            // that true (the container's hit region, the drop destination, the
            // auto-scroll zone) hangs off this state. Without it, emptying a
            // list made it permanently unfillable: nothing to hit-test, so a
            // drag over it resolved no target and flew home.
            renderState = emptyRenderState(
                source: source, context: context, stateStorage: stateStorage,
                targetContentHeight: targetContentHeight)
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
        handler.publishEscapeClaim(context: context, isFocused: listHasFocus)

        let origin = windowOrigin(
            handler: handler, source: source, showsScrollbar: wantsScrollbar)

        // Reserve a line for each scroll indicator that is actually
        // present at this offset, so the rows plus indicators fill
        // the content area exactly — no wasted blank line at the
        // ends (which used to push the "N more below" indicator one
        // row too high), and no overflow in the middle. With a bar,
        // the whole content area is the viewport (no reservation).
        var visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)]
        // Deliberately not defaulted anywhere below: an implicit default is
        // exactly how these window rules drift apart.
        let lineGranularity = context.environment.scrollGranularity == .line
        if wantsScrollbar {
            visibleRows = calculateVisibleRows(
                source: source, origin: origin, viewportHeight: targetContentHeight,
                lineGranularity: lineGranularity)
        } else {
            visibleRows = resolveVisibleWindow(
                source: source,
                origin: origin,
                contentHeight: targetContentHeight,
                overflowing: overflowing,
                lineGranularity: lineGranularity
            )
        }
        // Sync the viewport to the DATA rows this window covers — BEFORE the
        // reorder decoration rewrites them. The dragged row and the drop slot
        // are drawing, not data: a row in the user's hand is still counted by
        // `itemCount` and is not hidden below, and a slot has no data behind it
        // at all. Counting either makes the indicator predicates disagree with
        // the extent and invent a "1 more row below".
        handler.viewportHeight = max(1, visibleRows.count)
        // A `.dimmed` / `.cursor` drag rewrites the rows here, AFTER the
        // window walk: the drag shows an extra row that is not in the data, so
        // it must not take part in choosing which data rows are visible.
        visibleRows = decorateForReorder(
            visibleRows, handler: handler, context: context, palette: palette)

        let rowWidth = rowWidth(
            source: source, visibleRows: visibleRows, style: style, context: context)

        let lines: [String]
        let visibleRowYRanges: [VisibleRowRange]
        var scrollbarColumn: Int?
        var scrollbarHeight = 0
        if wantsScrollbar {
            let bar = listScrollbarCells(
                source: source,
                origin: origin,
                visibleRows: visibleRows,
                contentHeight: targetContentHeight,
                context: context,
                palette: palette
            )
            let contentRowWidth = max(1, rowWidth - 1)
            (lines, visibleRowYRanges) = composeScrollbarRowLines(
                visibleRows: visibleRows,
                handler: handler,
                origin: origin,
                listHasFocus: listHasFocus,
                contentRowWidth: contentRowWidth,
                bar: bar,
                style: style,
                context: context
            )
            // The bar is the last interior column: border (1) + left padding, then
            // the content, then the bar cell. Matches the `1 + paddingTop` content
            // inset used for click mapping (see attachMouseHandlers).
            scrollbarColumn = 1 + style.rowPadding.leading + contentRowWidth
            scrollbarHeight = bar.count
        } else {
            (lines, visibleRowYRanges) = composeRowLines(
                handler: handler,
                origin: origin,
                visibleRows: visibleRows,
                listHasFocus: listHasFocus,
                rowWidth: rowWidth,
                contentHeight: targetContentHeight,
                style: style,
                context: context
            )
        }

        return (
            lines: lines,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                origin: origin,
                visibleRowYRanges: visibleRowYRanges,
                visibleRows: visibleRows,
                dropInsertion: (source.allContent
                    ? content as? DynamicViewContentActions : nil)?.dropInsertionAction,
                scrollbarColumn: scrollbarColumn,
                scrollbarHeight: scrollbarHeight
            )
        )
    }

    /// The interaction state of a list with no rows: a real handler (its
    /// `itemCount` freshly zeroed, so the stale count from its last populated
    /// frame cannot leak into a drop index), no rows, no bands, and whatever
    /// drop action the content declared.
    ///
    /// Rows are the only thing missing. `publishRowBands` is called with an
    /// empty list, which clears the previous frame's geometry; the drop
    /// destination then resolves index 0 through its own `?? itemCount`
    /// fallback, with no new arithmetic anywhere.
    ///
    /// It registers with the focus system exactly as the populated path does.
    /// An empty list is still a Tab stop, an enclosing `ScrollView` still has
    /// to be able to find it to reveal it — and, the case that bites, a list
    /// the user is *in* when its last row goes away must not take their focus
    /// with it: registration is per frame, so a frame that skips it drops the
    /// control out of the ring and leaves focus nowhere.
    private func emptyRenderState(
        source: RowSource<SelectionValue>,
        context: RenderContext,
        stateStorage: StateStorage,
        targetContentHeight: Int
    ) -> PopulatedRenderState {
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
            overflowing: false
        )
        FocusRegistration.register(context: context, handler: handler)
        let listHasFocus = FocusRegistration.isFocused(
            context: context, focusID: persistedFocusID)
        handler.publishEscapeClaim(context: context, isFocused: listHasFocus)
        return PopulatedRenderState(
            handler: handler,
            focusID: persistedFocusID,
            origin: (0, 0),
            visibleRowYRanges: [],
            visibleRows: [],
            dropInsertion: (source.allContent
                ? content as? DynamicViewContentActions : nil)?.dropInsertionAction
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
        // More rows than target lines is overflow by counting alone — every
        // row renders at least its own line. This matters: the walk below
        // touches rows from the HEAD of the list, and touching a row's
        // `buffer` resolves (renders) it — so a deep-scrolled list resolved
        // ~a viewport of rows it wasn't even showing, every frame, just to
        // answer this predicate (~25% of a megalist frame).
        if source.count > targetContentHeight { return true }
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
        // A scrollbar draws no "N more" indicator line, so the scroll-bound
        // arithmetic must not reserve one (else the bottom over-scrolls, leaving
        // a blank row-height remainder). Threaded from `wantsScrollbar`.
        handler.showsScrollbar = showsScrollbar
        // A List swaps its indicators for the bar: the scrollbar compose path
        // emits no "N more" lines at all.
        handler.drawsScrollIndicators = !showsScrollbar
        handler.viewportHeight = provisionalViewport
        handler.canBeFocused = !isDisabled
        // Captured at render so Shift+arrow can accelerate the focus cursor at
        // event time, when the environment is no longer reachable.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        // The app-customisable key bindings, resolved once here rather than
        // per keystroke (see RowShortcuts.lookup).
        handler.shortcuts = context.environment.rowShortcuts.lookup(
            commandKey: context.environment.commandKey)
        // `.cursor` feedback needs a session to float the row above the frame.
        handler.canFloatDraggedRow = context.environment.dragAndDropSession != nil
        // Captured so a cancel can take the floating preview down itself.
        handler.dragSession = context.environment.dragAndDropSession
        handler.isScrollEnabled = context.environment.isScrollEnabled
        // §1.5: how far past its edges this view may be pushed, re-resolved
        // every frame (a `.viewport`-relative allowance moves with the
        // terminal) and pulling any existing excursion back inside it.
        handler.resolveOverscroll(
            environment: context.environment, contentHeight: contentHeight,
            reservesIndicatorLine: overflowing)
        // Captured at render so a USER wheel scroll can release a bound anchor
        // to `.window` at event time. (The list's ARROW keys move the selection,
        // which the spec shadow-switches to Row, not Window — that needs the
        // selection↔anchor wiring and lands with it.)
        handler.anchorPositionBinding = context.environment.anchorPosition
        handler.declaredAnchorMode = ScrollAnchorMode.resolved(
            defaultScrollAnchor: context.environment.defaultScrollAnchor)
        handler.wheelEdgeHold.delayNanos = context.environment.scrollChainingDelay.clampedNanoseconds
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
        // Same event-time capture: the reveal runs on key events.
        handler.followMargin = context.environment.scrollFollowMargin
        // …and again for a reorder drag, which runs entirely on mouse events.
        handler.reorderFeedback = context.environment.rowReorderFeedback
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
            // Never rest at offset 1 — see `settleRestingOffset`, which both
            // List and Table call so the rule cannot drift between them again.
            handler.settleRestingOffset(
                overflowing: overflowing, showsScrollbar: showsScrollbar,
                firstRowHeight: source.row(at: 0).buffer.height)
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
        // An editable `ForEach` (`.onDelete` / `.onMove`) makes the focused row
        // deletable via the Delete / Backspace key and draggable to reorder.
        // Wired ONLY for the homogeneous all-content list, where a row's focus
        // index equals its data offset — a Section's header / footer rows would
        // shift that mapping, so a Section-nested ForEach isn't exposed here.
        let dynamicActions = source.allContent ? content as? DynamicViewContentActions : nil
        handler.onDelete = dynamicActions?.deleteAction
        handler.onMove = dynamicActions?.moveAction
        // Apply whichever anchor is in effect (§1.1): a `.row` designation pins
        // that row as data changes around it, a `.bottom` edge follows the tail.
        // Render pass only — it mutates the persistent offset — and after the id
        // resolver above so a row key resolves. A no-op for every list with
        // neither `.anchorPosition` nor `defaultScrollAnchor`.
        if !context.isMeasuring {
            handler.applyAnchorHold()
        }
        return handler
    }

    /// Stitches together the row content with top / bottom
    /// scroll indicators and returns both the rendered lines
    /// and the y-ranges each visible row occupies inside that
    /// list (used by the click hit-test to find the row index
    /// for a given click position).
    private func composeRowLines(
        handler: ItemListHandler<SelectionValue>,
        origin: WindowOrigin,
        visibleRows: [(Int, SelectableListRow<SelectionValue>)],
        listHasFocus: Bool,
        rowWidth: Int,
        contentHeight: Int,
        style: any ListStyle,
        context: RenderContext
    ) -> (lines: [String], ranges: [VisibleRowRange]) {
        let palette = context.environment.palette
        // The indicator lines are chrome — they describe where the content sits —
        // so the rows are collected separately and an overscroll slide moves only
        // them (§1.5). `lines` is assembled from the three parts at the end.
        var rowLines: [String] = []
        var ranges: [VisibleRowRange] = []
        var topIndicator: String?
        var bottomIndicator: String?

        // A focused list with no scrollbar pulses its "N more" indicators as
        // its focus cue (in addition to the pulsing cursor row) — the
        // scrollbar-less counterpart to the bar's own pulse.
        let indicatorEmphasis = scrollIndicatorEmphasis(isFocused: listHasFocus, context: context)
        let numberLocale = context.environment.locale

        if origin.offset > 0 || origin.topClip > 0 {
            topIndicator = renderScrollIndicator(
                direction: .up,
                count: max(1, origin.offset),
                unit: .rows,
                width: rowWidth,
                palette: palette,
                emphasis: indicatorEmphasis,
                locale: numberLocale
            )
        }

        // Line granularity fills the content area EXACTLY: the bottom row may
        // be partially clipped (as the top row already can be, via
        // `scrollTopClipLines`), so the list's height never changes with
        // which rows happen to be visible. Row granularity keeps whole rows.
        let indicatorLines =
            (topIndicator == nil ? 0 : 1) + (handler.hasContentBelow ? 1 : 0)
        let rowLineBudget: Int? =
            context.environment.scrollGranularity == .line
            ? max(1, contentHeight - indicatorLines)
            : nil
        var rowLinesEmitted = 0

        var sectionContentIndex = 0
        for (rowIndex, row) in visibleRows {
            if case .header = row.type { sectionContentIndex = 0 }
            let isFocused = handler.isCursorRow(rowIndex) && listHasFocus
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
            // first `clip` lines scrolled off above the viewport. Clipped by
            // the RESOLVED origin, which is also what the window walk, the
            // indicators, the bands and the click mapping measure from.
            if rowIndex == origin.offset, origin.topClip > 0 {
                styledLines.removeFirst(min(origin.topClip, styledLines.count - 1))
            }
            // …and the bottom row leaves partially, clipped at the budget.
            // During a reorder hold the budget clip is deferred to
            // `clipReorderOverrun` below, which knows not to clip THROUGH the
            // slot — this mid-loop clip is blind to it, and when the slot was
            // the last entry (a move to the end) it took away the only thing
            // on screen saying where the rows would land.
            if let rowLineBudget, handler.reorder == nil {
                let remaining = rowLineBudget - rowLinesEmitted
                if remaining <= 0 { break }
                if styledLines.count > remaining {
                    styledLines.removeLast(styledLines.count - remaining)
                }
            }
            let yStart = rowLines.count
            rowLines.append(contentsOf: styledLines)
            rowLinesEmitted += styledLines.count
            ranges.append((
                rowIndex: rowIndex,
                yStart: yStart,
                height: styledLines.count,
                type: row.type
            ))
            if case .content = row.type { sectionContentIndex += 1 }
        }

        // A drag never changes how much is on screen, so a reorder frame's
        // overrun is clipped here, slot-aware, for BOTH granularities (row
        // granularity has no other clip at all — the window fit before the
        // slot was added, so held rows scrolled out of it overflowed the
        // content area by the slot's height).
        if handler.reorder != nil {
            clipReorderOverrun(
                lines: &rowLines, ranges: &ranges,
                budget: rowLineBudget ?? max(1, contentHeight - indicatorLines))
        }

        if handler.hasContentBelow {
            bottomIndicator = renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                unit: .rows,
                width: rowWidth,
                palette: palette,
                emphasis: indicatorEmphasis,
                locale: numberLocale
            )
        }

        // Slide the rows, then wrap the (unmoved) indicators back around them.
        // The ranges are relative to the assembled lines, so they take the
        // slide AND the top indicator's offset.
        let blank = String(repeating: " ", count: max(0, rowWidth))
        let slidRows = handler.overscrollState.slid(rowLines, blank: blank)
        let topOffset = topIndicator == nil ? 0 : 1
        let assembled = [topIndicator].compactMap { $0 } + slidRows
            + [bottomIndicator].compactMap { $0 }
        let moved = slidRanges(ranges, handler: handler, lineCount: slidRows.count)
            .map {
                (rowIndex: $0.rowIndex, yStart: $0.yStart + topOffset, height: $0.height,
                 type: $0.type)
            }
        return (assembled, moved)
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
        origin: WindowOrigin,
        visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        contentHeight: Int,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        let extentLines: Int
        let offsetLines: Int
        if visibleRows.allSatisfy({ $0.row.buffer.height == 1 }) {
            extentLines = source.count
            offsetLines = origin.offset
        } else {
            // A line-granularity top clip adds its hidden lines to the
            // offset, so the thumb tracks fine wheel steps exactly.
            extentLines = (0..<source.count).reduce(0) { $0 + source.row(at: $1).buffer.height }
            offsetLines =
                (0..<origin.offset).reduce(0) { $0 + source.row(at: $1).buffer.height }
                + origin.topClip
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
        origin: WindowOrigin,
        listHasFocus: Bool,
        contentRowWidth: Int,
        bar: [String],
        style: any ListStyle,
        context: RenderContext
    ) -> (lines: [String], ranges: [VisibleRowRange]) {
        let palette = context.environment.palette
        let contentHeight = bar.count
        let emptyCell = ANSIRenderer.colorize(" ", background: palette.foregroundQuaternary)
        func barCell(at line: Int) -> String { line < bar.count ? bar[line] : emptyCell }

        // Content-only row lines. The bar cell is merged in at the END, keyed by
        // absolute line index, so an overscroll slide moves the rows and leaves
        // the bar where it is.
        var lines: [String] = []
        var ranges: [VisibleRowRange] = []
        var sectionContentIndex = 0
        for (rowIndex, row) in visibleRows {
            if case .header = row.type { sectionContentIndex = 0 }
            let isFocused = handler.isCursorRow(rowIndex) && listHasFocus
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
            // composeRowLines)…
            if rowIndex == origin.offset, origin.topClip > 0 {
                styledLines.removeFirst(min(origin.topClip, styledLines.count - 1))
            }
            // …and the bottom row leaves partially: the bar area's height is
            // the hard budget, so the list never grows to fit a whole row.
            // Deferred to the slot-aware `clipReorderOverrun` during a hold —
            // see composeRowLines.
            //
            // Not gated on granularity, unlike the bar-less path: a bar spends
            // no line on indicators, so its height is a hard budget under
            // EITHER granularity — the same `showsBar ||` shape the Table uses.
            // With the whole-row window walk above this can now only fire for a
            // single row taller than the entire content area, where it keeps
            // the emitted lines and their published hit bands agreeing instead
            // of letting the container clamp cut lines the bands still claim.
            if handler.reorder == nil {
                let remaining = contentHeight - lines.count
                if remaining <= 0 { break }
                if styledLines.count > remaining {
                    styledLines.removeLast(styledLines.count - remaining)
                }
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
                lines.append(fitted + String(repeating: " ", count: pad))
            }
            ranges.append((
                rowIndex: rowIndex,
                yStart: yStart,
                height: styledLines.count,
                type: row.type
            ))
            if case .content = row.type { sectionContentIndex += 1 }
        }
        // Slot-aware overrun clip for a reorder hold (see composeRowLines).
        if handler.reorder != nil {
            clipReorderOverrun(lines: &lines, ranges: &ranges, budget: contentHeight)
        }

        // Fill the area below the last row so the bar spans the full height.
        let blank = String(repeating: " ", count: contentRowWidth)
        while lines.count < contentHeight { lines.append(blank) }

        // §1.5: slide the rows within the bar's span, then pair each with its
        // bar cell by absolute line index — the bar itself never moves.
        let slid = handler.overscrollState.slid(lines, blank: blank)
        return (
            slid.enumerated().map { $0.element + barCell(at: $0.offset) },
            slidRanges(ranges, handler: handler, lineCount: slid.count))
    }

    /// Clips a reorder frame's overrun — away from the SLOT, never through
    /// it. The exact bug the Table fixed in bafc8de1, whose List halves were
    /// still open: the ordinary budget clips take lines off the TAIL, and
    /// when the slot is the last entry (the "move to the end" destination)
    /// the tail IS the slot — clipping it took away the only thing on screen
    /// saying where the rows would land, which reads as the selection falling
    /// off the bottom of the list. When the slot ends the frame, the overrun
    /// comes off the FRONT instead (visually: the list scrolled down to keep
    /// the destination in view), and the ranges shift with it.
    private func clipReorderOverrun(
        lines: inout [String], ranges: inout [VisibleRowRange], budget: Int
    ) {
        let overrun = lines.count - max(1, budget)
        guard overrun > 0 else { return }
        if ranges.last?.rowIndex == Self.reorderSlotRowIndex {
            lines.removeFirst(overrun)
            ranges = ranges.compactMap { range in
                let end = range.yStart + range.height - overrun
                guard end > 0 else { return nil }
                let start = max(0, range.yStart - overrun)
                return (
                    rowIndex: range.rowIndex, yStart: start, height: end - start,
                    type: range.type)
            }
        } else {
            lines.removeLast(overrun)
            let cap = lines.count
            ranges = ranges.compactMap { range in
                guard range.yStart < cap else { return nil }
                return (
                    rowIndex: range.rowIndex, yStart: range.yStart,
                    height: min(range.height, cap - range.yStart), type: range.type)
            }
        }
    }

    /// The row ranges after an overscroll slide, dropping any pushed off screen.
    private func slidRanges(
        _ ranges: [VisibleRowRange], handler: ItemListHandler<SelectionValue>, lineCount: Int
    ) -> [VisibleRowRange] {
        guard handler.overscrollState.excursion != 0 else { return ranges }
        return ranges.compactMap { range in
            guard
                let moved = handler.overscrollState.slidRange(
                    yStart: range.yStart, height: range.height, lineCount: lineCount)
            else { return nil }
            return (
                rowIndex: range.rowIndex, yStart: moved.yStart, height: moved.height,
                type: range.type)
        }
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
        // A bordered container places content at y = 1 (below the top border);
        // a borderless (`.plain`) list has NO top border row, so its content
        // starts at y = 0. Add the configured top padding. The captured row
        // y-ranges are already relative to the content (they include the
        // scroll-indicator's own row when present), so this inset is the
        // entire translation needed. (Hardcoding `1` here shifted every
        // borderless click up a row — clicking row 2 selected row 1.)
        let topInset = (context.environment.listStyle.showsBorder ? 1 : 0) + paddingTop

        publishRowBands(state: state)

        // The scrollbar's own handler goes in first so the container's later
        // insert(at: 0) pushes it to a higher index — hit-tested ahead of the
        // container (reverse iteration) for its single column. The bar's metrics
        // are in lines while its offset is in rows, so dragging is exact for
        // uniform 1-line rows and proportional for taller rows (arrows/track stay
        // exact). Its own repeat token lets it auto-repeat independently.
        let showsBorder = context.environment.listStyle.showsBorder
        if let barColumn = state.scrollbarColumn, state.scrollbarHeight > 0 {
            let barHandler = ScrollbarRenderer.verticalMouseHandler(
                for: state.handler, length: state.scrollbarHeight,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                behavior: context.environment.scrollbarClickBehavior)
            let barHandlerID = mouseDispatcher.register(
                ScrollbarRenderer.focusing(
                    barHandler, focusID: state.focusID,
                    focusManager: context.environment.focusManager))
            // A bordered list's bar sits against the right border: widen the
            // bar's region over that border column too — a click there is
            // almost certainly aimed at the bar, not at "select whatever row
            // shares this y" (the handler only reads y, so the extra column
            // costs nothing).
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: barColumn, offsetY: topInset,
                    width: showsBorder ? 2 : 1,
                    height: state.scrollbarHeight, handlerID: barHandlerID),
                at: 0
            )
            ScrollbarRenderer.driveAutoRepeat(
                state: state.handler,
                token: "list-scrollbar-repeat-\(context.identity.path)", context: context)
        }

        // Selection needs a click on the CONTENT columns: the border is
        // chrome, and a click there (however row-aligned its y) must not
        // select — see the x-guard in the handler. Clamped: a degenerate
        // (sub-2-column) list still yields a valid, empty range.
        let borderInset = showsBorder ? 1 : 0
        let contentColumns = borderInset..<max(borderInset, buffer.width - borderInset)
        let mouseHandlerID = mouseDispatcher.register(
            containerMouseHandler(
                state: state,
                focusManager: focusManager,
                dragSession: context.environment.dragAndDropSession,
                topInset: topInset,
                // Where a row's own content starts: past the border, the style's
                // leading padding, and `renderPlainLine`'s 1-cell gutter — the
                // same column the row's hit regions are translated by. A
                // `.cursor` drag measures its grab point from here, so the row
                // rides the cursor on the exact cell that was pressed.
                rowContentLeft: borderInset + context.environment.listStyle.rowPadding.leading + 1,
                contentColumns: contentColumns
            )
        )
        // The rows are a landing place for drags from elsewhere. It borrows the
        // container's region: same rectangle, and the drop target only needs
        // the geometry — clicks still go to the container's own closure.
        registerRowTargets(
            zoneID: mouseHandlerID, state: state, context: context,
            topInset: topInset, contentColumns: contentColumns, insertion: state.dropInsertion)
        // Insert at index 0 so any interactive child inside a
        // row (Button, TextField, Stepper) still wins the
        // dispatcher's reverse-iteration match. This region is
        // the fallback — it fires only when nothing more
        // specific matched.
        // The list's focusID rides on this region: it is how an enclosing
        // ScrollView locates the focused list to scroll it into view
        // (`snapViewportToFocusedControl` scans regions by focusID).
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: mouseHandlerID,
                focusID: state.focusID
            ),
            at: 0
        )

        // A one-row region at the keyboard cursor's on-screen line, stamped
        // with the SAME focusID and inserted ahead of the container region:
        // `snapViewportToFocusedControl` takes the FIRST region matching the
        // focused ID, so an enclosing ScrollView follows the cursor row — not
        // the list's top — as the selection moves through a list taller than
        // the outer viewport, and its indicator-aware fire condition keeps
        // the row from resting hidden under "▲ N more above". At index 0 the
        // dispatcher's reverse iteration never routes a click here before the
        // container region, so reusing its handler is inert.
        if let (position, _) = zip(state.visibleRowYRanges, state.visibleRows)
            .first(where: { $0.1.index == state.handler.focusedIndex })
        {
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: 0,
                    offsetY: topInset + position.yStart,
                    width: buffer.width,
                    height: max(1, position.height),
                    handlerID: mouseHandlerID,
                    focusID: state.focusID
                ),
                at: 0
            )
        }

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
        for (position, visible) in zip(state.visibleRowYRanges, state.visibleRows) {
            // Line granularity: the top row's first `clip` lines are scrolled
            // off above the viewport, so its row-local coordinates shift up
            // by that much. Every other row has no clip. Measured from the
            // RESOLVED origin — the same one the rows were drawn from.
            let clip = visible.index == state.origin.offset ? state.origin.topClip : 0
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
                        handlerID: region.handlerID,
                        focusID: region.focusID
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

    /// Rewrites the visible rows for an in-flight `.dimmed` / `.cursor` reorder.
    ///
    /// The dragged row LEAVES its place: the list closes up behind it and a slot
    /// opens where it would land, holding a faint copy of it under `.dimmed` and
    /// nothing at all under `.cursor`. So the list keeps its length, and what is
    /// on screen is exactly the order a drop would produce — the preview IS the
    /// result, rather than the result plus a leftover.
    ///
    /// What "no slot" means differs by mode, and that is what the two guards
    /// below say. `.dimmed` draws the row only at the slot, so with nowhere to
    /// drop it there is nothing to draw and the list is left untouched.
    /// `.cursor` has the row on the pointer for the whole drag, so it must be
    /// out of the list for the whole drag too — drawn in both places at once it
    /// would read as a duplicate — and the missing gap is what says releasing
    /// here would put it back.
    ///
    /// The slot is typed as a footer, not as content: it carries no id, so
    /// selection ignores it, and it is not a row the keyboard cursor can sit on.
    /// It IS a drop target though — `publishRowBands` gives it a `dropIndex` —
    /// because after every step of the drag the pointer is resting on it.
    private func decorateForReorder(
        _ visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        handler: ItemListHandler<SelectionValue>,
        context: RenderContext,
        palette: any Palette
    ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
        // The overwhelmingly common frame has nothing in hand and no external
        // drag hovering: the decoration is the identity, and building the
        // by-index dictionary plus the drawn-rows walk just to reproduce the
        // input was ~11% of a plain List frame's render (session-list.trace,
        // 2026-07-31). Bail before any of it.
        guard !handler.reorderRemovedRows.isEmpty || handler.externalDropSlot != nil else {
            return visibleRows
        }
        // EVERY row in hand, stacked: they land as one block, so the slot is
        // one gap the size of all of them. Showing only the grabbed row made a
        // multi-row drag look like the rest had been deleted.
        let byIndex = Dictionary(
            visibleRows.map { ($0.index, $0.row) }, uniquingKeysWith: { first, _ in first })
        let held = handler.reorderRemovedRows.compactMap { index in
            byIndex[index].map { (index: index, buffer: $0.buffer) }
        }
        // Within a block, the row the cursor is on stays at full strength while
        // its travelling companions go faint — otherwise the slot's pulse is on
        // every one of them and marks none. See `reorderPrimaryHeldRow`; `nil`
        // for one row and for every mouse drag, which keep the old rendering.
        let primary = handler.reorderPrimaryHeldRow
        var body: FrameBuffer
        switch handler.effectiveReorderFeedback {
        case .dimmed:
            body =
                stacked(held.map { $0.index == primary ? $0.buffer : dimmed($0.buffer) })
                ?? blankRow(like: nil)
        case .cursor, .live: body = blankRow(like: stacked(held.map(\.buffer)))
        }
        // Held rows that have scrolled out of the window were never rendered,
        // so there is no buffer to show for them — but the slot must still be
        // the size of the whole block (the drop moves ALL of it; a Table
        // renders its lines straight from `data` and never has this gap, a
        // List row is an arbitrary view that only exists rendered inside the
        // window). Pad with one blank line per unseen row — their true height
        // is unknowable unrendered, and single-line is the overwhelming case.
        let removedCount = handler.reorderRemovedRows.count
        if body.height < removedCount {
            let width = max(1, body.width)
            body = FrameBuffer(
                lines: body.lines
                    + Array(
                        repeating: String(repeating: " ", count: width),
                        count: removedCount - body.height))
        }
        // A keyboard move has no pointer to say where the row is, so the slot
        // says it: the row you are steering is emphasised, not a gap. Carried as
        // a background the ROW renderer paints — baked into the buffer it began
        // one cell late, because the selection gutter is added around the
        // buffer, leaving the slot's first cell at the terminal default.
        let heldBackground = heldSlotBackground(
            handler: handler, context: context, palette: palette)
        // Which rows to draw, and where the slot goes among them, is the shared
        // arithmetic — `Table` asks the same question of the same handler.
        return handler.reorderDrawnRows(visibleRows.map(\.index)).compactMap { drawn in
            switch drawn {
            case .row(let index):
                return byIndex[index].map { (index: index, row: $0) }
            case .slot:
                var slot = SelectableListRow<SelectionValue>(type: .footer, buffer: body)
                slot.backgroundOverride = heldBackground
                return (Self.reorderSlotRowIndex, slot)
            }
        }
    }

    /// The colour that marks the slot as the row you are steering — the same
    /// pulse a focused, selected row uses, so "in hand" reads as emphasis
    /// rather than as a hole in the list. Only for a keyboard move: a mouse
    /// drag has the pointer itself to say where the row is.
    private func heldSlotBackground(
        handler: ItemListHandler<SelectionValue>, context: RenderContext, palette: any Palette
    ) -> Color? {
        guard handler.isKeyboardMove else { return nil }
        return SelectionIndicator.resolve(isFocused: true, context: context)
            .color(
                dim: palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background),
                bright: palette.accent.opacity(
                    ViewConstants.focusPulseMax, over: palette.background))
    }

    /// The same buffer with every line drawn faint — `.dimmed`'s preview of the
    /// row, shown at the slot it would land in.
    ///
    /// Persistent, not a bare wrapper: a row of several styled runs carries a
    /// reset per run, and each one would otherwise end the dim early.
    private func dimmed(_ buffer: FrameBuffer) -> FrameBuffer {
        FrameBuffer(lines: buffer.lines.map { ANSIRenderer.applyPersistentDim($0) })
    }

    /// The rows in hand as one buffer, in data order — what travels together,
    /// and so what the slot has to make room for. `nil` for no rows at all (an
    /// external drag hovering, which has no rows of ours to show).
    private func stacked(_ buffers: [FrameBuffer]) -> FrameBuffer? {
        guard !buffers.isEmpty else { return nil }
        return FrameBuffer(lines: buffers.flatMap(\.lines))
    }

    /// A gap the size of the dragged rows — `.cursor`'s "they land here".
    private func blankRow(like buffer: FrameBuffer?) -> FrameBuffer {
        let height = max(1, buffer?.height ?? 1)
        let width = max(1, buffer?.width ?? 1)
        return FrameBuffer(
            lines: Array(repeating: String(repeating: " ", count: width), count: height))
    }

    /// Hands this frame's row geometry to the handler for the reorder drag to
    /// hit-test against.
    ///
    /// It has to come from the handler rather than the mouse closure's captured
    /// copy: a ``RowReorderFeedback/live`` drag reorders the rows underneath the
    /// cursor, so press-frame bands would describe an order that no longer
    /// exists (and a wheel tick can scroll them out from under any mode).
    private func publishRowBands(state: PopulatedRenderState) {
        typealias Handler = ItemListHandler<SelectionValue>
        state.handler.publishRowBands(state.visibleRowYRanges.map { range in
            let entry: Handler.DrawnBand.Content
            if case .content = range.type {
                entry = .row(range.rowIndex)
            } else if range.rowIndex == Self.reorderSlotRowIndex {
                entry = .slot
            } else {
                entry = .chrome(rowIndex: range.rowIndex)
            }
            return Handler.DrawnBand(entry: entry, yStart: range.yStart, height: range.height)
        })
    }

    /// The sentinel row index the reorder drop slot is decorated with — it has
    /// no data behind it, so it cannot carry a real offset. Shared with `Table`.
    private static var reorderSlotRowIndex: Int {
        ItemListHandler<SelectionValue>.reorderSlotRowIndex
    }

    /// Registers everything this frame's rows can receive: a reorder of their
    /// own, and a drop from elsewhere.
    ///
    /// Both borrow the container's region — same rectangle, and both only need
    /// the geometry; clicks still go to the container's own closure. Neither is
    /// conditional on `isScrollEnabled` (the auto-scroll zone is): a drop is not
    /// a scroll, and a list that did not register is one a gesture cannot land
    /// in.
    ///
    /// The drop destination reports WHERE — the
    /// `ForEach.dropDestination(for:action:)` half of the drag-and-drop story.
    /// While a compatible drag hovers, the pointer's row becomes a landing slot
    /// (the same gap a `.cursor` reorder opens, drawn by the same code). On
    /// release the app is told the index it was pointing at.
    private func registerRowTargets(
        zoneID: HitTestRegion.HandlerID,
        state: PopulatedRenderState,
        context: RenderContext,
        topInset: Int,
        contentColumns: Range<Int>,
        insertion: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)?
    ) {
        let handler = state.handler
        // A drag hovering near an edge scrolls the rows to reveal an off-screen
        // drop target. Auto-scroll IS a scroll, so `.scrollDisabled` withholds
        // this one — unlike the two registrations below it.
        if context.environment.isScrollEnabled {
            context.environment.dragAndDropSession?.registerAutoScrollZone(
                DragAndDropSession.AutoScrollZone(
                    handlerID: zoneID, vertical: handler, horizontal: nil,
                    delayNanos: context.environment.dragAutoScrollDelay.clampedNanoseconds,
                    // A title sits above the rows, and a footer (with its
                    // separator) below them — chrome the rows never occupy. Left
                    // in, they eat the hot margin at that edge: a footered list
                    // only scrolled downward once the cursor was over the footer,
                    // the same defect a Table's header caused at the top.
                    topInset: title != nil ? 1 : 0,
                    bottomInset: footer != nil ? 2 : 0,
                    shiftStep: context.environment.shiftStepMultiplier))
        }
        if handler.onMove != nil {
            context.environment.dragAndDropSession?.registerReorderHost(
                DragAndDropSession.ReorderHost(
                    focusID: state.focusID, handlerID: zoneID, topInset: topInset,
                    contentColumns: contentColumns, handler: handler))
        }
        guard let insertion, let session = context.environment.dragAndDropSession else {
            handler.externalDropSlot = nil
            return
        }
        session.registerTarget(
            DragAndDropSession.Target(
                handlerID: zoneID,
                accepts: insertion.accepts,
                perform: { payload, _ in
                    let slot = handler.externalDropSlot ?? handler.itemCount
                    handler.externalDropSlot = nil
                    insertion.perform(slot, [payload])
                    return true
                },
                setTargeted: { targeted in
                    if !targeted { handler.externalDropSlot = nil }
                },
                hovering: { _, y in
                    // The band under the pointer names the row it would land
                    // BEFORE; past the last row it appends.
                    let contentY = y - topInset
                    // Clamped: a list that shrank under the pointer must not
                    // strand the slot past its own end.
                    let slot = handler.dropTarget(atContentY: contentY) ?? handler.itemCount
                    handler.externalDropSlot = min(max(0, slot), handler.itemCount)
                }))
    }

    /// Builds the closure that the container-wide hit-test
    /// region invokes. Routes wheel to the handler's scroll
    /// position (never the selection), left-release to row hit-
    /// testing + focus, and rejects everything else.
    private func containerMouseHandler(
        state: PopulatedRenderState,
        focusManager: FocusManager?,
        dragSession: DragAndDropSession?,
        topInset: Int,
        rowContentLeft: Int,
        contentColumns: Range<Int>
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        let rowRanges = state.visibleRowYRanges
        let capturedPrimaryAction = primaryAction
        let capturedRows = state.visibleRows
        // Where inside the grabbed row the press landed — the cell a `.cursor`
        // drag keeps under the pointer. Held in the closure because the closure
        // IS the gesture: the dispatcher captures it at press and routes the
        // whole drag back here, however many renders intervene.
        let grab = RowReorderGrabPoint()
        return { event in
            // Wheel scrolling moves the viewport, NEVER the
            // selection — same model as Finder / Explorer /
            // VS Code; arrow keys handle selection. Routed
            // through the shared ScrollableOffsetState
            // helper so the math lives in one place.
            if captureHandler.handleWheelEvent(event) { return true }

            if event.button == .left {
                // Row at the cursor (content columns only), from the press-frame
                // bands. Those are exact for the CLICK path — a press and its
                // release describe one unchanging layout — and it is the only
                // path that needs a row's type, and so its selection id. The
                // reorder path deliberately reads the handler's freshly
                // published bands instead: `.live` feedback moves the rows out
                // from under this captured copy as the drag goes.
                func rowAt(y: Int) -> (rowIndex: Int, type: ListRowType<SelectionValue>)? {
                    let yInLines = y - topInset
                    guard contentColumns.contains(event.x),
                        let hit = rowRanges.first(where: {
                            yInLines >= $0.yStart && yInLines < $0.yStart + $0.height
                        })
                    else { return nil }
                    return (hit.rowIndex, hit.type)
                }

                /// The drag's position in the handler's content-line space, or
                /// `nil` once the cursor leaves the content columns — which
                /// holds the current drop target rather than snapping it
                /// somewhere the user isn't pointing.
                var dragContentY: Int? {
                    contentColumns.contains(event.x) ? event.y - topInset : nil
                }

                switch event.phase {
                case .pressed:
                    // Pick up the row for a possible reorder (only when the
                    // ForEach is reorderable). Claim the press either way so the
                    // matching drag / release routes back here.
                    if captureHandler.onMove != nil, let hit = rowAt(y: event.y),
                        case .content = hit.type
                    {
                        captureHandler.beginReorder(grabbing: hit.rowIndex)
                        // Which control the gesture belongs to is the session's
                        // to know from here on: every event after this one is
                        // answered by whichever list is on screen under that
                        // focus identity, not by the one this closure captured.
                        dragSession?.beginReorder(
                            focusID: captureFocusID, handler: captureHandler)
                        // Focus follows the gesture, so the keyboard reaches
                        // this list for the length of it — that is what lets the
                        // navigators scroll a list that was not focused before
                        // the drag began.
                        focusManager?.focus(id: captureFocusID)
                        let band = captureHandler.visibleRowBands.first { $0.rowIndex == hit.rowIndex }
                        grab.x = max(0, event.x - rowContentLeft)
                        grab.y = max(0, event.y - topInset - (band?.yStart ?? 0))
                    }
                    return true

                case .dragged:
                    // Edge auto-scroll applies to reordering too, and the two
                    // feedback modes that open no drag session (`.live`,
                    // `.dimmed`) have to say so explicitly. Armed on the first
                    // MOTION rather than at the press: arming a motionless
                    // long-press near an edge started scrolling the list out
                    // from under a click once the dwell elapsed, with nothing
                    // in hand. Gated on the grab actually having begun — this
                    // closure claims every press, including ones that missed
                    // the reorderable rows.
                    dragSession?.armReorderAutoScrollOnMotion(owner: captureHandler)
                    // Any motion during a grab is a reorder, not a click. What
                    // that looks like is the feedback mode's business — and
                    // `.cursor`'s business reaches outside the list: its row is
                    // carried on the pointer, above every other view, which only
                    // the drag session can draw.
                    // Tracked through the session, which resolves the gesture
                    // against the list rendering NOW and localises the cursor
                    // by that list's rectangle — the captured coordinates
                    // describe the press frame, which is a different place the
                    // moment anything moves. Without a session (a headless
                    // harness) there is only ever one list, so the captured
                    // handler and coordinates are the same answer.
                    let held = dragSession?.reorderHandler ?? captureHandler
                    let wasActive = held.isReordering
                    if let dragSession {
                        dragSession.trackReorder()
                    } else {
                        captureHandler.dragReorder(toContentY: dragContentY)
                    }
                    let current = dragSession?.reorderHandler ?? captureHandler
                    let floating = current.reorderFloatingRows
                    if let dragSession, !floating.isEmpty {
                        let carried = floating.compactMap { index in
                            capturedRows.first { $0.index == index }?.row.buffer
                        }
                        if !wasActive, !carried.isEmpty {
                            // Hand the rows' own buffers to the session, which
                            // floats them at the cursor above everything else.
                            // Their hit regions go — a copy of a row riding the
                            // pointer must not also be clickable.
                            var preview = FrameBuffer(lines: carried.flatMap(\.lines))
                            preview.hitTestRegions = []
                            // The whole block travels, so the grab point moves
                            // down it by however much of the block was above the
                            // row the pointer took hold of — otherwise a block
                            // grabbed by its last row hangs from its first.
                            let above = current.reorderHeldRowsAboveGrab.reduce(0) { sum, index in
                                sum + (capturedRows.first { $0.index == index }?.row.buffer.height ?? 1)
                            }
                            // `begin` trims the preview's padding and clamps
                            // the grab point into what survives, so a press
                            // past the end of a short row still anchors the
                            // floating copy under the pointer.
                            dragSession.begin(
                                payload: RowReorderPayload(), preview: preview,
                                grabX: grab.x, grabY: grab.y + above)
                        } else {
                            // …and advance it on every later movement. `begin`
                            // samples the cursor once; only `dragMoved` tracks
                            // it, and a reorder drag reaches this closure rather
                            // than the `.draggable` modifier that normally calls
                            // it — which is why the row once sat at the position
                            // the drag began for the whole gesture.
                            dragSession.dragMoved()
                        }
                    }
                    return true

                case .released:
                    // Whatever this turns out to be — a drop, or a click that
                    // never moved — the gesture is over, so let go of the edge
                    // auto-scroll. (`end()` below only runs for a real drop.)
                    dragSession?.disarmAutoScroll()
                    // A cancel already put the rows back and ended the drag; the
                    // release that follows is the tail of a cancelled gesture,
                    // not a click on whatever is under the pointer. The SESSION
                    // is asked first: after a page round-trip the handler latch
                    // sits on the adopted replacement, which the fallback below
                    // is not (see `DragAndDropSession.cancelReorder`).
                    if dragSession?.consumeReorderCancellation() == true { return true }
                    let releasing = dragSession?.reorderHandler ?? captureHandler
                    if releasing.reorderCancelled {
                        releasing.reorderCancelled = false
                        return true
                    }
                    // A reorder drop, if this gesture was one. `.live` has
                    // already moved the rows; the other modes move them exactly
                    // there. Committed through the session for the same reason
                    // the drag is tracked through it — and it is the same shape
                    // as `performDrop`, deliberately.
                    if dragSession?.performReorderDrop()
                        ?? captureHandler.dropReorder(atContentY: dragContentY)
                    {
                        focusManager?.focus(id: captureFocusID)
                        return true
                    }

                    // Not a reorder — the original click / selection path.
                    // Translate event.y → row index by walking the captured
                    // y-ranges. Clicks on a row's CONTENT columns select it and
                    // focus the list; clicks on chrome — the border columns,
                    // empty area — just focus (the border shares a y with some
                    // row, but nobody clicking a frame means "select that row").
                    if let hit = rowAt(y: event.y), case .content(let id) = hit.type {
                        // A double-click fires the row's activation ("open"); a
                        // single click selects with macOS semantics (plain =
                        // sole selection, shift = range, ctrl/option = toggle).
                        if event.clickCount >= 2, let action = capturedPrimaryAction {
                            captureHandler.focusedIndex = hit.rowIndex
                            action(id)
                        } else {
                            captureHandler.handleClickSelection(at: hit.rowIndex, event: event)
                        }
                    }
                    focusManager?.focus(id: captureFocusID)
                    return true

                default:
                    return false
                }
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

        // ChildViewProvider (TupleView with multiple children). The *view*
        // provider, not the buffer-only ChildInfoProvider: each row's original
        // view is needed to peel off its `.badge(_:)`, and a `ForEach` spliced
        // between static rows only flattens on this path.
        if let provider = content as? ChildViewProvider {
            return .eager(extractFromChildren(provider: provider, context: context))
        }

        // Fallback: render as a single content row, carrying its badge
        // (`List { Text("Notifications").badge(5) }`).
        let badge = extractBadgeValue(from: content)
        let buffer = TUIkit.renderToBuffer(content, context: context)
        if let zeroID = 0 as? SelectionValue {
            return .eager([
                SelectableListRow(
                    type: .content(id: zeroID),
                    content: LazyListRowContent(buffer: buffer, badge: badge))
            ])
        }
        return .eager([])
    }

    /// Extracts one row per flattened child (TupleView content), each carrying
    /// the badge of its `.badge(_:)` wrapper, if any.
    private func extractFromChildren(
        provider: ChildViewProvider,
        context: RenderContext
    ) -> [SelectableListRow<SelectionValue>] {
        var result: [SelectableListRow<SelectionValue>] = []

        for child in provider.childViews(context: context) where !child.isSpacer {
            guard let indexID = result.count as? SelectionValue else { continue }
            let badge = extractBadgeValue(from: child.wrappedView)
            let buffer = child.render(
                width: context.availableWidth, height: context.availableHeight, context: context)
            result.append(
                SelectableListRow(
                    type: .content(id: indexID),
                    content: LazyListRowContent(buffer: buffer, badge: badge)))
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
    /// Where this frame is DRAWN from. Resolved once and threaded through
    /// every consumer — the window walk, the indicators, the row clip, the
    /// published bands and the click mapping — because a renderer that draws
    /// from the absorbed origin while the hit test measures from the raw one
    /// puts every row a line off its band (exactly how the `Table` broke
    /// before it did the same).
    ///
    /// A scrollbar spends no indicator line, so there is nothing to absorb:
    /// that path draws from the handler's raw position.
    private func windowOrigin(
        handler: ItemListHandler<SelectionValue>,
        source: RowSource<SelectionValue>,
        showsScrollbar: Bool
    ) -> WindowOrigin {
        guard !showsScrollbar else { return (handler.scrollOffset, handler.scrollTopClipLines) }
        return handler.resolvedWindowOrigin(firstRowHeight: source.row(at: 0).buffer.height)
    }

    /// The width the rows are laid out at. The List is greedy on width (SwiftUI
    /// parity): fill the available interior, growing past it only when a row is
    /// itself wider than the space offered. Sizing to the widest *visible* row
    /// (the old non-explicit path) made the List's box jump width as you
    /// scrolled past wider/narrower rows; filling keeps it stable.
    ///
    /// `.fixedSize(horizontal:)` instead hugs content: the widest of ALL rows
    /// (not just the visible ones — that's what keeps it stable), so the box is
    /// content-sized and constant.
    private func rowWidth(
        source: RowSource<SelectionValue>,
        visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        style: any ListStyle,
        context: RenderContext
    ) -> Int {
        if context.environment.fixedSizeWidth {
            return (0..<source.count).map { source.row(at: $0).buffer.width }.max() ?? 0
        }
        // Fill the interior: full available width when borderless (`.plain`),
        // minus the two border columns when bordered.
        let maxRowWidth = visibleRows.map { $0.row.buffer.width }.max() ?? 0
        let borderOverhead = style.showsBorder ? 2 : 0
        return max(maxRowWidth, context.availableWidth - borderOverhead)
    }

    private func resolveVisibleWindow(
        source: RowSource<SelectionValue>,
        origin: WindowOrigin,
        contentHeight: Int,
        overflowing: Bool,
        lineGranularity: Bool
    ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
        guard overflowing else {
            return calculateVisibleRows(
                source: source, origin: origin, viewportHeight: contentHeight,
                lineGranularity: lineGranularity)
        }
        // A line-granularity top clip means the top row is partially hidden,
        // which warrants the "above" indicator just like whole hidden rows.
        let contentAbove = origin.offset > 0 || origin.topClip > 0
        let aboveLines = contentAbove ? 1 : 0
        // First fill assuming no "below" indicator…
        let withoutBelow = calculateVisibleRows(
            source: source,
            origin: origin,
            viewportHeight: max(1, contentHeight - aboveLines),
            lineGranularity: lineGranularity)
        // …then, if rows remain past that window, a "below" indicator
        // is needed, so reserve its line and refill.
        let belowShown = origin.offset + withoutBelow.count < source.count
        guard belowShown else { return withoutBelow }
        return calculateVisibleRows(
            source: source,
            origin: origin,
            viewportHeight: max(1, contentHeight - aboveLines - 1),
            lineGranularity: lineGranularity)
    }

    /// - Parameter lineGranularity: Whether the viewport may end mid-row. See
    ///   the straddle branch below — this is the whole reason the flag is
    ///   threaded down here rather than read from the environment at the point
    ///   of use, so every window walk answers it the same way.
    private func calculateVisibleRows(
        source: RowSource<SelectionValue>,
        origin: WindowOrigin,
        viewportHeight: Int,
        lineGranularity: Bool
    ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
        var result: [(Int, SelectableListRow<SelectionValue>)] = []
        // A line-granularity top clip hides the first `clip` lines of the top
        // row, freeing that many lines for content further down.
        var linesUsed = -origin.topClip
        var currentIndex = origin.offset

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
                // The row that straddles the remaining budget. Line granularity
                // fills the viewport EXACTLY — the row enters and the renderer
                // clips its tail. Row granularity promises WHOLE rows, so it
                // stays out and waits for the next screenful; the shortfall is
                // padded downstream. `Table.rowWindow` has always had this rule
                // (its `lineGranularity && used < budget` test); the List never
                // learned it, and its compose paths tried to undo the over-emit
                // with a budget clip that is itself gated on `.line` — so under
                // `.row` nothing trimmed it and the container's blind bottom
                // clamp ate whatever was last: the "▼ N more below" indicator,
                // or the tail of the bottom row on the scrollbar path.
                //
                // A window is never empty, though: a first row taller than the
                // whole viewport still enters (clipped), or nothing would draw.
                if lineGranularity || result.isEmpty {
                    result.append((currentIndex, row))
                }
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
        let backgroundColor = row.backgroundOverride ?? rowBackgroundColor(
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
                let dimAccent = palette.accent.opacity(
                    ViewConstants.focusPulseMin, over: palette.background)
                return SelectionIndicator.resolve(isFocused: true, context: context)
                    .color(
                        dim: dimAccent,
                        bright: palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background))
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
                return palette.accent.opacity(ViewConstants.selectedBackground, over: palette.background)
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
            return palette.accent.opacity(ViewConstants.alternatingRowBackground, over: palette.background)
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
        let badgeText = badge.displayText
        let styledBadge = ANSIRenderer.colorize(badgeText, foreground: palette.foregroundTertiary)
        let badgeWidth = badgeText.strippedLength

        // When the row is too narrow for both, the CONTENT truncates and the
        // badge survives (as in SwiftUI, where the label truncates first) —
        // overflowing instead put the badge in the cells the container
        // clips, silently hiding it.
        let contentBudget = rowWidth - badgeWidth - 3
        let fittedLine =
            line.strippedLength > contentBudget
            ? line.truncatedToWidth(max(1, contentBudget)) : line

        let usedWidth = 1 + fittedLine.strippedLength + badgeWidth + 1
        let fillPadding = max(1, rowWidth - usedWidth)
        let paddedLine =
            " " + fittedLine + String(repeating: " ", count: fillPadding) + styledBadge + " "

        return terminatedBackground(paddedLine, backgroundColor)
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

        return terminatedBackground(paddedLine, backgroundColor)
    }

    /// Applies `backgroundColor` as a persistent row background and TERMINATES
    /// it with a reset at the row's right edge.
    ///
    /// The reset matters: `withPersistentBackground` leaves the background
    /// active at the end of the string, and a borderless list has no right
    /// border to cap it — so a selected row's highlight bled rightward into
    /// whatever was composited beside the list (in the styles demo, across
    /// the whole screen / into the neighbouring list's border). A bordered
    /// list's own right border happened to reset it, masking the bug there.
    /// Matches the self-contained pattern `BackgroundModifier` already uses.
    private func terminatedBackground(_ line: String, _ backgroundColor: Color?) -> String {
        guard backgroundColor != nil else { return line }
        return line.withPersistentBackground(backgroundColor) + ANSIRenderer.reset
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
