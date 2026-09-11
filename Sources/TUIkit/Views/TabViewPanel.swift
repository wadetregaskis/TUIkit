//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewPanel.swift
//
//  How a TabView fills its content panel: a line of the selected tab's content,
//  centred, with the rest of the row in the panel's surface. Shared by the compact
//  and the bordered styles, which each used to spell the pads their own way.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _TabViewCore {

    /// One row of a tab's panel: a line of the selected tab's content, `leftPad`
    /// cells in, with the rest of `width` filled in the panel's surface.
    ///
    /// The content is spliced in FINISHED and claims nothing here: it was rendered
    /// `.background(surface)`, which claims its own rectangle, and those claims
    /// travel on its own buffer. Only the pads are claimed, each separately —
    /// overlapping claims multiply, so one rectangle across the line would fade the
    /// content's surface twice. A filler row is `line: ""`.
    func panelRow(_ line: String, used: Int, leftPad: Int, width: Int, surface: Color) -> ClaimingRow {
        var row = ClaimingRow()
        // Nothing at all for a pad of no width: a styled empty string still costs an
        // introducer and a reset.
        func pad(_ count: Int) {
            guard count > 0 else { return }
            row.append(String(repeating: " ", count: count), cells: count, ink: nil, field: surface)
        }
        pad(leftPad)
        row.appendFinished(line, cells: used)
        pad(width - leftPad - used)
        return row
    }
}
