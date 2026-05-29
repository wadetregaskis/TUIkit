//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ListCore.swift
//
//  Created by LAYERED.work
//  License: MIT

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
struct _ListCore<SelectionValue: Hashable & Sendable, Content: View, Footer: View>: View, Renderable {
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

        let rows = extractRows(from: content, context: context)

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
        if rows.isEmpty {
            contentLines = buildEmptyStateLines(context: context)
            renderState = nil
        } else {
            let result = buildPopulatedContent(
                rows: rows,
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
        rows: [SelectableListRow<SelectionValue>],
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        style: any ListStyle,
        targetContentHeight: Int
    ) -> (lines: [String], state: PopulatedRenderState) {
        // Use the full content height when every row fits; only
        // reserve the 2 scroll-indicator lines when the rows
        // genuinely overflow, so a list with room to spare
        // never scrolls unnecessarily.
        let totalRowLines = rows.reduce(0) { $0 + $1.buffer.height }
        let viewportHeight =
            totalRowLines <= targetContentHeight
            ? targetContentHeight
            : max(1, targetContentHeight - 2)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "list",
            propertyIndex: 1  // focusID
        )
        let handler = resolvePopulatedHandler(
            rows: rows,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            viewportHeight: viewportHeight
        )
        FocusRegistration.register(context: context, handler: handler)
        let listHasFocus = FocusRegistration.isFocused(
            context: context, focusID: persistedFocusID)

        let visibleRows = calculateVisibleRows(
            rows: rows, handler: handler, viewportHeight: viewportHeight)

        // Row width — explicit-frame lists fill the available
        // interior; otherwise we shrink to the widest visible row.
        let maxRowWidth = visibleRows.map { $0.row.buffer.width }.max() ?? 0
        let rowWidth: Int
        if context.hasExplicitWidth {
            rowWidth = max(maxRowWidth, context.availableWidth - 2)
        } else {
            rowWidth = maxRowWidth
        }

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
        rows: [SelectableListRow<SelectionValue>],
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext,
        viewportHeight: Int
    ) -> ItemListHandler<SelectionValue> {
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: 0)
        let handlerBox: StateBox<ItemListHandler<SelectionValue>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID,
                itemCount: rows.count,
                viewportHeight: viewportHeight,
                selectionMode: selectionMode,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        handler.itemCount = rows.count
        handler.viewportHeight = viewportHeight
        handler.canBeFocused = !isDisabled
        handler.clampScrollOffset()

        var selectableIndices = Set<Int>()
        var itemIDs: [SelectionValue?] = []
        for (index, row) in rows.enumerated() {
            if let id = row.id {
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
                count: handler.scrollOffset,
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
            let lastVisibleIndex = visibleRows.last?.0 ?? (handler.scrollOffset - 1)
            let rowsBelow = max(0, handler.itemCount - lastVisibleIndex - 1)
            lines.append(renderScrollIndicator(
                direction: .down,
                count: rowsBelow,
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
            switch event.button {
            case .scrollUp:
                // Wheel scrolling moves the viewport, NEVER the
                // selection — same model as Finder / Explorer /
                // VS Code; arrow keys handle selection.
                captureHandler.scroll(by: -ViewConstants.mouseWheelScrollLines)
                return true
            case .scrollDown:
                captureHandler.scroll(by: ViewConstants.mouseWheelScrollLines)
                return true
            case .left:
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
            default:
                return false
            }
        }
    }

    // MARK: - Row Extraction

    private func extractRows(from content: Content, context: RenderContext) -> [SelectableListRow<SelectionValue>] {
        // Check for SectionRowExtractor first (Section view)
        // This must come before ChildInfoProvider because Section conforms to both
        if let section = content as? SectionRowExtractor {
            return extractSectionRows(from: section, context: context)
        }

        // Check for ListRowExtractor (ForEach)
        if let extractor = content as? ListRowExtractor {
            let rows: [ListRow<SelectionValue>] = extractor.extractListRows(context: context)
            return rows.map { SelectableListRow(type: .content(id: $0.id), buffer: $0.buffer, badge: $0.badge) }
        }

        // Check for ChildInfoProvider (handles TupleView with multiple children)
        if let provider = content as? ChildInfoProvider {
            return extractFromChildren(provider: provider, context: context)
        }

        // Fallback: render as single content row
        let buffer = TUIkit.renderToBuffer(content, context: context)
        if let zeroID = 0 as? SelectionValue {
            return [SelectableListRow(type: .content(id: zeroID), buffer: buffer)]
        }

        return []
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
                rows.append(SelectableListRow(type: .content(id: row.id), buffer: row.buffer, badge: row.badge))
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

    private func calculateVisibleRows(
        rows: [SelectableListRow<SelectionValue>],
        handler: ItemListHandler<SelectionValue>,
        viewportHeight: Int
    ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
        var result: [(Int, SelectableListRow<SelectionValue>)] = []
        var linesUsed = 0
        var currentIndex = handler.scrollOffset

        while currentIndex < rows.count && linesUsed < viewportHeight {
            let row = rows[currentIndex]
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
