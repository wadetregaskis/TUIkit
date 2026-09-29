//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ThemesChecks.swift
//
//  What the `themes` session's frames must show and how they must be painted,
//  judged from the look the session put on the page — the palettes, the depth
//  — and the promises TUIkit makes about the colours it chooses.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - A frame, as the checks read it

/// One frame, taken apart, with what the session knows about the look it was
/// drawn in.
@MainActor
struct ThemeFrame {
    let lines: [String]
    let cells: ScreenCells
    let depth: ColorDepth
    let rootPalette: any Palette
    let formPalette: any Palette
    let session: ThemesSession

    /// Where the focus is in this frame, as its status line says.
    var focus: String? { ThemesSession.focus(on: lines) }

    /// A colour as a terminal of this frame's depth is sent it — what a cell
    /// drawn in it holds — or `nil` where nobody can say: at 16 colours, which
    /// are the terminal's to choose; for a colour the terminal decides (its
    /// sixteen slots, its own ink and page); and for one that is not opaque
    /// (the Terminal palette's page is `Color.clear`, which leaves the page
    /// to the terminal).
    func drawn(_ colour: Color) -> Color? {
        guard colour.rgbComponents != nil, colour.isOpaque, !colour.isTerminalDefined else { return nil }
        switch depth {
        case .truecolor: return colour
        case .palette256: return colour.downsampledToPalette256()
        case .basic16, .noColor: return nil
        }
    }

    /// Where `text` is drawn, as (column, line), searching lines `rows`.
    func find(_ text: String, in rows: Range<Int>? = nil) -> (x: Int, y: Int)? {
        for y in rows ?? lines.indices where lines.indices.contains(y) {
            if let range = lines[y].range(of: text) {
                return (lines[y].distance(from: lines[y].startIndex, to: range.lowerBound), y)
            }
        }
        return nil
    }

    /// Whether `colour` lies within `tolerance` (in RGB steps) of a straight
    /// line between two of `roles`, or of one of them — a colour a blend of
    /// them could make.
    static func blends(_ colour: Color, of roles: [Color], within tolerance: Double) -> Bool {
        guard let c = colour.rgbComponents else { return true }
        let point = [Double(c.red), Double(c.green), Double(c.blue)]
        let ends = roles.compactMap(\.rgbComponents).map { [Double($0.red), Double($0.green), Double($0.blue)] }
        /// How far `point` is from the segment `a`–`b`.
        func distance(_ a: [Double], _ b: [Double]) -> Double {
            let ab: [Double] = (0..<3).map { b[$0] - a[$0] }
            let ap: [Double] = (0..<3).map { point[$0] - a[$0] }
            let length: Double = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2]
            let along: Double = ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]
            let t: Double = length == 0 ? 0 : min(1, max(0, along / length))
            var sum = 0.0
            for axis in 0..<3 {
                let gap = a[axis] + t * ab[axis] - point[axis]
                sum += gap * gap
            }
            return sum.squareRoot()
        }
        for (i, a) in ends.enumerated() {
            for b in ends[i...] where distance(a, b) <= tolerance { return true }
        }
        return false
    }

    /// Where the list draws the number of task `id`: inside its box — a line
    /// that starts with its border, in its first 40 columns — and not the
    /// start of a longer number.
    func listTag(_ id: Int) -> (x: Int, y: Int)? {
        let tag = "#\(id)"
        for (y, line) in lines.enumerated() where line.hasPrefix("│") {
            var searched = line.startIndex
            while let range = line.range(of: tag, range: searched..<line.endIndex) {
                searched = range.upperBound
                let x = line.distance(from: line.startIndex, to: range.lowerBound)
                guard x < 40, range.upperBound == line.endIndex || !line[range.upperBound].isNumber else { continue }
                return (x, y)
            }
        }
        return nil
    }

    /// The inked letter and digit cells of line `y` in columns `columns`.
    func letters(_ y: Int, _ columns: Range<Int>) -> [ScreenCell] {
        columns.compactMap { cells.cell(row: y, column: $0) }.filter { cell in
            guard let character = cell.character else { return false }
            return character.isLetter || character.isNumber
        }
    }
}

/// Whether `palette` is one TUIkit ships with its colours stated — the
/// palettes its readability audit holds to its pairs (`PaletteContrastAuditTests`).
@MainActor
private func isStatedShipped(_ palette: any Palette) -> Bool {
    (PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles).contains { $0.id == palette.id }
}

// MARK: - The promises

