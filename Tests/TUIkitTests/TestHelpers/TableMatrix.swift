//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableMatrix.swift
//
//  One `Table` fixture for the whole target, and the frame driver that renders
//  it the way a run loop does.
//
//  Table has about twenty-five configuration axes and roughly a hundred and
//  sixty tests, and every one of those tests builds its own table by hand —
//  three one-letter rows here, five files there, a `Binding.constant(nil)`
//  everywhere. That is why the suite pins what a table draws ONCE and almost
//  nothing about what it draws TWICE: a fixture that renders a single frame
//  cannot be asked whether the second frame agreed with it, and there was no
//  shared place to put the question.
//
//  So this is deliberately not another table. It is a POINT IN THE SPACE plus a
//  frame driver, and what it exists to make cheap is the family of assertions
//  nothing in the target could make before:
//
//  * the same data renders the same BYTES on the next frame (ANSI included —
//    every existing Table assertion compares `.stripped` text, which cannot see
//    a row that came back stale or re-coloured);
//  * a warm cache draws what a cold one draws;
//  * changing ONE row of many changes that row's lines and no others;
//  * each column's value closure runs exactly once per drawn row per frame —
//    an invariant `renderRow` states in its own comment and nothing checked.
//
//  Those are the properties a per-row cache would have to keep, and they are
//  worth holding whether or not one is ever built.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - The row

/// The fixture's row type: an id, and a generation that a mutation bumps.
///
/// `Equatable` on purpose — `Table` requires only `Identifiable`, and the
/// difference decides whether a value memo may key on the row at all, so the
/// fixture offers both (see ``TableMatrixOpaqueRow``).
struct TableMatrixRow: Identifiable, Sendable, Equatable {
    let id: Int
    /// Bumped to make this row — and only this row — different content.
    var generation: Int = 0

    // The same five cell shapes as ``TableCellCost``, reachable by KEY PATH.
    //
    // A column built from one of these names its value; a column built from a
    // closure computes it. That distinction decides whether a `Table` may keep
    // its rows across frames at all — a key path has no closure context and so
    // cannot capture anything the row does not carry — so the fixture has to be
    // able to build both, or it can only ever test one of the two behaviours.
    var cheapText: String { TableCellCost.cheap.text(id: id, generation: generation) }
    var formattedText: String { TableCellCost.formatted.text(id: id, generation: generation) }
    var styledText: String { TableCellCost.styled.text(id: id, generation: generation) }
    var wideText: String { TableCellCost.wide.text(id: id, generation: generation) }
    var overlongText: String { TableCellCost.overlong.text(id: id, generation: generation) }
}

extension TableCellCost {
    /// The key path that names this shape on a row, for a column that may be
    /// memoised.
    var keyPath: KeyPath<TableMatrixRow, String> & Sendable {
        switch self {
        case .cheap: \TableMatrixRow.cheapText
        case .formatted: \TableMatrixRow.formattedText
        case .styled: \TableMatrixRow.styledText
        case .wide: \TableMatrixRow.wideText
        case .overlong: \TableMatrixRow.overlongText
        }
    }
}

/// The same row with no `Equatable` conformance, for the cases that have to
/// hold when the row type cannot be compared.
struct TableMatrixOpaqueRow: Identifiable, Sendable {
    let id: Int
    var generation: Int = 0
}

// MARK: - The axes

/// How expensive one cell is to produce.
///
/// The axis that decides what a row cache could ever be worth: its saving is
/// (rows served) × (cost of a row), and every Table fixture and Stress scenario
/// in the repository sits at `.cheap`. A memo that pays for itself on
/// `.formatted` may be invisible on `.cheap`, and a measurement that only ever
/// sees one of them cannot say which.
enum TableCellCost: Sendable, CaseIterable {
    /// An interpolated integer. What every existing fixture does.
    case cheap
    /// Words joined from a table, the shape a display string usually has.
    case formatted
    /// The same, wrapped in SGR — a cell the byte-wise clip has to decline.
    case styled
    /// CJK and emoji, so the width rules run per cluster.
    case wide
    /// Long enough that the column must truncate it.
    case overlong

    /// The cell's text for a row, deterministic in `(id, generation)`.
    func text(id: Int, generation: Int) -> String {
        let hash = TableMatrixShape.mix(UInt64(bitPattern: Int64(id &* 2_654_435_761 &+ generation)))
        switch self {
        case .cheap:
            return "\(id).\(generation)"
        case .formatted:
            return Self.words(hash, count: 2)
        case .styled:
            return "\u{1B}[3\(hash % 6 + 1)m\(Self.words(hash, count: 2))\u{1B}[0m"
        case .wide:
            return "\(Self.wideGlyphs[Int(hash % UInt64(Self.wideGlyphs.count))]) \(id)"
        case .overlong:
            return Self.words(hash, count: 14)
        }
    }

