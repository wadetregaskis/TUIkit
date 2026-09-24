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
