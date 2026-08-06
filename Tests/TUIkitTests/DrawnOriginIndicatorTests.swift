//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DrawnOriginIndicatorTests.swift
//
//  The "N more rows above/below" indicators count from the offset the rows
//  were DRAWN from, not from wherever `scrollOffset` happens to stand.
//
//  `ScrollWindowOrigin.absorbing` draws a one-line-hidden offset from the line
//  above, because announcing that line would cost the very line it hides. It is
//  a resolution, not a state change, so `scrollOffset` keeps its value — and
//  normally `settleRestingOffset` snaps it down anyway. It deliberately does
//  NOT while a drop slot hovers, and there the two disagreed: two consecutive
//  frames drew identical rows and reported different counts, one of them
//  counting a row plainly on screen as hidden below.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Indicators count from the drawn origin")
struct DrawnOriginIndicatorTests {

    /// A six-row List in a viewport that shows three, with a foreign drag
    /// hovering it — the Example's Queue-onto-Backlog shape.
    @MainActor
    private final class Fixture {
        let names = (0..<6).map { "r\($0)" }
        let tui = TUIContext()
        var env = EnvironmentValues()
        var buffer = FrameBuffer(lines: [], width: 0)

        init() {
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        func render() {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let list = List {
                ForEach(names, id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { _, _ in }
            }
            .frame(height: 7)
            var context = RenderContext(
                availableWidth: 24, availableHeight: 12, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            buffer = renderToBuffer(list, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        }

        /// The row labels drawn, in order. Matched EXACTLY — an indicator line
        /// like "▼ 2 more rows below" contains "r" too, and reading it as a row
        /// is how this bug hid.
        var drawnRows: [String] {
            buffer.lines.compactMap { line in
                let letters = String(line.stripped.filter { $0.isLetter || $0.isNumber })
                return names.contains(letters) ? letters : nil
            }
        }

        /// The number in the "▼ N more rows below" line, if one is drawn.
        var rowsBelow: Int? {
            for line in buffer.lines where line.stripped.contains("▼") {
                return Int(String(line.stripped.filter(\.isNumber))) ?? 0
            }
            return nil
        }

        func hoverDrag() {
            render()
            let y = buffer.lines.firstIndex { $0.stripped.contains("r1") } ?? 2
            tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
                button: .left, phase: .dragged, x: 2, y: y)
            tui.dragAndDropSession.begin(payload: "z", preview: FrameBuffer(text: "z"))
            render()
        }

        func navigator(_ key: Key) {
            _ = tui.dragAndDropSession.handleDragNavigator(KeyEvent(key: key))
            render()
        }
    }

    /// Whatever is on screen, "N more below" plus the rows drawn must account
    /// for every row: the indicator's subject is the rows the user CANNOT see.
    @Test("The below count and the drawn rows account for every row")
    func belowCountAgreesWithWhatIsDrawn() {
        let fixture = Fixture()
        fixture.hoverDrag()

        var offenders: [String] = []
        func check(_ tag: String) {
            let drawn = fixture.drawnRows
            let below = fixture.rowsBelow ?? 0
            // Rows above are whatever is neither drawn nor counted below; the
            // invariant is that nothing is double-counted or lost.
            if drawn.count + below > fixture.names.count {
                offenders.append("\(tag): drew \(drawn) and claims \(below) below")
            }
            if let last = drawn.last, let index = fixture.names.firstIndex(of: last) {
                let actuallyBelow = fixture.names.count - (index + 1)
                if below != actuallyBelow {
                    offenders.append(
                        "\(tag): drew through \(last) (\(actuallyBelow) below) "
                            + "but claims \(below)")
                }
            }
        }

        check("hover")
        for step in 1...4 {
            fixture.navigator(.down)
            check("down\(step)")
        }
        for step in 1...5 {
            fixture.navigator(.up)
            check("up\(step)")
        }
        #expect(offenders.isEmpty, "every frame counts what it drew: \(offenders)")
    }

    /// Two screens that look identical must PAGE identically too.
    ///
    /// Home lands on offset 0 and Page Up lands on offset 1, and near the top
    /// edge those draw the same picture — so before `pageDelta(_:)` re-based
    /// the jump, one Page Down from what looked like the very same place went
    /// two rows or three depending on which key got you there.
    @Test("Two routes to the top page to the same place")
    func pagingDoesNotDependOnHowYouReachedTheTop() {
        func topThenPageDown(viaHome: Bool) -> [String] {
            let fixture = Fixture()
            fixture.hoverDrag()
            fixture.navigator(.end)
            fixture.navigator(viaHome ? .home : .pageUp)
            let atTop = fixture.drawnRows
            fixture.navigator(.pageDown)
            return atTop + ["|"] + fixture.drawnRows
        }
        let viaHome = topThenPageDown(viaHome: true)
        let viaPageUp = topThenPageDown(viaHome: false)
        // Guard the premise: if the two routes did not both reach a top that
        // draws the same rows, this test proves nothing about paging.
        #expect(
            viaHome.prefix(while: { $0 != "|" }) == viaPageUp.prefix(while: { $0 != "|" }),
            "both routes reach the same-looking top: \(viaHome) vs \(viaPageUp)")
        #expect(viaHome == viaPageUp, "and page to the same place: \(viaHome) vs \(viaPageUp)")
    }

    /// The owner's invariant, and the symptom as reported: an arrow key that
    /// changes no visible row must not change how many are said to be below.
    @Test("A key that moves no row changes no count")
    func aKeyThatDrawsTheSameSaysTheSame() {
        let fixture = Fixture()
        fixture.hoverDrag()
        fixture.navigator(.down)
        fixture.navigator(.down)

        var previousRows = fixture.drawnRows
        var previousBelow = fixture.rowsBelow
        var offenders: [String] = []
        for step in 1...4 {
            fixture.navigator(.up)
            let rows = fixture.drawnRows
            let below = fixture.rowsBelow
            if rows == previousRows, below != previousBelow {
                offenders.append(
                    "up\(step) drew \(rows) both times but went "
                        + "\(previousBelow.map(String.init) ?? "—") → "
                        + "\(below.map(String.init) ?? "—") below")
            }
            (previousRows, previousBelow) = (rows, below)
        }
        #expect(offenders.isEmpty, "identical frames report identical counts: \(offenders)")
    }
}
