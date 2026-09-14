//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewWidths.swift
//
//  How ``NavigationSplitView`` decides how wide each column is: the
//  style-derived proportions, the size-to-fit content hug, the widths the user
//  has dragged or keyed, and the `.navigationSplitViewColumnWidth(…)` request a
//  column publishes from inside itself. Split out of `NavigationSplitView.swift`
//  because the two together outgrew the file-length budget — the view, its
//  rendering, and the divider stay there; everything that decides a width lives
//  here.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Column Measurement

/// What one column contributes to the width calculation.
private struct ColumnMeasurement {
    /// The column's hugged content size — what the size-to-fit style lays out
    /// from. Zero for a column that wasn't measured (see
    /// ``_NavigationSplitViewCore/measureColumns(visibleColumns:includingTrailing:context:)``).
    var size = ViewSize(width: 0, height: 0)

    /// The width the column asked for with `.navigationSplitViewColumnWidth(…)`,
    /// or `nil` if it asked for nothing.
    var request: NavigationSplitViewColumnWidth?
}

// MARK: - Column Widths

extension _NavigationSplitViewCore {
    /// The width of every visible column for this frame, in column order.
    ///
    /// The single entry point the render uses, so the two width models — fit the
    /// content from the left, or divide the width by the style's proportions —
    /// share one measurement of the columns and one reading of what each column
    /// asked for.
    func columnWidths(
        visibleColumns: [NavigationSplitViewColumn],
        style: any NavigationSplitViewStyle,
        context: RenderContext,
        widths: SplitViewWidths?,
        writeBack: Bool
    ) -> [Int] {
        let measured = measureColumns(
            visibleColumns: visibleColumns, includingTrailing: style.sizesToFit, context: context)
        return style.sizesToFit
            ? sizeToFitColumnWidths(
                visibleColumns: visibleColumns, availableWidth: context.availableWidth,
                measured: measured, widths: widths, writeBack: writeBack)
            : calculateColumnWidths(
                visibleColumns: visibleColumns, style: style,
                availableWidth: context.availableWidth, measured: measured,
                widths: widths, writeBack: writeBack)
    }

    /// Measures each visible column once for this frame: its hugged content size
    /// and the ``NavigationSplitViewColumnWidth`` it publishes.
    ///
    /// The request is read by MEASURING the column, not by looking at its type:
    /// `.navigationSplitViewColumnWidth(…)` is a *preference*, so it may sit
    /// anywhere inside the column — under a `.padding()`, on one row of a
    /// `List` — and travels up from wherever it was set. Pushing a preference
    /// scope around the measurement collects just this column's, and popping
    /// merges it onward the way every other collector does (``NavigationStack``
    /// reads its titles the same way). It has to be a measure rather than a look
    /// at the rendered buffer because the column must be asked BEFORE its width
    /// is chosen — it is rendered into that width.
    ///
    /// `includingTrailing` is false under the proportional styles: the trailing
    /// column absorbs whatever the leading ones leave, so neither its content
    /// width nor its request can move the layout, and measuring it (usually the
    /// heaviest column, the detail) would be per-frame work with nothing to show
    /// for it. The result always has one entry per visible column regardless.
    private func measureColumns(
        visibleColumns: [NavigationSplitViewColumn],
        includingTrailing: Bool,
        context: RenderContext
    ) -> [ColumnMeasurement] {
        var measurements = [ColumnMeasurement](
            repeating: ColumnMeasurement(), count: visibleColumns.count)
        let usable = context.availableWidth - max(0, visibleColumns.count - 1)
        guard usable > 0 else { return measurements }

        // Measure each column's HUGGED content width, not its greedy fill. A
        // width-greedy root (the sidebar/content `List`) reports `isWidthFlexible`
        // with a fill-the-offer width unless `fixedSizeWidth` is set — which
        // bucketed every column "flexible" so they split the usable width evenly
        // (1/N each), coming out WIDER than the proportional Automatic (1/4) and
        // Balanced (~1/3) shares. Requesting the hug (and proposing an unbounded
        // width so the ideal/content width is measured) makes a naturally-narrow
        // column take just its content width; the rightmost absorbs the slack.
        var measureContext = context.withAvailableSize(
            width: usable, height: context.availableHeight)
        measureContext.environment.fixedSizeWidth = true
        let proposal = ProposedSize(width: nil, height: nil)
        let preferences = context.environment.preferenceStorage
        let trailing = visibleColumns.count - 1

        for (index, column) in visibleColumns.enumerated()
        where includingTrailing || index < trailing {
            preferences?.push()
            let size = measureColumn(column, proposal: proposal, context: measureContext)
            let scope = preferences?.pop()
            measurements[index] = ColumnMeasurement(
                size: size,
                // `flatMap` rather than a subscript: there are two nils to
                // collapse here, "no preference stack at all" (a bare
                // measurement harness has none) and the key's own default, "this
                // column asked for nothing".
                request: scope.flatMap { $0[NavigationSplitViewColumnWidthKey.self] })
        }
        return measurements
    }

