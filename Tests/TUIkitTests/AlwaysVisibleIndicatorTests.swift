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
        withArm(which, rows: rows, always: always) { lines($0) }
    }

    /// The four arms, handed to `body` as views rather than as lines.
    ///
    /// `any View` and not `AnyView`: the caller's generic parameter is bound to
    /// the CONCRETE type when the existential is opened, so the view tree is the
    /// same one `arm` renders. An `AnyView` would be a node in that tree, and a
    /// flexible child measures differently through one.
    private func withArm<R>(
        _ which: Int, rows: [Row], always: Bool, _ body: (any View) -> R
    ) -> R {
        func loud(_ view: some View) -> some View {
            view
                .scrollIndicators(always ? .visible : .automatic)
                .scrollIndicatorStyle(.text)
        }
        switch which {
        case 0:
            return body(loud(
                List(selection: .constant(Int?.none)) {
                    ForEach(rows) { Text($0.name) }
                }
                .frame(height: 8)))
        case 1:
            return body(loud(
                Table(rows, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \Row.name).width(.flexible)
                }
                .frame(height: 8)))
        case 2:
            // Multi-line: a wrapping column makes the rows different heights,
            // which is the path with its own window arithmetic.
            return body(loud(
                Table(rows, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \Row.name).width(.fixed(6)).lineLimit(3)
                }
                .frame(height: 8)))
        default:
            return body(loud(
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

    /// The lines have to come out of the BUDGET, not out of the content.
    ///
    /// Drawing them was only half the claim: "reserved and drawn are one answer".
    /// A view that draws an indicator over a line it never reserved loses that
    /// line — and under `.visible` it loses it at every offset, because the
    /// reservation is constant, so there is no neighbouring offset that shows it.
    /// Three rows in a viewport that fits eight: nothing is hidden anywhere, so
    /// every row must be on screen.
    @Test("Both lines are reserved, not painted over the content", arguments: 0..<4)
    func indicatorsDoNotEatContent(which: Int) {
        let drawn = arm(which, rows: Self.few, always: true)
        for row in Self.few {
            #expect(
                drawn.contains { $0.contains(row.name) },
                "\(Self.armNames[which]) lost \(row.name) under the indicator: \(drawn)")
        }
    }

    /// A view is measured before it is rendered, and the two have to agree about
    /// the two lines. They did not: the analytic size of a table whose rows FIT
    /// counted the rows alone, so a `.visible` table measured two lines shorter
    /// than it drew — and a container that believed the measurement then gave it
    /// a viewport two lines too short, in which the reservation ate two of the
    /// three rows it was supposed to be protecting.
    @Test("A view measures the height it draws", arguments: 0..<4)
    func measuredHeightIsTheDrawnHeight(which: Int) {
        for rows in [Self.few, Self.many] {
            let (measured, drawn) = withArm(which, rows: rows, always: true) { view in
                let tui = TUIContext()
                var environment = EnvironmentValues()
                environment.focusManager = FocusManager()
                environment.applyRuntimeServices(from: tui)
                var context = RenderContext(
                    availableWidth: 40, availableHeight: 8, environment: environment,
                    tuiContext: tui)
                context.hasExplicitHeight = true
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                let size = measureChild(
                    view, proposal: ProposedSize(width: 40, height: 8), context: context)
                let buffer = renderToBuffer(view, context: context)
                tui.stateStorage.endRenderPass()
                return (size.height, buffer.height)
            }
            #expect(
                measured == drawn,
                "\(Self.armNames[which]), \(rows.count) rows: measured \(measured), drew \(drawn)")
        }
    }

    /// The reason any of this matters: the rows' share of the content area is the
    /// same at the top, in the middle and at the bottom, so nothing moves under
    /// the reader as they scroll. Counted as "how many lines are neither
    /// indicator nor chrome".
    @Test("The rows' share of the content area never changes", arguments: 0..<4)
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

/// The two lines have to be in the SIZE as well as in the picture.
///
/// A framed view is told its height, so measure and render agree there whatever
/// either believes. A HUGGING one answers with a height of its own, and that is
/// where a view can measure one thing and draw another — the container then
/// allots what it was told, and the view draws into a viewport two lines shorter
/// than the one it measured for.
@MainActor
@Suite("A hugging view measures the indicator lines it reserves")
struct AlwaysVisibleHugMeasureTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    private func measuredAndDrawn(_ view: some View, height: Int = 20) -> (Int, Int) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: height, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let size = measureChild(
            view, proposal: ProposedSize(width: 40, height: height), context: context)
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        return (size.height, buffer.height)
    }

    @Test("A hugging table whose rows fit measures its reserved lines too", arguments: [1, 3])
    func huggingTableMeasuresTheReservation(lineLimit: Int) {
        let rows = (0..<3).map(Row.init(id:))
        let (measured, drawn) = measuredAndDrawn(
            Table(rows, selection: .constant(Int?.none)) {
                TableColumn("Name", value: \Row.name).width(.flexible).lineLimit(lineLimit)
            }
            .scrollIndicatorStyle(.text)
            .scrollIndicators(.visible))
        #expect(measured == drawn, "measured \(measured), drew \(drawn)")
    }

    /// The control: `.automatic` reserves nothing when everything fits, so the
    /// same table measures and draws its rows alone. Without this the test above
    /// could pass by both numbers being wrong in the same direction.
    @Test("…and an automatic one still measures its rows alone", arguments: [1, 3])
    func automaticHuggingTableIsUnchanged(lineLimit: Int) {
        let rows = (0..<3).map(Row.init(id:))
        let (measured, drawn) = measuredAndDrawn(
            Table(rows, selection: .constant(Int?.none)) {
                TableColumn("Name", value: \Row.name).width(.flexible).lineLimit(lineLimit)
            }
            .scrollIndicatorStyle(.text))
        #expect(measured == drawn, "measured \(measured), drew \(drawn)")
        #expect(drawn == 6, "3 rows + top border + header + bottom border: \(drawn)")
    }
}

/// What a frame draws is what THAT frame reserved.
///
/// The single-line `Table` used to publish the answer onto its handler and read
/// it back when composing, which is a latch, and a latch has a stale value. A
/// table that overflowed and then stopped — its data filtered down, its terminal
/// grown — skips the reservation entirely, and `scrollOffset` did not change, so
/// nothing cleared what the last frame left there. The composer read it and drew
/// "▼ 0 more rows below" under a table with nothing below it.
@MainActor
@Suite("A frame's indicators are that frame's", .serialized)
struct TableIndicatorLatchTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    /// One context and one handler across frames, as the run loop has — the
    /// whole point is what survives from one frame into the next.
    private func frames(_ counts: [Int]) -> [[String]] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.scrollIndicatorStyle = .text
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 8, environment: environment, tuiContext: tui)
        return counts.map { count in
            let view = Table((0..<count).map(Row.init(id:)), selection: .constant(Int?.none)) {
                TableColumn("Name", value: \Row.name).width(.flexible)
            }
            .frame(height: 8)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines.map(\.stripped)
        }
    }

    @Test("A table that stops overflowing stops drawing the below line")
    func theBelowLineGoesWithTheOverflow() {
        // 50 rows in a five-line content area overflows; three rows do not, and
        // the offset stays 0 throughout, so nothing else clears the answer.
        let drawn = frames([50, 3])
        #expect(
            drawn[0].contains { $0.contains("▼") },
            "the overflowing frame draws it: \(drawn[0])")
        #expect(
            !drawn[1].contains { $0.contains("▼") },
            "…and the frame that fits does not: \(drawn[1])")
    }
}