    private static let vocabulary = [
        "harbor", "cipher", "lattice", "ember", "vector", "glyph", "fjord", "comet",
        "molten", "frozen", "hidden", "gilded", "fractal", "quantum", "stellar", "terse",
    ]

    private static let wideGlyphs = ["日本語", "한국어", "👋🏽", "👨‍👩‍👧‍👦", "❤️", "🇬🇧"]

    private static func words(_ hash: UInt64, count: Int) -> String {
        var value = hash
        var parts: [String] = []
        parts.reserveCapacity(count)
        for _ in 0..<count {
            value = TableMatrixShape.mix(value)
            parts.append(vocabulary[Int(value % UInt64(vocabulary.count))])
        }
        return parts.joined(separator: " ")
    }
}

/// One column of the fixture.
struct TableMatrixColumn: Sendable {
    var title: String
    var width: ColumnWidth = .flexible
    var lineLimit: Int = 1
    var truncation: TruncationMode = .tail
    var alignment: HorizontalAlignment = .leading
    var cost: TableCellCost = .cheap
    /// Whether the column NAMES its value (a key path) or computes one (a
    /// closure). Closures are the default because they are what the fixture's
    /// call counter needs; a key-path column is counted by the framework's own
    /// `RenderCache.rowWork.cellValues` instead.
    var namesAProperty: Bool = false
}

/// What a table is bound to, which changes both the gutter and what a row draws.
enum TableMatrixSelection: Sendable {
    case unbound
    case single(Int?)
    case multi(Set<Int>)
}

/// One point in `Table`'s configuration space.
struct TableMatrixShape: Sendable {
    var rows: Int = 24
    var columns: [TableMatrixColumn] = [
        TableMatrixColumn(title: "ID", width: .fixed(5), cost: .cheap),
        TableMatrixColumn(title: "Name", cost: .formatted),
    ]
    var selection: TableMatrixSelection = .unbound
    var width: Int = 48
    var height: Int = 14
    /// Which scroll-extent mode the table renders under. `.exact` is never
    /// cached by the estimator, so it is the control for the below-the-limit
    /// path that now is.
    var precision: ScrollExtentPrecision = .approximate

    /// Whether any column wraps, which is the single predicate that sends the
    /// whole table down its variable-height row composer instead of the
    /// single-line one. Named here so a test can say which path it is on.
    var isMultiLine: Bool { columns.contains { $0.lineLimit > 1 } }