    /// Measures a column's content: its natural width and whether it's
    /// width-flexible (fills its column).
    func measureColumn(
        _ column: NavigationSplitViewColumn, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        switch column {
        case .sidebar:
            return measureChild(sidebar, proposal: proposal, context: context.withChildIdentity(type: type(of: sidebar)))
        case .content:
            return measureChild(content, proposal: proposal, context: context.withChildIdentity(type: type(of: content)))
        case .detail:
            return measureChild(detail, proposal: proposal, context: context.withChildIdentity(type: type(of: detail)))
        default:
            return ViewSize(width: 0, height: 0)
        }
    }

    /// The width a column asks for, before the layout's own clamps.
    ///
    /// The one place either width model resolves a request, so the two cannot
    /// drift apart in what they honour. `natural` is what the column would get
    /// with nothing asked for: the style-derived default under the proportional
    /// styles, the measured content width under size-to-fit.
    ///
    /// - the user's width wins when they have dragged or keyed this divider
    ///   (`.navigationSplitViewColumnWidthReset(_:)` releases it),
    /// - else the `fixed` width the column asked for, else its `ideal`,
    /// - else `natural`;
    /// - and the result is held inside the request's `min…max` band.
    ///
    /// The band clamps the user's width TOO, which is what makes a fixed
    /// `.navigationSplitViewColumnWidth(30)` stick: a fixed width is the
    /// degenerate band 30…30, so a drag writes its raw intent, this pins it back
    /// to 30, and the render's write-back stores 30 — the column simply does not
    /// move. A `min:ideal:max:` column opens at `ideal` and then drags freely
    /// between `min` and `max`.
    private func requestedColumnWidth(
        natural: Int, userPinned: Int?, request: NavigationSplitViewColumnWidth?
    ) -> Int {
        var width = userPinned ?? request?.fixed ?? request?.ideal ?? natural
        if let lower = request?.fixed ?? request?.min { width = max(width, lower) }
        if let upper = request?.fixed ?? request?.max { width = min(width, upper) }
        return width
    }

    /// The default width of a left (non-trailing) column, derived from the
    /// active ``NavigationSplitViewStyle``'s proportions and the usable width.
    ///
    /// This is what makes `.automatic`, `.balanced`, and `.prominentDetail`
    /// render distinctly: a wider `sidebarProportion` / leading
    /// `threeColumnProportions` yields wider leading columns, leaving the
    /// trailing detail column (which absorbs the remainder) correspondingly
    /// narrower. `.prominentDetail`'s small leading proportions thus give it a
    /// noticeably wider detail; `.balanced`'s larger ones make the columns
    /// comparable. Clamped to at least `minimumColumnWidth` so a tiny terminal
    /// still shows every column.
    private func defaultColumnWidth(
        for column: NavigationSplitViewColumn,
        style: any NavigationSplitViewStyle,
        isThreeColumnLayout: Bool,
        usableWidth: Int
    ) -> Int {
        let proportion: Double
        if isThreeColumnLayout {
            let props = style.threeColumnProportions
            switch column {
            case .sidebar: proportion = props.sidebar
            case .content: proportion = props.content
            default: proportion = props.detail
            }
        } else {
            // Two-column: only the sidebar is a leading column; the detail
            // absorbs the rest, so its proportion is implied (1 − sidebar).
            proportion = column == .sidebar ? style.sidebarProportion : 1 - style.sidebarProportion
        }
        return max(minimumColumnWidth, Int((Double(usableWidth) * proportion).rounded()))
    }