/// A contrast TUIkit promises between the ink and the field of some cells,
/// at some depths: the pair, the floor it comes from, and where the pair is
/// drawn. Add one to hold a new promise to every frame of the session.
///
/// Written from TUIkit's promises as they stand — the floors in
/// `ViewConstants`, the pairs `PaletteContrastAuditTests` holds shipped
/// palettes to — and nothing more: a proposed redesign of the list rows'
/// colours is not encoded here.
@MainActor
struct ContrastPromise {
    /// What the pair is, for the report.
    let name: String
    let floor: Double
    /// The depths the promise is made at.
    let depths: Set<ColorDepth>
    /// Whether both colours are measured as a 256-colour terminal draws them
    /// at every depth — the promise of `Color.ensuringRenderedContrast`,
    /// which floors a label so it reads the same on every terminal.
    let throughTheCube: Bool
    /// The cells the promise covers in a frame, when it holds for that frame's
    /// look at all.
    let cells: (ThemeFrame) -> [ScreenCell]

    /// The first of the cells that falls under the floor, described.
    func problem(in frame: ThemeFrame) -> String? {
        guard depths.contains(frame.depth) else { return nil }
        for cell in cells(frame) {
            guard let ink = cell.foreground, let field = cell.background else { continue }
            let (a, b) = throughTheCube ? (ink.downsampledToPalette256(), field.downsampledToPalette256()) : (ink, field)
            let ratio = a.contrastRatio(against: b)
            guard ratio > 0, ratio < floor - 0.005 else { continue }
            return "\(name): \"\(cell.character.map(String.init) ?? " ")\" in \(ScreenCell.name(a)) on "
                + "\(ScreenCell.name(b)) is \(String(format: "%.2f", ratio)):1, under \(floor) "
                + "(\(frame.rootPalette.name), the form in \(frame.formPalette.name), at \(frame.depth))"
        }
        return nil
    }

    /// Every promise the session holds its frames to.
    static let all: [Self] = listRows + [buttonLabels, disabledButtonLabel, header]

    /// A list's rows, by what they are this frame. The list's text keeps its
    /// own ink on every fill, which is what the floors assume.
    static let listRows: [Self] = [
        Self(
            name: "the cursor row of the focused list on the accent's breath (a selected row)",
            floor: ViewConstants.rowBreathPeakContrastFloor, depths: [.truecolor, .palette256],
            throughTheCube: false
        ) { frame in listRow(frame, .accentBreath) },
        Self(
            name: "the cursor row of the focused list on the focus wash's breath",
            floor: ViewConstants.rowBreathPeakContrastFloor, depths: [.truecolor], throughTheCube: false
        ) { frame in listRow(frame, .washBreath) },
        Self(
            name: "a selected row on its tint", floor: 3.0, depths: [.truecolor], throughTheCube: false
        ) { frame in isStatedShipped(frame.rootPalette) ? listRow(frame, .selectedTint) : [] },
        Self(
            name: "a plain row", floor: 4.5, depths: [.truecolor], throughTheCube: false
        ) { frame in isStatedShipped(frame.rootPalette) ? listRow(frame, .plain) : [] },
    ]

    /// An enabled button's label on its face, as `ButtonStyle` floors it.
    static let buttonLabels = Self(
        name: "an enabled button's label", floor: ViewConstants.labelContrastFloor,
        depths: [.truecolor, .palette256], throughTheCube: true
    ) { frame in
        ["▐ Save ▌", "▐ Tinted ▌"].flatMap { label -> [ScreenCell] in
            guard let (x, y) = frame.find(label) else { return [] }
            return frame.letters(y, x..<x + label.count)
        }
    }

    /// A disabled button's label, floored lower on purpose.
    static let disabledButtonLabel = Self(
        name: "a disabled button's label", floor: ViewConstants.disabledLabelContrastFloor,
        depths: [.truecolor, .palette256], throughTheCube: true
    ) { frame in
        guard let (x, y) = frame.find("▐ Revert ▌") else { return [] }
        return frame.letters(y, x..<x + 10)
    }

    /// The app header's text on its bar: foreground/appHeader, 4.5 in the audit.
    static let header = Self(
        name: "the app header's text", floor: 4.5, depths: [.truecolor], throughTheCube: false
    ) { frame in
        guard isStatedShipped(frame.rootPalette), let (x, y) = frame.find("Themes · ", in: 0..<3) else { return [] }
        return frame.letters(y, x..<frame.lines[y].count)
    }

