//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenusChecks.swift
//
//  What the `menus` session's screen must show, judged from what the session
//  did and the model it did it to — never from another rendering, which would
//  share any mistake it made.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

extension MenusSession {
    // MARK: The model's side of the rows

    /// The rows the open menu lets the arrows land on, as their labels, in order.
    func selectableRows(_ kind: OpenMenu.Kind) -> [String] {
        switch kind {
        case .popUp("File"):
            ["New Document", "Sort Ascending", "Sort Descending"] + desk.recent.map { "Reopen #\($0)" }
        case .popUp("View"): ["Zoom In", "Zoom Out", "Actual Size"]
        case .popUp("Export"):
            ["Export PDF", "Export HTML", "Export Plain Text", "Export Everything As One Long Archive"]
        case .popUp: ["Show Shortcuts", "About Documents"]
        case .picker: MenuDesk.filters
        case .context(let id): ["Rename #\(id)", "Promote #\(id)", "Trash #\(id)"]
        case .suggestions: desk.suggestions
        }
    }

    /// The command that choosing the row `label` of a menu `kind` runs, as
    /// ``MenuDesk/last`` records it: the label itself, but for a suggestion,
    /// which submits the field with it, and the one Export row whose label is
    /// longer than its command.
    func command(choosing label: String, in kind: OpenMenu.Kind) -> String {
        switch kind {
        case .suggestions: "Tag \(label)"
        case .popUp("Export") where label.hasPrefix("Export Everything"): "Export Archive"
        default: label
        }
    }

    /// The focus the status line reports, or `nil` when it is not on the screen.
    var focusShown: String? { Self.focus(on: screen) }

