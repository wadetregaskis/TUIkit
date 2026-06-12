//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore.swift
//
//  Created by LAYERED.work
//  License: MIT

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
    /// Every row's type/id, resolved eagerly (no content built).
    let types: [ListRowType<SelectionValue>]

    /// Builds the deferred content box for a row index.
    private let make: (Int) -> LazyListRowContent

    /// Per-frame memo so a row touched by both the overflow check and the visible
    /// window (or re-read by the compose pass) is built — and rendered — once.
    private var materialized: [Int: SelectableListRow<SelectionValue>] = [:]

    init(types: [ListRowType<SelectionValue>], make: @escaping (Int) -> LazyListRowContent) {
        self.types = types
        self.make = make
    }

    /// Wraps already-built rows (the eager Section / fallback paths).
    static func eager(_ rows: [SelectableListRow<SelectionValue>]) -> RowSource {
        RowSource(types: rows.map(\.type), make: { rows[$0].content })
    }

    var count: Int { types.count }
    var isEmpty: Bool { types.isEmpty }

    /// The fully-formed row at `index`, materialising (and memoising) its content
    /// box on first access. Reading the row's `.buffer` renders it once (cached).
    func row(at index: Int) -> SelectableListRow<SelectionValue> {
        if let existing = materialized[index] { return existing }
        let row = SelectableListRow(type: types[index], content: make(index))
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
    /// Width is reported flexible (and height fixed at the filled height) — the
    /// same shape the render-to-measure fallback reported once the List began
    /// filling — so a parent stack fills around it. Hugging content is opt-in via
    /// `.fixedSize(horizontal:)`, which proposes an unbounded width.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize.flexibleWidth(
            minWidth: proposal.width ?? context.availableWidth,
            height: proposal.height ?? context.availableHeight)
    }

    /// Captures the populated-state values that the mouse-
    /// handler attachment needs from the content rendering
    /// pass. `nil` in the empty-list case.
    private struct PopulatedRenderState {
        let handler: ItemListHandler<SelectionValue>
        let focusID: String
        let visibleRowYRanges: [VisibleRowRange]
    }

    private typealias VisibleRowRange = (
        rowIndex: Int, yStart: Int, height: Int, type: ListRowType<SelectionValue>
    )

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let style = context.environment.listStyle
        let stateStorage = context.environment.stateStorage!

        let source = extractRows(from: content, context: context)

        // Vertical chrome around the scrollable content; reserve
        // only what is actually present.
        let footerHeight = footer != nil ? 2 : 0  // footer line + separator
        let borderOverhead = style.showsBorder ? 2 : 0  // top + bottom border
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
                borderStyle: style.showsBorder ? context.environment.appearance.borderStyle : nil,
                borderColor: style.showsBorder ? palette.border : nil,
                titleColor: nil,
                padding: style.rowPadding,
                showFooterSeparator: showFooterSeparator
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
            // The "−2" accounts for the two border characters.
            targetWidth = max(intrinsicWidth, context.availableWidth - 2)
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
            overflowing: overflowing
        )
        FocusRegistration.register(context: context, handler: handler)
        let listHasFocus = FocusRegistration.isFocused(
            context: context, focusID: persistedFocusID)

        // Reserve a line for each scroll indicator that is actually
        // present at this offset, so the rows plus indicators fill
        // the content area exactly — no wasted blank line at the
        // ends (which used to push the "N more below" indicator one
        // row too high), and no overflow in the middle.
        let visibleRows = resolveVisibleWindow(
            source: source,
            handler: handler,
            contentHeight: targetContentHeight,
            overflowing: overflowing
        )
        // Sync the viewport to the rows actually shown so the
        // handler's indicator predicates match the rendering.
        handler.viewportHeight = max(1, visibleRows.count)

        // Row width — the List is greedy on width (SwiftUI parity): fill the
        // available interior, growing past it only when a row is itself wider
        // than the space offered. Sizing to the widest *visible* row (the old
        // non-explicit path) made the List's box jump width as you scrolled past
        // wider/narrower rows; filling keeps it stable. To hug content instead,
        // a caller uses `.fixedSize(horizontal:)` (which proposes an unbounded
        // width, so the interior collapses to `maxRowWidth`).
        let maxRowWidth = visibleRows.map { $0.row.buffer.width }.max() ?? 0
        let rowWidth = max(maxRowWidth, context.availableWidth - 2)

        let (lines, visibleRowYRanges) = composeRowLines(
            handler: handler,
            visibleRows: visibleRows,
            listHasFocus: listHasFocus,
            rowWidth: rowWidth,
            style: style,
            context: context,
            palette: palette
        )

        return (
            lines: lines,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                visibleRowYRanges: visibleRowYRanges
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
        overflowing: Bool
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
            // An "above" indicator that hides exactly one row wastes its
            // line: that line could just show the row. So never rest at
            // offset 1 — snap to 0, where the first row shows with no
            // indicator. Removing the indicator frees a line, so the row
            // that was at the bottom of the viewport is still shown.
            if overflowing, handler.scrollOffset == 1 {
                handler.scrollOffset = 0
            }
        }

        // Built from the eager `types` — no row content is materialised, so this
        // stays O(total) in cheap id reads while the expensive row buffers remain
        // O(visible).
        var selectableIndices = Set<Int>()
        var itemIDs: [SelectionValue?] = []
        itemIDs.reserveCapacity(source.count)
        for (index, type) in source.types.enumerated() {
            if case .content(let id) = type {
                itemIDs.append(id)
                selectableIndices.insert(index)
            } else {
                itemIDs.append(nil)
            }
        }
        handler.itemIDs = itemIDs
        handler.selectableIndices = selectableIndices
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection
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

        if handler.hasContentAbove {
            lines.append(renderScrollIndicator(
                direction: .up,
                count: handler.rowsAbove,
                width: rowWidth,
                palette: palette
            ))
        }

        var sectionContentIndex = 0
        for (rowIndex, row) in visibleRows {
            if case .header = row.type { sectionContentIndex = 0 }
            let isFocused = handler.isFocused(at: rowIndex) && listHasFocus
            let isSelected = handler.isSelected(at: rowIndex)
            let styledLines = renderRow(
                row: row,
                isFocused: isFocused,
                isSelected: isSelected,
                rowWidth: rowWidth,
                sectionContentIndex: sectionContentIndex,
                style: style,
                context: context,
                palette: palette
            )
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
    }

    /// Builds the closure that the container-wide hit-test
    /// region invokes. Routes wheel to the handler's scroll
    /// position (never the selection), left-release to row hit-
    /// testing + focus, and rejects everything else.
    private func containerMouseHandler(
        state: PopulatedRenderState,
        focusManager: FocusManager,
        topInset: Int
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        let rowRanges = state.visibleRowYRanges
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
                    if case .content = hit.type {
                        captureHandler.focusedIndex = hit.rowIndex
                        captureHandler.toggleSelectionAtFocusedIndex()
                    }
                }
                focusManager.focus(id: captureFocusID)
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

        // Windowed path (ForEach): resolve every row's id cheaply up front, but
        // materialise a row's content box only when the overflow check or the
        // visible window walks to it. This is the hot path for a large flat List
        // and what makes per-frame cost O(visible), not O(total). Falls through
        // to the eager path when the ids can't all be resolved.
        if let windowed = content as? WindowedListRowExtractor,
            let ids = windowed.listRowIDs(context: context) as [SelectionValue]?
        {
            let types = ids.map { ListRowType<SelectionValue>.content(id: $0) }
            return RowSource(types: types) { index in
                windowed.makeListRowContent(at: index, context: context)
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
        let aboveLines = handler.scrollOffset > 0 ? 1 : 0
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
        var linesUsed = 0
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
                return Color.lerp(dimAccent, palette.accent.opacity(ViewConstants.focusPulseMax), phase: context.environment.pulsePhase)
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