    /// What a list row is, read from the fill it is drawn on
    /// (`RowBackground`): on the page, a plain row; a selected row on the tint
    /// a selection rests in; a selected row on anything else, the cursor on
    /// it, breathing the accent; an unselected row on anything else, the
    /// cursor, breathing the focus wash. From the drawing rather than from a
    /// cursor the session walks, which would be one more thing for it to get
    /// wrong: where TUIkit puts the cursor as the focus comes back is TUIkit's
    /// to decide, and not what these promises are about.
    enum RowKind {
        case plain, selectedTint, accentBreath, washBreath
    }

    /// The letters of the list's rows of `kind`, found by the number each row
    /// ends in.
    private static func listRow(_ frame: ThemeFrame, _ kind: RowKind) -> [ScreenCell] {
        frame.session.board.tasks.flatMap { task -> [ScreenCell] in
            guard let (x, y) = frame.listTag(task.id), frame.rowKind(task.id, at: y, before: x) == kind else {
                return []
            }
            return frame.letters(y, 1..<x + "#\(task.id)".count)
        }
    }
}

extension ThemeFrame {
    /// What the list's row for task `id`, drawn on line `y` with its number
    /// at `x`, is: see ``ContrastPromise/RowKind``.
    func rowKind(_ id: Int, at y: Int, before x: Int) -> ContrastPromise.RowKind {
        let field = ScreenCell.name(letters(y, 1..<x).first?.background)
        let pages = [rootPalette.background].compactMap(drawn).map { ScreenCell.name($0) }
        let isSelected = session.board.selection == id
        guard !pages.contains(field) else { return .plain }
        guard isSelected else { return .washBreath }
        guard case .fill(let tint) = rootPalette.selectedRowFill(), let drawnTint = drawn(tint) else {
            return .accentBreath
        }
        return ScreenCell.name(drawnTint) == field ? .selectedTint : .accentBreath
    }
}

// MARK: - The checks

extension ThemesSession {
    func check(_ screen: [String], after index: Int) -> String? {
        let look = "look: \(formPalette.name) · \(formPalette.colorScheme == .dark ? "dark" : "light")"
        if !screen.contains(where: { $0.contains(look) }) {
            return "the page should say \"\(look)\""
        }
        if !screen.prefix(3).contains(where: { $0.contains("Themes · \(rootPalette.name)") }) {
            return "the header should name the app's palette, \(rootPalette.name)"
        }
        if board.saves != expectedSaves {
            return "\(board.saves) saves were made where the session made \(expectedSaves)"
        }
        return nil
    }

    func check(styled screen: [String], after index: Int) -> String? {
        let frame = ThemeFrame(
            lines: screen.map(\.stripped), cells: ScreenCells(screen), depth: depth, rootPalette: rootPalette,
            formPalette: formPalette, session: self)
        return depthProblem(frame) ?? pageProblem(frame) ?? retiredProblem(frame)
            ?? cursorProblem(frame, after: index)
            ?? ContrastPromise.all.lazy.compactMap { $0.problem(in: frame) }.first
    }

    /// The list's cursor, shown exactly while the list holds the focus: one
    /// row breathing — the accent on a selected row, the focus wash on any
    /// other — and none once the focus is elsewhere.
    ///
    /// Where the colours can be told apart: not at 16 colours, where the
    /// terminal chooses them, nor in a palette that leaves its page to the
    /// terminal; and not on the page's first frame — the opening frame, which
    /// the runner checks as step -1, hence `index >= 0` — whose status line
    /// reads a frame late the focus TUIkit gives out at the end of that pass. A
    /// selected row on the tint a selection rests in may be the cursor all the
    /// same: at 256 colours the accent's breath can land on the tint's entry
    /// (Basic, Ocean, Red Sands), and TUIkit promises today only that the
    /// breath keeps off the page and off its ● — a promise that the cursor on
    /// a selection stays apart from the selection's tint would go here.
    private func cursorProblem(_ frame: ThemeFrame, after index: Int) -> String? {
        guard index >= 0, depth != .basic16, let focus = frame.focus, frame.drawn(rootPalette.background) != nil else {
            return nil
        }
        var breathing: [Int] = []
        var maybe: [Int] = []
        for task in board.tasks {
            guard let (x, y) = frame.listTag(task.id) else { continue }
            switch frame.rowKind(task.id, at: y, before: x) {
            case .accentBreath, .washBreath: breathing.append(task.id)
            case .selectedTint: maybe.append(task.id)
            case .plain: break
            }
        }
        let rows = { (ids: [Int]) in ids.map { "#\($0)" }.joined(separator: ", ") }
        let look = "\(rootPalette.name) at \(depth)"
        if focus != "list", !breathing.isEmpty {
            return "the focus is on \(focus), and the list still shows its cursor on \(rows(breathing)) (\(look))"
        }
        if focus == "list", breathing.count > 1 {
            return "the list holds the focus, and \(breathing.count) rows show its cursor: \(rows(breathing)) (\(look))"
        }
        if focus == "list", breathing.isEmpty, maybe.isEmpty {
            return "the list holds the focus, and no row shows its cursor (\(look))"
        }
        return nil
    }