    static func focus(on screen: [String]) -> String? {
        guard let line = statusLine(on: screen), line.hasPrefix("["), let end = line.firstIndex(of: "]") else {
            return nil
        }
        let shown = String(line[line.index(after: line.startIndex)..<end])
        // A document says so itself, with a `▸` before its name — and where a
        // narrow terminal has cut its number off, nobody can say which.
        guard shown == "none", let row = screen.first(where: { $0.contains("▸") }) else { return shown }
        guard let range = row.range(of: #"#\d+"#, options: .regularExpression) else { return nil }
        return "row " + row[range].dropFirst()
    }

    /// The page's status line, where the screen shows it.
    static func statusLine(on screen: [String]) -> String? {
        screen.first { $0.hasPrefix("[") && $0.contains(" applied") }
    }

    // MARK: Finding things on the screen

    /// Whether document `id` is drawn in the list.
    func showsDocument(_ id: Int, on screen: [String]? = nil) -> Bool {
        (screen ?? self.screen).contains { line in
            guard let range = line.range(of: "#\(id)") else { return false }
            return range.upperBound == line.endIndex || !line[range.upperBound].isNumber
        }
    }

    /// Whether some row of the menu `kind` is drawn in a pop-up on the screen —
    /// by its start, since a long label wraps or ends in an ellipsis.
    func shows(_ kind: OpenMenu.Kind, on screen: [String]? = nil) -> Bool {
        selectableRows(kind).contains { Self.drawnRow($0, on: screen ?? self.screen) != nil }
    }

    /// Where a pop-up draws the row `label`, found by its start — its first
    /// fourteen characters, whole when that is all of it.
    static func drawnRow(_ label: String, on screen: [String]) -> (x: Int, y: Int)? {
        popupRow(String(label.prefix(14)), on: screen, whole: label.count <= 14)
    }

    /// Where `text` is first drawn on the screen, in cells — inside a pop-up's
    /// border when `inPopup`.
    func locate(_ text: String, inPopup: Bool = false) -> (x: Int, y: Int)? {
        inPopup ? Self.popupRow(text, on: screen) : Self.find(text, on: screen)
    }

    /// Where `text` is first drawn on `screen`.
    static func find(_ text: String, on screen: [String]) -> (x: Int, y: Int)? {
        for (y, line) in screen.enumerated() {
            guard let range = line.range(of: text) else { continue }
            return (line.distance(from: line.startIndex, to: range.lowerBound), y)
        }
        return nil
    }

    /// Where a pop-up draws the row labelled `label`: the label inside a
    /// border, and not the start of a longer one ("Reopen #5" is not
    /// "Reopen #52") — or its start alone, when `whole` is false, for a label
    /// that wraps or ends in an ellipsis.
    static func popupRow(_ label: String, on screen: [String], whole: Bool = true) -> (x: Int, y: Int)? {
        for (y, line) in screen.enumerated() {
            var searched = line.startIndex
            while let range = line.range(of: label, range: searched..<line.endIndex) {
                searched = range.upperBound
                let ends = range.upperBound == line.endIndex || !(line[range.upperBound].isLetter || line[range.upperBound].isNumber)
                guard line[..<range.lowerBound].contains("│"), ends || !whole else { continue }
                return (line.distance(from: line.startIndex, to: range.lowerBound), y)
            }
        }
        return nil
    }

    /// Every label a pop-up of the page draws and nothing else does: none may
    /// be on the screen while no menu is open.
    private var popupOnlyLabels: [String] {
        let fixed = [
            "New Document", "Sort Ascending", "Sort Descending", "Reopen #", "Zoom In", "Zoom Out",
            "Actual Size", "Export PDF", "Export HTML", "Export Plain Text", "Show Shortcuts",
            "About Documents", "Rename #", "Promote #", "Trash #",
        ]
        let filters = MenuDesk.filters.indices.filter { $0 != desk.filter }.map { MenuDesk.filters[$0] }
        return fixed + filters + MenuDesk.tags.filter { $0 != desk.tag }
    }

    func check(_ screen: [String], after index: Int) -> String? {
        if desk.applied != expectedApplied {
            return "\(desk.applied) commands ran where the session chose \(expectedApplied)"
        }
        if let expectedLast, desk.last != expectedLast {
            return "the command that ran last is \(desk.last) where the session chose \(expectedLast)"
        }
        if desk.filter != expectedFilter {
            return "the filter is \(MenuDesk.filters[desk.filter]) where the session chose \(MenuDesk.filters[expectedFilter])"
        }
        if let status = Self.statusLine(on: screen), !status.contains("] \(desk.applied) applied") {
            return "the status line says \(status.prefix(12)) with \(desk.applied) commands run"
        }
        guard let menu = open else { return closedProblems(screen, after: index) }
        return openProblems(menu, screen)
    }

    /// With no menu open: nothing of one on the screen, and the focus handed
    /// back to where it was before the last one opened.
    private func closedProblems(_ screen: [String], after index: Int) -> String? {
        if let lost, shows(lost, on: screen) {
            return "\(describe(lost)) closed when its document left the list, and is back"
        }
        // The status line repeats the last command and the tag; it is the one
        // line allowed a menu's words.
        for (y, line) in screen.enumerated() where line != Self.statusLine(on: screen) {
            if let label = popupOnlyLabels.first(where: { line.contains($0) }) {
                return "no menu is open, but line \(y) still shows \"\(label)\": \(line.trimmingCharacters(in: .whitespaces))"
            }
        }
        // Not to a document the command itself took off the list — a promotion
        // out of the filter, a deletion: there is nowhere to go back to. Nor
        // from nowhere: with no focus to go back to, TUIkit gives it to the
        // first focus stop, as it does on any page that has none.
        if let (focus, from) = focusAfterClose, index == from, let shown = Self.focus(on: screen), shown != focus,
            focus != "none", !focus.hasPrefix("row ") || desk.shown.contains(where: { "row \($0.id)" == focus })
        {
            return "a menu closed, and the focus went to \(shown), not back to \(focus)"
        }
        return nil
    }

    /// With a menu open: its box whole on the screen, every row it has drawn
    /// in full, and a scroll indicator when some are not drawn.
    private func openProblems(_ menu: OpenMenu, _ screen: [String]) -> String? {
        let rows = selectableRows(menu.kind)
        guard !rows.isEmpty else { return nil }
        // A row counts as drawn by its start: a long label wraps in a menu too
        // narrow for it, or ends in an ellipsis.
        let drawn = rows.filter { Self.drawnRow($0, on: screen) != nil }
        guard let first = drawn.first, let (x, y) = Self.drawnRow(first, on: screen) else {
            // Closed with its document, which left the list's window: see
            // `stepInMenu`, which learns it from this frame.
            if case .context(let id) = menu.kind, !showsDocument(id, on: screen) { return nil }
            return "\(describe(menu.kind)) is open, but none of its rows is on the screen"
        }
        // Two lines of content (a terminal eight tall, less the header's and
        // the status bar's boxes) have no room for a box round a row at all.
        let content = Self.contentLines(of: screen)
        guard content.count >= 3 else { return nil }
        guard let box = PopupBox(aroundColumn: x, at: y, on: screen) else {
            return "\(describe(menu.kind)) is open, but the box around \"\(first)\" is not whole on the screen"
        }
        if !content.contains(box.top) || !content.contains(box.bottom) {
            return "\(describe(menu.kind))'s box runs from line \(box.top) to \(box.bottom), outside the content's "
                + "lines \(content.lowerBound)...\(content.upperBound)"
        }
        if drawn.count < rows.count {
            let interior = (box.top...box.bottom).map { screen[$0] }
            if !interior.contains(where: { $0.contains("▲") || $0.contains("▼") || $0.contains("more") }) {
                let missing = rows.filter { !drawn.contains($0) }
                return "\(describe(menu.kind)) draws \(drawn.count) of \(rows.count) rows and no way to reach \(missing)"
            }
        }
        return nil
    }

    /// The open menu's highlight, read from how its rows are painted: the row
    /// the session walked to painted apart from the others, or none apart
    /// when it walked to none.
    func check(styled screen: [String], after index: Int) -> String? {
        guard let menu = open, !menu.awaitingRelease else { return nil }
        let rows = selectableRows(menu.kind)
        let stripped = screen.map(\.stripped)
        let cells = ScreenCells(screen)
        // The field each drawn row's label is painted on.
        var fields: [(row: Int, field: Color?)] = []
        for (row, label) in rows.enumerated() {
            guard let (x, y) = Self.popupRow(label, on: stripped) else { continue }
            fields.append((row, cells.cell(row: y, column: x + label.count / 2)?.background))
        }
        guard fields.count > 1 else { return nil }
        let painted = fields.map { "\(rows[$0.row]) on \(ScreenCell.name($0.field))" }.joined(separator: ", ")
        if let highlight = menu.highlight, highlight < rows.count {
            guard let lit = fields.first(where: { $0.row == highlight }) else { return nil }
            if fields.contains(where: { $0.row != highlight && $0.field == lit.field }) {
                return "\(describe(menu.kind)) should highlight \"\(rows[highlight])\", but its row is painted as "
                    + "another is: \(painted)"
            }
        } else if Set(fields.map { ScreenCell.name($0.field) }).count > 1 {
            return "\(describe(menu.kind)) should highlight nothing, but a row is painted apart: \(painted)"
        }
        return nil
    }

    /// The lines between the app header's box and the status bar's.
    static func contentLines(of screen: [String]) -> ClosedRange<Int> {
        let top = screen.first?.hasPrefix("╭") == true ? (screen.firstIndex { $0.hasPrefix("╰") } ?? -1) + 1 : 0
        let bottom = (screen.lastIndex { $0.hasPrefix("╭") }).map { $0 - 1 } ?? screen.count - 1
        return top...max(top, bottom)
    }

    private func describe(_ kind: OpenMenu.Kind) -> String {
        switch kind {
        case .popUp(let label): "the \(label) menu"
        case .picker: "the filter's drop-down"
        case .context(let id): "the context menu of #\(id)"
        case .suggestions: "the tag suggestions"
        }
    }
}

/// A pop-up's border, found from a row inside it: the column of its left and
/// right edges and the lines of its top and bottom.
private struct PopupBox {
    let left: Int
    let right: Int
    let top: Int
    let bottom: Int

    init?(aroundColumn labelAt: Int, at y: Int, on screen: [String]) {
        let lines = screen.map { Array($0) }
        guard let left = (0..<labelAt).last(where: { lines[y][$0] == "│" }) else { return nil }
        func at(_ line: Int, _ column: Int) -> Character? {
            lines.indices.contains(line) && lines[line].indices.contains(column) ? lines[line][column] : nil
        }
        guard let top = (0..<y).last(where: { at($0, left) == "╭" || at($0, left) == "┌" }),
            let bottom = (y + 1..<lines.count).first(where: { at($0, left) == "╰" || at($0, left) == "└" }),
            let right = (left + 1..<lines[top].count).first(where: { at(top, $0) == "╮" || at(top, $0) == "┐" }),
            at(bottom, right) == "╯" || at(bottom, right) == "┘"
        else { return nil }
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }
}