    /// A stable per-(id, generation) hash. The fixture's content must not move
    /// between runs, or a byte comparison across frames proves nothing.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// One named point in the space, so a parameterised failure says which.
struct TableMatrixCase: Sendable, CustomTestStringConvertible {
    let name: String
    let shape: TableMatrixShape
    var testDescription: String { name }
}

extension TableMatrixShape {
    /// A representative sweep rather than the full cross product.
    ///
    /// Twenty-five axes do not fit in a test matrix, so this picks the ones that
    /// reach a row's BYTES and varies them one at a time against a common base:
    /// the five cell costs, the four column-width modes, the three selection
    /// bindings, and the single predicate — any column with `lineLimit > 1` —
    /// that sends the table down its other row composer entirely.
    static var sweep: [TableMatrixCase] {
        func base(_ columns: [TableMatrixColumn]) -> TableMatrixShape {
            TableMatrixShape(rows: 40, columns: columns)
        }
        var cases: [TableMatrixCase] = []

        for cost in TableCellCost.allCases {
            cases.append(
                TableMatrixCase(
                    name: "cost=\(cost)",
                    shape: base([
                        TableMatrixColumn(title: "ID", width: .fixed(5), cost: .cheap),
                        TableMatrixColumn(title: "Value", cost: cost),
                    ])))
        }
        for (label, width) in [
            ("flexible", ColumnWidth.flexible), ("fixed", .fixed(12)),
            ("ratio", .ratio(0.4)), ("fit", .fit),
        ] {
            cases.append(
                TableMatrixCase(
                    name: "width=\(label)",
                    shape: base([
                        TableMatrixColumn(title: "Value", width: width, cost: .formatted),
                        TableMatrixColumn(title: "Tail", cost: .cheap),
                    ])))
        }
        for (label, selection) in [
            ("unbound", TableMatrixSelection.unbound), ("single", .single(3)),
            ("single-none", .single(nil)), ("multi", .multi([1, 4, 5])),
        ] {
            var shape = base([
                TableMatrixColumn(title: "ID", width: .fixed(5), cost: .cheap),
                TableMatrixColumn(title: "Value", cost: .formatted),
            ])
            shape.selection = selection
            cases.append(TableMatrixCase(name: "selection=\(label)", shape: shape))
        }
        for limit in [2, 3] {
            cases.append(
                TableMatrixCase(
                    name: "lineLimit=\(limit)",
                    shape: base([
                        TableMatrixColumn(title: "ID", width: .fixed(5), cost: .cheap),
                        TableMatrixColumn(title: "Body", lineLimit: limit, cost: .overlong),
                    ])))
        }
        for (label, mode) in [
            ("tail", TruncationMode.tail), ("head", .head), ("middle", .middle),
        ] {
            cases.append(
                TableMatrixCase(
                    name: "truncation=\(label)",
                    shape: base([
                        TableMatrixColumn(
                            title: "Body", width: .fixed(14), truncation: mode, cost: .overlong),
                        TableMatrixColumn(title: "Tail", cost: .cheap),
                    ])))
        }
        for (label, alignment) in [
            ("leading", HorizontalAlignment.leading), ("center", .center), ("trailing", .trailing),
        ] {
            cases.append(
                TableMatrixCase(
                    name: "alignment=\(label)",
                    shape: base([
                        TableMatrixColumn(title: "ID", width: .fixed(8), alignment: alignment),
                        TableMatrixColumn(title: "Value", alignment: alignment, cost: .formatted),
                    ])))
        }
        // Narrow enough that every column truncates, and tall enough that the
        // window is a small slice of the data — the shape the owner named.
        cases.append(
            TableMatrixCase(
                name: "narrow-and-long",
                shape: TableMatrixShape(
                    rows: 600,
                    columns: [
                        TableMatrixColumn(title: "A", cost: .overlong),
                        TableMatrixColumn(title: "B", cost: .styled),
                        TableMatrixColumn(title: "C", cost: .wide),
                    ],
                    width: 36, height: 10)))
        return cases
    }
}

// MARK: - Counting what a frame did

/// How many times a cell value closure ran, and for which rows.
///
/// A counter rather than a clock: "this frame produced no cell values for the
/// rows it did not change" is a claim a stopwatch cannot make and a count makes
/// exactly. `final class` so the `@Sendable` column closures can share one.
final class TableCellCalls: @unchecked Sendable {
    private(set) var total = 0
    private(set) var perRow: [Int: Int] = [:]

    func note(row id: Int) {
        total += 1
        perRow[id, default: 0] += 1
    }

    func reset() {
        total = 0
        perRow.removeAll(keepingCapacity: true)
    }
}

// MARK: - The harness

/// Renders one shape frame after frame through a single `TUIContext`, the way
/// the run loop does.
///
/// The pass lifecycle is the point. A render that does not bracket itself in
/// `beginRenderPass` / `endRenderPass` never applies the `@State` writes the
/// previous frame enqueued, so a fixture without it cannot see a table settle —
/// and settling is where every cross-frame question starts. Three frames, not
/// two: a `Table` builds its own `@State` while rendering the first, that write
/// invalidates its subtree, the cache applies it at the start of the second, and
/// the third is the first frame that can be served from anything.
@MainActor
final class TableMatrixHarness {
    let shape: TableMatrixShape
    let calls = TableCellCalls()
    private(set) var rows: [TableMatrixRow]
    private let tui = TUIContext()
    /// ONE focus manager for the harness's whole life, not one per frame.
    ///
    /// A fresh instance each frame is a changed environment value, and an
    /// applied environment change clears the subtree below it
    /// (`Environment.noteAppliedEnvironment` → `clearAffected(by:)`). A fixture
    /// that rebuilds it every frame therefore measures a table whose cache is
    /// wiped before every render — which is indistinguishable from a memo that
    /// does not work, and is how the first version of this file "showed" the
    /// `.fit` column memo never serving.
    private let focusManager = FocusManager()
    private var singleSelection: Int?
    private var multiSelection: Set<Int>

    /// How many frames a table needs before a cross-frame question is fair.
    static let framesToSettle = 3

    init(_ shape: TableMatrixShape = TableMatrixShape()) {
        self.shape = shape
        self.rows = (0..<shape.rows).map { TableMatrixRow(id: $0) }
        switch shape.selection {
        case .unbound:
            singleSelection = nil
            multiSelection = []
        case .single(let id):
            singleSelection = id
            multiSelection = []
        case .multi(let ids):
            singleSelection = nil
            multiSelection = ids
        }
    }

