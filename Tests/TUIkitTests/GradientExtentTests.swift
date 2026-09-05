//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientExtentTests.swift
//
//  `.gradientExtent(.subtree)` — the TUI-specific half. SwiftUI has no way to
//  say "span this set of controls" (measured: `ShapeStyle.in(_:)` re-anchors at
//  every leaf, and the mask idiom costs the content's interactivity), so this
//  is an addition and it needs its own evidence.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Gradient extent")
struct GradientExtentTests {

    private let red = Color.rgb(255, 0, 0)
    private let blue = Color.rgb(0, 0, 255)

    private func context(width: Int = 40, height: Int = 10) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    /// The truecolor ink of each visible cell of a line, `nil` where none —
    /// the shared `truecolorInks`, kept under its short name here.
    private func inks(_ line: String) -> [String?] { truecolorInks(line) }

    private func firstInk(_ line: String) -> String? { inks(line).compactMap { $0 }.first }

    /// The ink at a visible COLUMN — see `truecolorInk(_:atColumn:)` for why
    /// cells are counted rather than escape runs.
    private func ink(_ line: String, atColumn wanted: Int) -> String? {
        truecolorInk(line, atColumn: wanted)
    }

    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
    }

    private static let rows = (0..<4).map { Row(id: $0, name: "row\($0)") }

    private func vertical() -> LinearGradient {
        LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom)
    }

    private func horizontal() -> LinearGradient {
        LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - The feature

    /// The headline, and the one the request asked for: first row red, last row
    /// blue, with every row a step along the way — rather than each row running
    /// the whole ramp inside itself.
    @Test("A vertical ramp spans the rows of a stack")
    func verticalSpansRows() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines

        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        #expect(rows[3] == "0;0;255", "the last row is not the ramp's end: \(rows)")
        #expect(Set(rows.compactMap { $0 }).count == 4, "rows repeat: \(rows)")
    }

    /// Without the modifier the same tree is SwiftUI's meaning: every leaf runs
    /// the whole ramp inside itself, so a one-row leaf takes the midpoint and
    /// they all look alike.
    @Test("Without it, each row runs its own ramp — the default is unchanged")
    func leafExtentIsTheDefault() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical()),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "the default spanned the stack: \(rows)")
    }

    /// `.leaf` put back inside a `.subtree` returns to per-leaf resolution — the
    /// modifier is a scope, not a switch thrown once.
    @Test("An inner .leaf overrides an outer .subtree")
    func innerLeafOverrides() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .gradientExtent(.leaf)
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "\(rows)")
    }

    /// The horizontal half, through an `HStack`, whose own axis is the one it
    /// distributes — so this is the exact case rather than the predicted one.
    @Test("A horizontal ramp spans the columns of a row")
    func horizontalSpansColumns() {
        let lines = renderToBuffer(
            HStack(spacing: 0) {
                Text(verbatim: "AA")
                Text(verbatim: "BB")
                Text(verbatim: "CC")
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let cells = inks(lines[0]).compactMap { $0 }
        #expect(cells.count == 6, "\(cells)")
        #expect(cells.first == "255;0;0")
        #expect(cells.last == "0;0;255")
        // Monotone across the whole row: each column is further along than the
        // one before it, which is what "one ramp" means.
        let blues = cells.map { Int($0.split(separator: ";").last ?? "0") ?? 0 }
        #expect(blues == blues.sorted(), "the ramp did not run left to right: \(blues)")
    }

    /// A leaf still resolves over the EXTENT, not its own box, so a short leaf
    /// at the far end takes the far end's colour rather than the whole ramp.
    @Test("A short leaf takes its own slice of the extent, not the whole ramp")
    func shortLeafTakesItsSlice() {
        let lines = renderToBuffer(
            HStack(spacing: 0) {
                Text(verbatim: "AAAAAA")
                Text(verbatim: "B")
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let cells = inks(lines[0]).compactMap { $0 }
        #expect(cells.count == 7, "\(cells)")
        #expect(cells.last == "0;0;255", "the last cell is not the ramp's end")
        #expect(cells[5] != "0;0;255", "the wide leaf reached the end on its own")
    }

    // MARK: - Nothing when unused

    @Test("A context with no subtree gradient carries no frame")
    func noFrameWhenUnused() {
        var seen: GradientFrame??
        _ = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                _FrameProbe { seen = $0 }
            },
            context: context())
        #expect(seen == .some(nil), "a frame was published with no .gradientExtent in force")
    }
}

// MARK: - `.in(_:)`, the other half

extension GradientExtentTests {

    /// SwiftUI's own extent knob fixes the ramp's SCALE: four cells of a ramp
    /// told to run over forty only get the first tenth of it, so a text that
    /// would have ended blue ends barely off red.
    @Test("`.in(_:)` resolves over the size it names, not the leaf's own")
    func fixedExtentRescalesTheRamp() {
        let plain = renderToBuffer(
            Text(verbatim: "AAAA").foregroundStyle(horizontal()), context: context()
        ).lines[0]
        let scaled = renderToBuffer(
            Text(verbatim: "AAAA")
                .foregroundStyle(horizontal().in(CellRect(x: 0, y: 0, width: 40, height: 1))),
            context: context()
        ).lines[0]

        #expect(inks(plain).compactMap { $0 }.last == "0;0;255", "four cells, the whole ramp")
        let end = inks(scaled).compactMap { $0 }.last
        #expect(end != "0;0;255", "the ramp was not rescaled: \(String(describing: end))")
        let red = end.flatMap { Int($0.split(separator: ";")[0]) } ?? 0
        #expect(red > 200, "four cells of forty should still be red: \(String(describing: end))")
    }

    /// And it fixes ONLY the scale. Each leaf still anchors the ramp at
    /// itself, so four rows told to resolve over eight all take the same early
    /// slice — measured in SwiftUI, and the reason `.in(_:)` cannot express
    /// "one ramp across a set" however tempting it looks.
    @Test("`.in(_:)` re-anchors at every leaf, so it cannot span a set")
    func fixedExtentReAnchorsPerLeaf() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical().in(CellRect(x: 0, y: 0, width: 4, height: 8))),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "rows differ, so it anchored once: \(rows)")
        // And it did something: a bare one-row leaf takes the ramp's far end,
        // where a row of eight takes its start.
        #expect(rows[0] != "0;0;255", "the rescaling did not happen: \(rows)")
    }

    /// Two knobs, one question, so the order has to be stated: `.in(_:)` names
    /// the rectangle outright, and outright wins.
    @Test("`.in(_:)` overrides an enclosing .gradientExtent(.subtree)")
    func fixedExtentBeatsSubtree() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical().in(CellRect(x: 0, y: 0, width: 4, height: 8)))
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "the subtree extent won: \(rows)")
    }

    // MARK: - Lazy stacks

    /// A `LazyVStack` is the same core as `VStack` under a different overflow
    /// policy, but a different render path — one that renders as it walks, so
    /// it cannot learn its own extent on the way and has to measure the rows
    /// that will fit before it starts. It got no ramp at all until it did.
    @Test("A vertical ramp spans the rows of a LazyVStack")
    func lazyVerticalSpansRows() {
        let lines = renderToBuffer(
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines

        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        #expect(rows[3] == "0;0;255", "the last row is not the ramp's end: \(rows)")
        #expect(Set(rows.compactMap { $0 }).count == 4, "rows repeat: \(rows)")
    }

    /// The horizontal twin, through `LazyHStack`'s own append-while-it-fits
    /// walk.
    @Test("A horizontal ramp spans the columns of a LazyHStack")
    func lazyHorizontalSpansColumns() {
        let lines = renderToBuffer(
            LazyHStack(spacing: 0) {
                Text(verbatim: "AA")
                Text(verbatim: "BB")
                Text(verbatim: "CC")
                Text(verbatim: "DD")
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let cells = inks(lines[0]).prefix(8).compactMap { $0 }
        #expect(cells.first == "255;0;0", "the first column is not the start: \(cells)")
        #expect(cells.last == "0;0;255", "the last column is not the end: \(cells)")
    }

    /// The rule a scrolling list needs: the ramp spans the CONTENT, not the
    /// viewport. Ten rows of forty are on screen, so they take the first
    /// quarter of the ramp — a row keeps its colour as it scrolls rather than
    /// the whole column re-inking under a ramp pinned to the screen.
    @Test("A ramp over scrolling content spans the content, not the window")
    func lazyRampSpansContentNotViewport() {
        let lines = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { index in
                        Text(verbatim: "row \(index)")
                    }
                }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context(height: 10)
        ).lines

        let rows = lines.prefix(10).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        // Row 9 of 40 is a quarter of the way down a red→blue ramp: still
        // mostly red. Pinned to the viewport it would be full blue.
        let last = rows[9]?.split(separator: ";").compactMap { Int($0) }
        #expect(last?.count == 3, "no ink on the last visible row: \(rows)")
        if let last, last.count == 3 {
            #expect(last[0] > last[2], "the window took the whole ramp: \(rows)")
            #expect(last[0] < 255, "the ramp did not advance down the window: \(rows)")
        }
        #expect(Set(rows.compactMap { $0 }).count > 1, "rows repeat: \(rows)")
    }

    /// Variable-height rows in a scroll window take the exact slot walk rather
    /// than the arithmetic seek — a third render path, with its own idea of
    /// where each row is, and the ramp has to agree with it.
    @Test("A ramp spans content the exact slot walk places")
    func lazyRampAcrossExactWalk() {
        let lines = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "AAAA")
                    Text(verbatim: "BBBB")
                    Text(verbatim: "CCCC")
                    Text(verbatim: "DDDD")
                }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context(height: 4)
        ).lines

        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        #expect(rows[3] == "0;0;255", "the last row is not the ramp's end: \(rows)")
        #expect(Set(rows.compactMap { $0 }).count == 4, "rows repeat: \(rows)")
    }

    /// Past the anchored threshold with variable-height rows, the stack stops
    /// walking the content at all and works outward from an anchor on
    /// estimates. The ramp is estimated with it — approximate by construction,
    /// and required to still start at the start and advance downward.
    @Test("A ramp over anchored content advances from the top")
    func lazyRampAcrossAnchoredWalk() {
        let lines = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<300, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "row \(index)")
                            if index.isMultiple(of: 2) { Text(verbatim: "more") }
                        }
                    }
                }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context(height: 8)
        ).lines

        let rows = lines.prefix(8).compactMap { firstInk($0) }
        #expect(rows.first == "255;0;0", "the first row is not the ramp's start: \(rows)")
        // Eight lines of three hundred rows: a sliver at the very top of the
        // ramp, so every visible row is red-dominant and none is the end.
        for row in rows {
            let channels = row.split(separator: ";").compactMap { Int($0) }
            #expect(channels.count == 3, "malformed ink \(row)")
            if channels.count == 3 {
                #expect(channels[0] > channels[2], "the ramp ran to its end on screen: \(rows)")
            }
        }
    }

    // MARK: - List, and everything that lays out by placement

    /// The ink of the first *content* cell on a line — past a bordered
    /// container's own border glyph, which is the palette's and not the ramp's.
    private func rowInk(_ line: String) -> String? {
        inks(line).compactMap { $0 }.dropFirst().first
    }

    /// The case the whole feature was asked for: one ramp down the rows of a
    /// `List`. Every row came out the ramp's first colour before, because
    /// `List` never told its rows where they were.
    @Test("A vertical ramp spans the rows of a List")
    func listSpansRows() {
        let lines = renderToBuffer(
            List {
                ForEach(["a", "b", "c", "d"], id: \.self) { Text(verbatim: $0) }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.dropFirst().prefix(4).map { rowInk($0) }
        #expect(
            rows == ["255;0;0", "170;0;85", "85;0;170", "0;0;255"],
            "the ramp did not span the rows: \(rows)")
    }

    /// The static spelling renders its rows during extraction rather than
    /// through a deferred box, so it is a second code path to the same picture.
    @Test("A ramp spans the rows of a List written out row by row")
    func listOfStaticRowsSpansRows() {
        let lines = renderToBuffer(
            List {
                Text(verbatim: "a")
                Text(verbatim: "b")
                Text(verbatim: "c")
                Text(verbatim: "d")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.dropFirst().prefix(4).map { rowInk($0) }
        #expect(
            rows == ["255;0;0", "170;0;85", "85;0;170", "0;0;255"],
            "the ramp did not span the rows: \(rows)")
    }

    /// A list's rows render on demand, so it seeds its ramp from row 0's
    /// MEASURED height and steps by that pitch. Two-line rows therefore occupy
    /// two lines of the ramp each — the same picture the equivalent stack
    /// draws — rather than one step per row, which would run the ramp out
    /// halfway down.
    @Test("A List of two-line rows steps by lines, not by rows")
    func listStepsByItsRowHeight() {
        let lines = renderToBuffer(
            List {
                ForEach(["a", "b"], id: \.self) { name in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: name)
                        Text(verbatim: name + "2")
                    }
                }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.dropFirst().prefix(4).map { rowInk($0) }
        // Four lines of ramp over two two-line rows: the ends are the ends, and
        // every line is its own step.
        #expect(rows[0] == "255;0;0", "\(rows)")
        #expect(rows[3] == "0;0;255", "\(rows)")
        #expect(Set(rows.compactMap { $0 }).count == 4, "lines repeat: \(rows)")
    }

    /// Every `Layout`-based container places its subviews through one funnel.
    /// This pins the lazy-grid end of it; `AnyLayout` has its own test, and
    /// `Grid` — which is NOT a `Layout` — has two, because arguing from this
    /// one that it must be covered too is precisely what left it broken.
    @Test("A vertical ramp spans the rows of a lazy grid")
    func gridSpansRows() {
        let lines = renderToBuffer(
            LazyVGrid(columns: [GridItem(), GridItem()]) {
                ForEach(["a", "b", "c", "d"], id: \.self) { Text(verbatim: $0) }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(2).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first grid row is not the start: \(rows)")
        #expect(rows[1] == "0;0;255", "the last grid row is not the end: \(rows)")
    }

    /// `Grid` is the one container that places children two-dimensionally
    /// without being a `Layout` — a lattice is not something `LayoutSubviews`
    /// can describe — so it does NOT inherit `_LayoutCore`'s answer, and used
    /// not to give one: every row of a three-row grid painted the ramp's first
    /// colour. The doc comment on ``View/gradientExtent(_:)`` named `Grid` as
    /// covered while `Grid.swift` contained no mention of a gradient at all.
    @Test("A vertical ramp spans the rows of a Grid")
    func gridProperSpansRows() {
        let lines = renderToBuffer(
            Grid(horizontalSpacing: 1, verticalSpacing: 0) {
                GridRow { Text(verbatim: "a") }
                GridRow { Text(verbatim: "b") }
                GridRow { Text(verbatim: "c") }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(3).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first grid row is not the start: \(rows)")
        #expect(rows[1] == "128;0;128", "the middle grid row is not the middle: \(rows)")
        #expect(rows[2] == "0;0;255", "the last grid row is not the end: \(rows)")
    }

    /// The other axis, and the column origins that carry it.
    @Test("A horizontal ramp spans the columns of a Grid")
    func gridSpansColumns() {
        let lines = renderToBuffer(
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Text(verbatim: "aaaa")
                    Text(verbatim: "bbbb")
                }
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let line = lines.first ?? ""
        #expect(ink(line, atColumn: 0) == "255;0;0", "the left cell is not the start: \(line.debugDescription)")
        #expect(
            ink(line, atColumn: 7) == "0;0;255",
            "the right cell does not reach the end: \(line.debugDescription)")
    }

    /// `AnyLayout` and `LazyHGrid` reach the ramp through `_LayoutCore`, which
    /// the survey claims covers "any `Layout` an app writes for itself" — the
    /// claim was only ever pinned through `LazyVGrid`.
    @Test("A vertical ramp spans the rows of an AnyLayout")
    func anyLayoutSpansRows() {
        let lines = renderToBuffer(
            AnyLayout(VStackLayout(spacing: 0)) {
                Text(verbatim: "a")
                Text(verbatim: "b")
                Text(verbatim: "c")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(3).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "\(rows)")
        #expect(rows[2] == "0;0;255", "\(rows)")
    }

    // MARK: - Table

    /// A `Table` paints its own cells — its columns yield strings, not views —
    /// so the ramp has to reach them through the table rather than through
    /// anything inside a row. It used to collapse a gradient to one colour for
    /// every row.
    @Test("A vertical ramp spans the rows of a Table")
    func tableSpansRows() {
        let lines = renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \.name) }
                .foregroundStyle(vertical())
                .gradientExtent(.subtree),
            context: context()
        ).lines
        // Border, header, then the four rows.
        let cells = lines.dropFirst(2).prefix(4).map { ink($0, atColumn: 4) }
        #expect(
            cells == ["255;0;0", "170;0;85", "85;0;170", "0;0;255"],
            "the ramp did not span the rows: \(cells)")
    }

    /// …and without the modifier too: a `Table` is ONE leaf, so its own rows
    /// are the extent either way. `.gradientExtent(.subtree)` changes nothing
    /// here, which is worth pinning — it is the only container of which that is
    /// true.
    @Test("A Table spans its rows with or without the subtree extent")
    func tableIsItsOwnExtent() {
        let withModifier = renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \.name) }
                .foregroundStyle(vertical())
                .gradientExtent(.subtree),
            context: context()
        ).lines
        let without = renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \.name) }
                .foregroundStyle(vertical()),
            context: context()
        ).lines
        #expect(withModifier == without, "the two differ")
    }

    /// A ramp that varies ALONG the row cannot be one colour per row, so the
    /// cells band — through the same per-cell walk `Text` uses.
    @Test("A horizontal ramp bands across a Table's cells")
    func tableBandsAcrossCells() {
        let lines = renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \.name) }
                .foregroundStyle(horizontal()),
            context: context()
        ).lines
        let row = lines.dropFirst(2).first ?? ""
        let cells = (4...12).compactMap { ink(row, atColumn: $0) }
        #expect(cells.count == 9, "not every cell is inked: \(cells)")
        #expect(Set(cells).count == cells.count, "the row took one colour: \(cells)")
        // Left to right, red draining into blue.
        let reds = cells.compactMap { Int($0.split(separator: ";").first ?? "") }
        #expect(reds == reds.sorted(by: >), "the ramp did not run leftward-first: \(cells)")
        // …and every row is the same, a horizontal ramp having no row term.
        let second = (4...12).compactMap { ink(lines.dropFirst(3).first ?? "", atColumn: $0) }
        #expect(second == cells, "the rows disagree: \(cells) vs \(second)")
    }

    /// The flat path is the one every table without a gradient takes, and it
    /// must be exactly what it was: one SGR introducer for the whole row.
    @Test("A plain colour still gives a Table one run per row")
    func tablePlainColourIsOneRun() {
        let lines = renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \.name) }
                .foregroundStyle(Color.rgb(9, 9, 9)),
            context: context()
        ).lines
        let row = lines.dropFirst(2).first ?? ""
        #expect(ink(row, atColumn: 4) == "9;9;9", "\(row.debugDescription)")
        #expect(
            row.components(separatedBy: "38;2;9;9;9").count == 2,
            "more than one run for the row: \(row.debugDescription)")
    }

    /// The memo hole: a row's colour is baked into its buffer, so a row that
    /// has MOVED within the ramp has to re-render even though nothing about the
    /// row changed. Keyed only on value and size, the rows below an insertion
    /// went on wearing the shorter ramp's colours.
    @Test("A row that moves within the ramp re-inks")
    func movingWithinTheRampReInks() {
        let tui = TUIContext()
        func frame(_ items: [String]) -> [String?] {
            var environment = EnvironmentValues()
            environment.palette = SystemPalette.green
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            defer {
                tui.stateStorage.endRenderPass()
                tui.renderCache.removeInactive()
            }
            return renderToBuffer(
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.self) { Text(verbatim: $0) }
                }
                .foregroundStyle(vertical())
                .gradientExtent(.subtree),
                context: context
            ).lines.prefix(items.count).map { firstInk($0) }
        }

        let three = frame(["b", "c", "d"])
        #expect(three == ["255;0;0", "128;0;128", "0;0;255"], "\(three)")
        // The same three rows, one row further down a ramp that is now four
        // rows long. Every one of them has moved.
        let four = frame(["a", "b", "c", "d"])
        #expect(four == ["255;0;0", "170;0;85", "85;0;170", "0;0;255"], "stale ink: \(four)")
    }

    /// A lazy stack under the default extent is still SwiftUI's meaning.
    @Test("Without the modifier a LazyVStack row runs its own ramp")
    func lazyLeafExtentIsTheDefault() {
        let lines = renderToBuffer(
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
            }
            .foregroundStyle(vertical()),
            context: context()
        ).lines
        let rows = lines.prefix(3).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "the default spanned the stack: \(rows)")
    }
}

/// Reports the render context's gradient frame and draws nothing.
private struct _FrameProbe: View {
    let report: (GradientFrame?) -> Void
    var body: Never { fatalError("renders via Renderable") }
}

extension _FrameProbe: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        report(context.gradientFrame)
        return FrameBuffer(lines: ["."])
    }
}
