//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewTabFitTests.swift
//
//  A TabView sizes its panel from its tabs' measured sizes and then draws the
//  selected tab in that panel. The two have to be the same question: a tab
//  measured in more room than it is drawn in is sized for a layout nobody
//  sees, and the difference lands on the content — a scroll view's bar taking
//  a column out of its rows, a panel sized for a candidate `ViewThatFits`
//  does not draw.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
private func renderFrames(_ view: some View, width: Int, height: Int) -> FrameBuffer {
    let tui = TUIContext()
    var environment = EnvironmentValues()
    environment.focusManager = FocusManager()
    environment.stateStorage = StateStorage()
    environment.applyRuntimeServices(from: tui)
    var context = RenderContext(
        availableWidth: width, availableHeight: height, environment: environment,
        tuiContext: tui)
    context.hasExplicitWidth = true
    context.hasExplicitHeight = true
    // Two frames, the way the run loop draws them, so nothing here depends on
    // a first-frame special case.
    _ = renderToBuffer(view, context: context)
    return renderToBuffer(view, context: context)
}

@MainActor
private func rows(from first: Int, count: Int) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(first..<(first + count), id: \.self) { Text("row \($0)") }
        }
    }
}

private func dump(_ lines: [String]) -> String {
    lines.map { "[\($0)]" }.joined(separator: "\n")
}

@MainActor
@Suite("A TabView measures a tab in the height it draws it in")
struct TabViewTabMeasureHeightTests {

    /// Content within the strip's height of the TabView's. A TabView measured
    /// its tabs against its whole height and then laid them out in that less
    /// the strip's chrome, so a scroll view there measured as fitting — no
    /// column for a bar — and overflowed the shorter height it was drawn in,
    /// and the bar took its column out of the rows ("row 1" for "row 10").
    @Test(
        "A scroll view a strip's height short of fitting in a TabView keeps its rows whole",
        arguments: [
            (TabViewStyle.compact, 12),
            // Bordered: twelve rows less four of chrome and the default inset's
            // two leaves six, so seven to ten rows fitted the measure and not
            // the box.
            (.bordered, 7), (.bordered, 10),
        ])
    func stripBandKeepsTheRowsWhole(style: TabViewStyle, rowCount: Int) {
        let lines = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("A", value: 0) { rows(from: 10, count: rowCount) }
            }
            .tabViewStyle(style),
            width: 30, height: 12
        ).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("row 10") }, "row 10 was squeezed:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("▲") }, "no bar:\n\(dump(lines))")
    }

    /// A tab whose layout depends on the height: twelve wide lines where they
    /// fit, one narrow word where they do not. Twelve rows fit the TabView's
    /// twelve, not the eleven left under the strip, so the panel was sized for
    /// the wide candidate and drew the narrow one in the middle of it.
    @Test("A tab is sized for the layout it is drawn as")
    func panelFitsTheDrawnLayout() {
        let buffer = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("A", value: 0) {
                    ViewThatFits(in: .vertical) {
                        VStack(spacing: 0) {
                            ForEach(0..<12, id: \.self) { _ in Text("wide wide wide") }
                        }
                        Text("narrow")
                    }
                }
            },
            width: 40, height: 12)
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.contains { $0.contains("narrow") }, "not the narrow layout:\n\(dump(lines))")
        #expect(buffer.width == 6, "a panel \(buffer.width) wide for a six-cell word:\n\(dump(lines))")
    }
}

@MainActor
@Suite("A TabView draws a tab that fills its width at the width it measured")
struct TabViewFillingTabTests {