    /// Which rows a frame drew, in order, read back off the picture.
    ///
    /// Only meaningful for a shape whose first column is ``TableCellCost/cheap``
    /// — that cell is `"<id>.<generation>"`, so the drawn window can be
    /// recovered from the bytes rather than from the handler's internal state.
    /// Reading it from the FRAME is the point: a memo that served the wrong row
    /// would be invisible to a question asked of the scroll offset.
    static func drawnRowIDs(in buffer: FrameBuffer) -> [Int] {
        buffer.lines.compactMap { line in
            // The first `<int>.<int>` field on the line. Not simply the first
            // field: every line opens with the container's border glyph, and a
            // row also opens with the selection gutter when it has one.
            for field in line.stripped.split(separator: " ", omittingEmptySubsequences: true) {
                guard let dot = field.firstIndex(of: "."),
                    let id = Int(field[field.startIndex..<dot]),
                    Int(field[field.index(after: dot)...]) != nil
                else { continue }
                return id
            }
            return nil
        }
    }

    /// What this frame's rows cost: composed, served, and calls into the
    /// fixture's own cell closures. Read from the cache the harness owns, so it
    /// is this table's number and nobody else's.
    var rowWork: RenderCache.RowWork { tui.renderCache.rowWork }

    /// What the render-memo verifier found, when it is on.
    var renderCacheMismatches: [String] { tui.renderCache.renderMemoMismatches }

    /// Gives one row new content, leaving every other row's bytes alone.
    func mutate(rowAt index: Int) {
        rows[index].generation += 1
    }

    /// Moves the selection without touching the data.
    ///
    /// The case a memo keyed on the row VALUE alone would get wrong: two rows'
    /// bytes change — the one that gained the mark and background, and the one
    /// that lost them — while both rows compare exactly equal to what they were.
    /// Whatever a `Table` learns to keep, this has to keep working.
    func select(_ id: Int?) {
        singleSelection = id
        if let id { multiSelection = [id] } else { multiSelection = [] }
    }

    /// Renders one frame. `coldCache` empties the cache first, which is how a
    /// warm answer is compared with the answer nothing could have served.
    @discardableResult
    func frame(coldCache: Bool = false) -> FrameBuffer {
        if coldCache { tui.renderCache.clearAll() }
        calls.reset()
        tui.renderCache.rowWork = RenderCache.RowWork()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.scrollExtentPrecision = shape.precision
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: shape.width, availableHeight: shape.height,
            environment: environment, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view(), context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer
    }

    /// Walks the cursor down `times` rows, the way a key press does.
    ///
    /// Through the focus manager rather than by writing `scrollOffset`: moving
    /// the window is a reveal driven by the cursor, and a fixture that set the
    /// offset directly would skip the arithmetic that decides where the window
    /// lands — which is the part a row memo has to keep working.
    func pressDown(_ times: Int = 1) {
        for _ in 0..<times { _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down)) }
    }

    /// Renders until the table has settled, and answers the last frame.
    @discardableResult
    func settle() -> FrameBuffer {
        var last = FrameBuffer(lines: [])
        for _ in 0..<Self.framesToSettle { last = frame() }
        return last
    }

    // MARK: Building the view

    private func columns() -> [TableColumn<TableMatrixRow>] {
        shape.columns.map { spec in
            let calls = self.calls
            let column =
                spec.namesAProperty
                ? TableColumn<TableMatrixRow>(spec.title, value: spec.cost.keyPath)
                : TableColumn<TableMatrixRow>(spec.title) { (row: TableMatrixRow) -> String in
                    calls.note(row: row.id)
                    return spec.cost.text(id: row.id, generation: row.generation)
                }
            return column
            .width(spec.width)
            .lineLimit(spec.lineLimit)
            .truncationMode(spec.truncation)
            .alignment(spec.alignment)
        }
    }

    private func view() -> AnyView {
        let columns = self.columns()
        switch shape.selection {
        case .unbound:
            return AnyView(Table(rows) { columns })
        case .single:
            let binding = Binding<Int?>(
                get: { self.singleSelection }, set: { self.singleSelection = $0 })
            return AnyView(Table(rows, selection: binding) { columns })
        case .multi:
            let binding = Binding<Set<Int>>(
                get: { self.multiSelection }, set: { self.multiSelection = $0 })
            return AnyView(Table(rows, selection: binding) { columns })
        }
    }
}