    /// Calculates the width for each visible column.
    ///
    /// TUI-specific: every left column has a width, the rightmost column is
    /// flexible and absorbs the remainder. A left column's width is whatever
    /// ``requestedColumnWidth(natural:userPinned:request:)`` resolves — the
    /// user's stored width, the column's own
    /// `.navigationSplitViewColumnWidth(…)`, or the style-derived default (see
    /// ``defaultColumnWidth(for:style:isThreeColumnLayout:usableWidth:)``) —
    /// then clamped so the column keeps at least `minimumColumnWidth` and leaves
    /// at least that much for each column to its right. When `writeBack` is set
    /// (the real render of a resizable split), the clamped width is written back
    /// so the next arrow-key step starts from the true current width and a
    /// too-wide drag settles at the real maximum.
    private func calculateColumnWidths(
        visibleColumns: [NavigationSplitViewColumn],
        style: any NavigationSplitViewStyle,
        availableWidth: Int,
        measured: [ColumnMeasurement],
        widths: SplitViewWidths?,
        writeBack: Bool
    ) -> [Int] {
        let separatorCount = max(0, visibleColumns.count - 1)
        let usableWidth = availableWidth - separatorCount

        guard usableWidth > 0 else {
            return Array(repeating: 0, count: visibleColumns.count)
        }

        var result: [Int] = []
        var remainingWidth = usableWidth

        for (index, column) in visibleColumns.enumerated() {
            let isLastColumn = index == visibleColumns.count - 1

            if isLastColumn {
                // Last column gets all remaining width
                result.append(max(minimumColumnWidth, remainingWidth))
            } else {
                // A user-resized column keeps its stored width, a column that
                // asked for one gets what it asked for, and an untouched column
                // follows the style default (so changing the style re-flows it
                // live).
                let desired = requestedColumnWidth(
                    natural: defaultColumnWidth(
                        for: column, style: style,
                        isThreeColumnLayout: isThreeColumn, usableWidth: usableWidth),
                    userPinned: widths?.isUserSet(column) == true ? widths?.value(for: column) : nil,
                    request: measured[index].request)
                // Reserve at least minimumColumnWidth for every column still to
                // the right, so a wide left column can't starve them.
                let columnsToTheRight = visibleColumns.count - index - 1
                let maxForColumn =
                    remainingWidth - minimumColumnWidth * columnsToTheRight
                let width = max(
                    minimumColumnWidth, min(desired, max(minimumColumnWidth, maxForColumn)))
                // Persist the clamped effective width WITHOUT marking it
                // user-set, so a style-derived column keeps a valid drag/keyboard
                // seed yet still re-derives when the style changes; a user-set
                // column simply keeps its (now re-clamped) value.
                if writeBack {
                    widths?.setClamped(width, for: column)
                }
                result.append(width)
                remainingWidth -= width
            }
        }

        return result
    }

