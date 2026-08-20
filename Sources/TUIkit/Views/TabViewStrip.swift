//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewStrip.swift
//
//  How a TabView draws its strip of tabs: the compact chips, the folder-tab
//  chrome, and the colours both take. Split from TabView.swift, which keeps
//  the view itself — its focus, geometry, and content panel.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _TabViewCore {

    /// Lays out the wrapped, aligned compact chip rows. Returns the lines (each
    /// padded to `width`), the per-tab click regions in strip coordinates, and
    /// the active chip's animation run if it is breathing.
    func compactStripLines(
        rows: [[Int]], selectedIndex: Int, hoveredIndex: Int?,
        chip: ActiveChipCycle, palette: any Palette,
        width: Int, alignment: HorizontalAlignment
    ) -> (
        lines: [String], regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)],
        animatedCells: [AnimatedCellRun]
    ) {
        let (inactiveFg, inactiveBg) = stripLabelColors(palette: palette)
        var lines: [String] = []
        var regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)] = []
        var animatedCells: [AnimatedCellRun] = []

        // A coloured chip: the half-block caps (▐ … ▌) extend the chip's fill
        // half a cell each side with a clean edge. One function draws it, so
        // the animation's frames are the same cells the render draws — a second
        // spelling of this is how a replayed run drifts from what is on screen.
        func drawChip(_ index: Int, background: Color, foreground: Color, active: Bool) -> String {
            ANSIRenderer.colorize("▐", foreground: background)
                + ANSIRenderer.colorize(
                    " \(tabs[index].title) ", foreground: foreground,
                    background: background, bold: active)
                + ANSIRenderer.colorize("▌", foreground: background)
        }

        for (y, row) in rows.enumerated() {
            let offset = max(0, alignment.childOffset(childWidth: compactRowWidth(row), in: width))
            var line = String(repeating: " ", count: offset)
            var x = offset
            for i in row {
                // The active chip takes the surface (breathing when focused);
                // inactive chips recede onto the base background.
                let active = i == selectedIndex
                // The pointer lifts the label it is over — including the active
                // tab's, unless that one is already breathing for the focus.
                let hovered = i == hoveredIndex && !(active && chip.isBreathing)
                let resting = active ? chip.labelNow : inactiveFg
                line += drawChip(
                    i, background: active ? chip.surface : inactiveBg,
                    foreground: hovered ? palette.hoveredForeground(resting) : resting,
                    active: active)
                let chipWidth = tabWidth(i, style: .compact)  // body + the two caps
                regions.append((x: x, y: y, width: chipWidth, height: 1, index: i))
                if active,
                    let run = chip.run(offsetX: x, offsetY: y, draw: {
                        drawChip(i, background: chip.surface, foreground: $0, active: true)
                    })
                {
                    animatedCells.append(run)
                }
                x += chipWidth
            }
            if x < width { line += String(repeating: " ", count: width - x) }
            lines.append(line)
        }
        return (lines, regions, animatedCells)
    }

    /// The chrome a folder-tab strip is drawn from: the label colours, the
    /// border and surface tones, and the box geometry its rows align within.
    struct FolderStripStyle {
        let inactiveFg: Color
        /// The tab under the pointer, if any.
        let hoveredIndex: Int?
        /// For the hover lift (``Palette/hoveredForeground(_:)``).
        let palette: any Palette
        let inactiveBg: Color
        let border: Color
        let surface: Color
        let interior: Int
        let boxWidth: Int
        let alignment: HorizontalAlignment
    }

    /// Draws the folder-tab strip: per row, a line of tab tops and a line of
    /// labels, and under the last row the content box's top border curving
    /// around the active tab.
    ///
    /// Returns the lines, the per-tab click regions, and the active chip's
    /// animation run — all in box coordinates, which are also the buffer's,
    /// because the strip opens it.
    func folderStripRows(
        rows: [[Int]], selectedIndex: Int, chip: ActiveChipCycle, style: FolderStripStyle
    ) -> (
        lines: [String], regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)],
        animatedCells: [AnimatedCellRun]
    ) {
        func bc(_ s: String) -> String { ANSIRenderer.colorize(s, foreground: style.border) }
        func base(_ n: Int) -> String { n > 0 ? String(repeating: " ", count: n) : "" }
        // The absolute box column of a row's left wall, per the strip alignment.
        func rowOffset(_ rowWidth: Int) -> Int {
            1 + max(0, style.alignment.childOffset(childWidth: rowWidth, in: style.interior))
        }
        // One function draws a tab's label so the animation's frames are the
        // same cells the render draws. The walls either side are border chrome
        // and do not breathe, so a folder tab's run is its body only.
        func drawLabel(_ index: Int, background: Color, foreground: Color, active: Bool) -> String {
            ANSIRenderer.colorize(
                " \(tabs[index].title) ", foreground: foreground,
                background: background, bold: active)
        }

        var lines: [String] = []
        var regions: [(x: Int, y: Int, width: Int, height: Int, index: Int)] = []
        var animatedCells: [AnimatedCellRun] = []

        for (rowIndex, row) in rows.enumerated() {
            let isBottom = rowIndex == rows.count - 1
            let off = rowOffset(folderRowWidth(row))

            // Walls (count + 1) and bodies for this row, in absolute columns.
            var wallCols: [Int] = []
            var bodySpans: [(start: Int, len: Int, index: Int)] = []
            var col = off
            for i in row {
                wallCols.append(col)
                let bw = tabWidth(i, style: .bordered)
                bodySpans.append((start: col + 1, len: bw, index: i))
                col += 1 + bw
            }
            wallCols.append(col)

            // Tab tops: the whole strip span is border-coloured, so emit it as one
            // run — `╭`/`╮` for active corners & strip ends, `┬` for shared walls.
            var top = ""
            for k in wallCols.indices {
                // A wall touching the active tab takes a rounded corner so the
                // active tab reads as a raised `╭ … ╮` cell — `╮` on its right
                // wall, `╭` on its left. These deliberately cut into the shared
                // walls with its neighbours (a "backwards" corner on the
                // neighbour), which is what makes the active tab stand out.
                let activeRight = k > 0 && row[k - 1] == selectedIndex
                let activeLeft = k < bodySpans.count && row[k] == selectedIndex
                top += Self.topWallGlyph(
                    isStripStart: k == 0, isStripEnd: k == wallCols.count - 1,
                    activeRight: activeRight, activeLeft: activeLeft)
                if k < bodySpans.count { top += String(repeating: "─", count: bodySpans[k].len) }
            }
            lines.append(base(off) + bc(top) + base(style.boxWidth - off - top.count))

            // Tab labels: `│ title │ title │ …`, the active chip on the surface.
            let labelsY = lines.count
            var labels = base(off)
            for (k, i) in row.enumerated() {
                let active = i == selectedIndex
                let hovered = i == style.hoveredIndex && !(active && chip.isBreathing)
                let resting = active ? chip.labelNow : style.inactiveFg
                labels += bc("│")
                labels += drawLabel(
                    i, background: active ? chip.surface : style.inactiveBg,
                    foreground: hovered ? style.palette.hoveredForeground(resting) : resting,
                    active: active)
                // The chrome above and below a tab is the tab's, not the
                // page's: a folder tab is drawn as three rows and read as one
                // control, so a click on the line over the title should not
                // miss. The top border always belongs to it; the row below
                // does too on the bottom row, where it is the content box's
                // own border — higher up it is the NEXT row's top border, and
                // two tabs claiming one row would make the answer arbitrary.
                regions.append((
                    x: bodySpans[k].start, y: labelsY - 1, width: bodySpans[k].len,
                    height: isBottom ? 3 : 2, index: i))
                if active,
                    let run = chip.run(
                        offsetX: bodySpans[k].start, offsetY: labelsY,
                        draw: { drawLabel(i, background: chip.surface, foreground: $0, active: true) })
                {
                    animatedCells.append(run)
                }
            }
            labels += bc("│")
            lines.append(labels + base(style.boxWidth - off - folderRowWidth(row)))

            // Under the active (bottom) row: the content box's top border, curving
            // up to wrap the active tab and opening (surface gap) beneath it.
            if isBottom {
                lines.append(activeRowBottomBorder(
                    wallCols: wallCols, bodySpans: bodySpans, selectedIndex: selectedIndex,
                    boxWidth: style.boxWidth, border: style.border, surface: style.surface))
            }
        }
        return (lines, regions, animatedCells)
    }

    /// The inactive chips' foreground and background. Shared by both strip
    /// styles; the ACTIVE chip's label comes from ``ActiveChipCycle``, which
    /// owns both ends of its breath.
    func stripLabelColors(palette: any Palette) -> (inactiveFg: Color, inactiveBg: Color) {
        (palette.foregroundSecondary, palette.background.resolve(with: palette))
    }

    /// The glyph for a tab-strip top wall: rounded corners at the strip ends and
    /// around the active tab (`╭`/`╮`), a `┬` for an ordinary shared wall. The
    /// precedence (strip-end before active-tab) makes a wall that is both read as
    /// the strip end.
    static func topWallGlyph(
        isStripStart: Bool, isStripEnd: Bool, activeRight: Bool, activeLeft: Bool
    ) -> String {
        if isStripStart {
            return "╭"
        } else if isStripEnd {
            return "╮"
        } else if activeRight {
            return "╮"
        } else if activeLeft {
            return "╭"
        } else {
            return "┬"
        }
    }

    /// The content box's top border drawn beneath the active (bottom) tab row: it
    /// curves up to wrap the active tab (`╯` … `╰`, with a surface-coloured gap
    /// across the tab body) and meets the inactive walls with `┴`.
    func activeRowBottomBorder(
        wallCols: [Int], bodySpans: [(start: Int, len: Int, index: Int)],
        selectedIndex: Int, boxWidth: Int, border: Color, surface: Color
    ) -> String {
        func bc(_ s: String) -> String { ANSIRenderer.colorize(s, foreground: border) }
        let activeWall = wallCols.firstIndex { wc in
            bodySpans.contains { $0.index == selectedIndex && $0.start == wc + 1 }
        } ?? 0
        let aLeft = wallCols[activeWall]
        guard let aBody = bodySpans.first(where: { $0.index == selectedIndex }) else {
            return bc("╰" + String(repeating: "─", count: max(0, boxWidth - 2)) + "╯")
        }
        let aRight = aBody.start + aBody.len
        let inactiveWalls = Set(wallCols).subtracting([aLeft, aRight])
        func borderGlyph(_ c: Int) -> String {
            if c == 0 { return "╭" }
            if c == boxWidth - 1 { return "╮" }
            if c == aLeft { return "╯" }
            if c == aRight { return "╰" }
            return inactiveWalls.contains(c) ? "┴" : "─"
        }
        var left = ""
        for c in 0..<aBody.start { left += borderGlyph(c) }
        var right = ""
        for c in aRight..<boxWidth { right += borderGlyph(c) }
        let gap =
            aBody.len > 0
            ? ANSIRenderer.colorize(String(repeating: " ", count: aBody.len), background: surface)
            : ""
        return bc(left) + gap + bc(right)
    }
}