    /// A colour TUIkit computed, spelled for another depth: a 24-bit colour
    /// sent to a 256-colour terminal is one it cannot draw, and an index sent
    /// to a truecolour one is a colour quantised for a terminal that is not
    /// there. The page states no colour of its own by index, and its one named
    /// colour (a tint) is spelled by name at every depth.
    private func depthProblem(_ frame: ThemeFrame) -> String? {
        let expected = ColourSpelling.computed(at: depth)
        for spelling in [ColourSpelling.rgb, .indexed] where spelling != expected {
            guard let (row, column) = frame.cells.spellings[spelling] else { continue }
            return "at \(depth), a colour is spelled as \(spelling) at line \(row), column \(column): "
                + "\(frame.lines[row].trimmingCharacters(in: .whitespaces).prefix(60))"
        }
        return nil
    }

    /// The page's own field — a blank cell below the content — in the app's
    /// palette's background.
    private func pageProblem(_ frame: ThemeFrame) -> String? {
        guard let expected = frame.drawn(rootPalette.background),
            let y = frame.lines.lastIndex(where: { $0.hasPrefix("[") && $0.contains(" saved") }).map({ $0 - 1 }),
            frame.lines[y].allSatisfy({ $0 == " " }),
            let cell = frame.cells.cell(row: y, column: frame.lines[y].count - 1)
        else { return nil }
        guard ScreenCell.name(cell.background) == ScreenCell.name(expected) else {
            return "the page is \(ScreenCell.name(cell.background)) where \(rootPalette.name)'s background at \(depth) "
                + "is \(ScreenCell.name(expected))"
        }
        return nil
    }

    /// A cell still in a colour of a palette the page no longer uses: one of
    /// the retired palette's roles that no blend of the roles in use can make.
    ///
    /// TUIkit derives most of what it draws by blending two roles — a fill is
    /// the accent over the page, a fade the ink toward it — so a retired role
    /// that lies on a line between two roles in use (Pro's grey focus wash, and
    /// White's black page and grey ink) may be one the new look drew for itself.
    /// Only a colour off every such line is proof: Amber's orange on Green.
    private func retiredProblem(_ frame: ThemeFrame) -> String? {
        // In truecolour only: the cube quantises a blend onto whatever entry is
        // nearest, and one of those is some other palette's role often enough
        // (a row of Novel's list drew #5f5f00, Man Page's tertiary there) that a match
        // there proves nothing. The twin and the spelling check hold 256 colours.
        guard !retired.isEmpty, depth == .truecolor else { return nil }
        let tolerance = 10.0
        func roles(_ palette: any Palette) -> [(String, Color)] {
            [
                ("background", palette.background), ("foreground", palette.foreground),
                ("secondary", palette.foregroundSecondary), ("tertiary", palette.foregroundTertiary),
                ("accent", palette.accent), ("border", palette.border),
                ("app header", palette.appHeaderBackground), ("status bar", palette.statusBarBackground),
                ("focus", palette.focusBackground), ("field", palette.fieldBackground),
            ].compactMap { role, colour in frame.drawn(colour).map { (role, $0) } }
        }
        let inUse = palettesInUse.flatMap { roles($0).map(\.1) } + [board.tint].compactMap { $0.flatMap(frame.drawn) }
        var stale: [String: String] = [:]
        for palette in retired {
            for (role, colour) in roles(palette) where !ThemeFrame.blends(colour, of: inUse, within: tolerance) {
                stale[ScreenCell.name(colour)] = "\(palette.name)'s \(role)"
            }
        }
        guard !stale.isEmpty else { return nil }
        for (y, row) in frame.cells.rows.enumerated() {
            for (x, cell) in row.enumerated() {
                for (slot, colour) in [("ink", cell.hasInk ? cell.foreground : nil), ("field", cell.background)] {
                    if let colour, let what = stale[ScreenCell.name(colour)] {
                        let glyph = cell.character.map(String.init) ?? " "
                        return "line \(y), column \(x) (\"\(glyph)\")'s \(slot) is "
                            + "still in \(what), \(ScreenCell.name(colour)), after the look changed to "
                            + "\(palettesInUse.map(\.name).joined(separator: ", ")): "
                            + "\(frame.lines[y].trimmingCharacters(in: .whitespaces).prefix(60))"
                    }
                }
            }
        }
        return nil
    }
}