    /// Sizes columns to fit their content from the left: a naturally-narrow
    /// (non-flexible) column takes its content width; the width-flexible columns
    /// share the remainder, the last absorbing rounding. When the fixed columns
    /// would leave less than the minimum for each flexible column, they're shrunk
    /// from the right (their content truncates). Every column keeps at least
    /// `minimumColumnWidth`, and the widths always sum to the usable width.
    private func sizeToFitColumnWidths(
        visibleColumns: [NavigationSplitViewColumn],
        availableWidth: Int,
        measured: [ColumnMeasurement],
        widths: SplitViewWidths?,
        writeBack: Bool
    ) -> [Int] {
        let count = visibleColumns.count
        let usable = availableWidth - max(0, count - 1)
        guard usable > 0, count > 0 else { return Array(repeating: 0, count: count) }

        var natural = measured.map { max(minimumColumnWidth, $0.size.width) }
        var flexible = measured.map(\.size.isWidthFlexible)

        // A column that has asked for a width — pinned by the user's drag /
        // keyboard, or requested with `.navigationSplitViewColumnWidth(…)` — is
        // DETERMINATE: it holds that width while the untouched columns keep
        // fitting their content and the trailing one absorbs the slack. (The
        // trailing column is neither: it is always the flexible remainder.)
        // `.navigationSplitViewColumnWidthReset(_:)` clears the user's pins.
        for index in 0..<max(0, count - 1) {
            let column = visibleColumns[index]
            let pinned = widths?.isUserSet(column) == true ? widths?.value(for: column) : nil
            let request = measured[index].request
            guard pinned != nil || request != nil else { continue }
            natural[index] = max(
                minimumColumnWidth,
                requestedColumnWidth(
                    natural: natural[index], userPinned: pinned, request: request))
            flexible[index] = false
        }

        var widthsResult = [Int](repeating: minimumColumnWidth, count: count)
        let flexIndices = (0..<count).filter { flexible[$0] }
        let fixedIndices = (0..<count).filter { !flexible[$0] }
        for index in fixedIndices { widthsResult[index] = natural[index] }
        var fixedSum = fixedIndices.reduce(0) { $0 + widthsResult[$1] }

        guard !flexIndices.isEmpty else {
            // No flexible column — the rightmost absorbs the slack so the split
            // still fills its width.
            widthsResult[count - 1] += max(0, usable - fixedSum)
            writeBackUserSet(
                widthsResult, visibleColumns: visibleColumns, widths: widths, writeBack: writeBack)
            return widthsResult
        }

        // Shrink fixed columns from the right if they'd starve the flexible ones.
        var freeForFlex = usable - fixedSum
        let flexMinTotal = flexIndices.count * minimumColumnWidth
        if freeForFlex < flexMinTotal {
            var deficit = flexMinTotal - freeForFlex
            for index in fixedIndices.reversed() where deficit > 0 {
                let give = min(widthsResult[index] - minimumColumnWidth, deficit)
                widthsResult[index] -= give
                deficit -= give
            }
            fixedSum = fixedIndices.reduce(0) { $0 + widthsResult[$1] }
            freeForFlex = usable - fixedSum
        }

        // Split the remainder evenly; the last flexible column absorbs rounding.
        let per = max(minimumColumnWidth, freeForFlex / flexIndices.count)
        for (position, index) in flexIndices.enumerated() {
            widthsResult[index] =
                position == flexIndices.count - 1
                ? max(minimumColumnWidth, freeForFlex - per * (flexIndices.count - 1))
                : per
        }
        writeBackUserSet(
            widthsResult, visibleColumns: visibleColumns, widths: widths, writeBack: writeBack)
        return widthsResult
    }

    /// Writes the clamped effective width of each user-pinned column back to the
    /// shared store (render pass only), so the next drag / arrow resize steps
    /// from the width actually shown rather than a stale intent — the size-to-fit
    /// counterpart of `calculateColumnWidths`'s write-back. Only user-set columns
    /// are touched; the style-derived ones re-measure from content every frame.
    private func writeBackUserSet(
        _ effective: [Int], visibleColumns: [NavigationSplitViewColumn],
        widths: SplitViewWidths?, writeBack: Bool
    ) {
        guard writeBack, let widths else { return }
        for index in 0..<max(0, effective.count - 1) where widths.isUserSet(visibleColumns[index]) {
            widths.setClamped(effective[index], for: visibleColumns[index])
        }
    }
}
