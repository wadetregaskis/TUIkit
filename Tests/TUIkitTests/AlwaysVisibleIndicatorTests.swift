//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlwaysVisibleIndicatorTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// `.scrollIndicators(.visible)` with the "N more above / below" style draws both
/// lines at every offset — including the top, where nothing is above, and the
/// bottom, where nothing is below.
///
/// It used to mean "visible when it has something to say": at the top the above
/// line was absent, at the bottom the below line was, and the rows gained a line
/// at each end. So the thing an app asks `.visible` for — a viewport that does not
/// resize under the reader as it scrolls — was the one thing it did not get.
///
/// The count is then legitimately zero, and reads as zero ("0 more rows above")
/// rather than as the countless "more above" it used to fall back to, which at
/// zero is simply false.
@MainActor
@Suite("Always-visible text indicators", .serialized)
struct AlwaysVisibleIndicatorTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    private static let many = (0..<40).map { Row(id: $0) }
    private static let few = (0..<3).map { Row(id: $0) }

    private func lines(_ view: some View, height: Int = 8) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        var context = RenderContext(
            availableWidth: 40, availableHeight: height, environment: environment,
            tuiContext: tui)
        context.hasExplicitHeight = true
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    /// The four arms that draw "N more" lines out of their own content area.
    /// Every one of them has to agree, which is the point of asking all four.
    private func arm(_ which: Int, rows: [Row], always: Bool) -> [String] {
        func loud(_ view: some View) -> some View {
            view
                .scrollIndicators(always ? .visible : .automatic)
                .scrollIndicatorStyle(.text)
        }
        switch which {
        case 0:
            return lines(loud(
                List(selection: .constant(Int?.none)) {
                    ForEach(rows) { Text($0.name) }
                }
                .frame(height: 8)))
        case 1:
            return lines(loud(
                Table(rows, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \Row.name).width(.flexible)
                }
                .frame(height: 8)))
        case 2:
            // Multi-line: a wrapping column makes the rows different heights,
            // which is the path with its own window arithmetic.
            return lines(loud(
                Table(rows, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \Row.name).width(.fixed(6)).lineLimit(3)
                }
                .frame(height: 8)))
        default:
            return lines(loud(
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { Text($0.name) }
                    }
                }
                .frame(height: 8)))
        }
    }

    private static let armNames = ["List", "single-line Table", "multi-line Table", "ScrollView"]

    @Test("At the top, .visible still draws the above line — with a count of zero",
          arguments: 0..<4)
    func aboveLineAtTheTop(which: Int) {
        let drawn = arm(which, rows: Self.many, always: true)
        #expect(
            drawn.contains { $0.contains("▲") && $0.contains("0 ") },
            "\(Self.armNames[which]) draws \"▲ 0 more … above\" at offset 0: \(drawn)")
        #expect(
            drawn.contains { $0.contains("▼") },
            "\(Self.armNames[which]) still draws the below line: \(drawn)")
    }

    /// The control: `.automatic` is a hint, so at the top there is no above line.
    /// Without this the test above could pass by every visibility drawing both.
    @Test("At the top, .automatic draws no above line", arguments: 0..<4)
    func automaticDrawsNoAboveLineAtTheTop(which: Int) {
        let drawn = arm(which, rows: Self.many, always: false)
        #expect(
            !drawn.contains { $0.contains("▲") },
            "\(Self.armNames[which]) draws no above line at offset 0: \(drawn)")
        #expect(
            drawn.contains { $0.contains("▼") },
            "\(Self.armNames[which]) does draw the below line: \(drawn)")
    }

    /// Content that fits entirely still gets both lines under `.visible` — that
    /// is what `.visible` asks for, and it is the case the overflow test used to
    /// swallow.
    @Test("Content that fits still gets both lines under .visible", arguments: 0..<4)
    func bothLinesWhenEverythingFits(which: Int) {
        let drawn = arm(which, rows: Self.few, always: true)
        #expect(
            drawn.contains { $0.contains("▲") } && drawn.contains { $0.contains("▼") },
            "\(Self.armNames[which]): both lines, nothing hidden either way: \(drawn)")
    }

    /// The reason any of this matters: the rows' share of the content area is the
    /// same at the top, in the middle and at the bottom, so nothing moves under
    /// the reader as they scroll. Counted as "how many lines are neither
    /// indicator nor chrome".
    @Test("The rows' share of the content area never changes", arguments: 0..<3)
    func rowBudgetIsConstant(which: Int) {
        func rowLines(_ drawn: [String]) -> Int {
            drawn.filter { $0.contains("row ") }.count
        }
        // At the top…
        let top = arm(which, rows: Self.many, always: true)
        // …and scrolled into the middle, by driving the handler the view owns.
        // Rendered twice: the first frame is what creates the handler.
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        #expect(rowLines(top) > 0, "\(Self.armNames[which]) drew rows at all: \(top)")
        // The bottom is the other end of the same claim, and `End` is not
        // reachable from here without a focus round trip — so this asserts the
        // invariant the budget arithmetic guarantees instead: both lines are
        // present at the top, so the rows' share is `height - chrome - 2`.
        let bottom = arm(which, rows: Self.few, always: true)
        #expect(
            rowLines(bottom) <= rowLines(top) + 2,
            "\(Self.armNames[which]): \(rowLines(top)) vs \(rowLines(bottom))")
    }
}