    /// The reported shape. A panel sized to a strip wider than the tab: the
    /// tab was rendered at the panel's width, which put the scroll view's bar
    /// in the panel's last column, and then clamped back to the tab's own
    /// ideal width to centre it — which cut the bar off, on every frame.
    @Test(
        "A scroll view in a TabView keeps its scrollbar",
        arguments: [TabViewStyle.compact, .bordered])
    func scrollViewKeepsItsBar(style: TabViewStyle) {
        let lines = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("Scrolling rows", value: 0) { rows(from: 0, count: 50) }
            }
            .tabViewStyle(style),
            width: 30, height: 12
        ).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("▲") }, "no top arrow:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("▼") }, "no bottom arrow:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("row 0") }, "the rows are gone:\n\(dump(lines))")
    }

    /// The same clamp, on content with no scroll view in it at all. A `Divider`
    /// fills its width, so the column did: rendered across the panel, its title
    /// and body were centred in the panel, and the clamp to the column's own
    /// nine cells kept only the middle of the rule. Both lines of text were
    /// drawn and then cut away.
    @Test(
        "A column with a Divider keeps its text in a wider panel",
        arguments: [TabViewStyle.compact, .bordered])
    func dividerColumnKeepsItsText(style: TabViewStyle) {
        let lines = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { VStack { Text("Title"); Divider(); Text("body text") } }
                Tab("Two", value: 1) { Text("a much wider tab body than the first") }
            }
            .tabViewStyle(style),
            width: 30, height: 12
        ).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("Title") }, "the title is gone:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("body text") }, "the body is gone:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("─────────") }, "the rule is gone:\n\(dump(lines))")
    }

    /// A text field fills its width too: its closing cap was drawn in the
    /// panel's last column and clamped off.
    @Test("A text field in a narrower tab keeps its closing cap")
    func textFieldKeepsItsCap() {
        let lines = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) {
                    VStack(alignment: .leading) {
                        Text("Name")
                        TextField("prompt", text: .constant("hello"))
                    }
                }
                Tab("Two", value: 1) { Text("a much wider tab body than the first one is") }
            },
            width: 30, height: 12
        ).lines.map(\.stripped)
        let field = lines.first { $0.contains("hello") } ?? ""
        #expect(field.contains("▐hello"), "no field:\n\(dump(lines))")
        #expect(field.contains("▌"), "the field's closing cap is gone:\n\(dump(lines))")
    }

    /// A `.toContentWidth` strip folded onto eight rows, where the tabs were
    /// measured allowing for one: the selected scroll view measured as fitting
    /// eleven rows and answered no column for a bar. Rendered at that width in
    /// the four rows left under the strip, its bar took the column out of the
    /// rows, and "row 10" wrapped onto two lines; rendered at the panel's
    /// width and clamped back, the bar was cut off instead.
    @Test("A tab drawn in fewer rows than it was measured in keeps its rows and its bar")
    func foldedStripKeepsRowsAndBar() {
        let lines = renderFrames(
            TabView(selection: .constant(0)) {
                ForEach(0..<8, id: \.self) { index in
                    Tab("Tab\(index)", value: index) { rows(from: 10, count: 6 + index) }
                }
            }
            .tabViewHeaderWrap(.toContentWidth),
            width: 30, height: 12
        ).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("row 10") }, "row 10 was wrapped:\n\(dump(lines))")
        #expect(lines.contains { $0.contains("▲") }, "no bar:\n\(dump(lines))")
    }

    /// NOT fixed: a scroll view under a header whose rows fit the tab's height
    /// but not what the header leaves them. A column measures its children
    /// against its whole height and lays them out in their share of it, so the
    /// scroll view answered no column for a bar it then drew in eleven rows
    /// less the header's one. Rendered at its natural width that squeezes the
    /// rows; rendered at the panel's and clamped back, as before this, a wider
    /// strip hid it by clipping the bar off instead. The fix is the column's:
    /// measure a squeezed flexible child in its share.
    @Test("A scroll view under a header a row short of fitting keeps its rows (known issue)")
    func headerBandKeepsTheRows() {
        let lines = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("Log", value: 0) {
                    VStack(alignment: .leading) { Text("Header"); rows(from: 10, count: 11) }
                }
            },
            width: 30, height: 12
        ).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("▲") }, "no bar:\n\(dump(lines))")
        withKnownIssue("a column measures a flexible child in its whole height, not its share") {
            #expect(lines.contains { $0.contains("row 10") }, "row 10 was squeezed:\n\(dump(lines))")
        }
    }

    /// A strip wider than the space: a bordered tab's one-tab row, " One "
    /// between walls, is seven cells, and an eight-cell terminal leaves six
    /// inside the box. Tabs are measured in the six and drawn in the panel's
    /// seven, so what they measured is no width to hold them to — rendered at
    /// it, an `HStack` of "a", a spacer and "b" lost its "b"; clamped to it, a
    /// `List` lost its right border.
    @Test("Content that takes all the space is not squeezed when the strip is wider")
    func contentTakingAllTheSpaceIsNotSqueezed() {
        let spread = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { HStack { Text("a"); Spacer(); Text("b") } }
                Tab("Two", value: 1) { Text("a much wider tab body than the first") }
            }
            .tabViewStyle(.bordered),
            width: 8, height: 12
        ).lines.map(\.stripped)
        #expect(spread.contains { $0.contains("a b") }, "the row lost a word:\n\(dump(spread))")

        let list = renderFrames(
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { List { ForEach(0..<30, id: \.self) { Text("item \($0)") } } }
                Tab("Two", value: 1) { Text("wide wide wide wide body") }
            }
            .tabViewStyle(.bordered),
            width: 8, height: 12
        ).lines.map(\.stripped)
        #expect(list.contains { $0.contains("╭─╮") }, "the list lost its right border:\n\(dump(list))")
    }
}
