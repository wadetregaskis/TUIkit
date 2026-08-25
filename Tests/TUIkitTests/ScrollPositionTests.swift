//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollPositionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// `.scrollPosition` in both directions: writing it moves the scroll view,
/// and the scroll view writes back the row it is actually showing.
///
/// The read direction is the half that needed new machinery. A seek matches on
/// a stringified key, which is a one-way trip — fine for finding a row, useless
/// for handing one back to a `Binding<ID?>`. So the id VALUE now travels
/// alongside the key, and these tests are mostly about that trip.
@MainActor
@Suite("ScrollPosition")
struct ScrollPositionTests {
    private static let viewport = 6
    private static let rowCount = 40

    /// Renders one frame of a windowed list, driving the render-pass hooks the
    /// way the real loop does — the write-back is a render-time side effect, so
    /// a single `renderToBuffer` would not exercise it honestly.
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private func list(position: Binding<ScrollPosition>) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(position)
    }

    // MARK: - Writing

    @Test("Scrolling to a row brings it into view")
    func scrollToIDMoves() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })

        let first = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("row 0") })

        position.scrollTo(id: 30, anchor: .top)
        let after = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(after.contains { $0.contains("row 30") })
        #expect(!after.contains { $0.contains("row 0") })
    }

    @Test("Scrolling to an edge goes all the way")
    func scrollToEdge() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })

        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        position.scrollTo(edge: .bottom)
        let bottom = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(bottom.contains { $0.contains("row \(Self.rowCount - 1)") })

        position.scrollTo(edge: .top)
        let top = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(top.contains { $0.contains("row 0") })
    }

    @Test("A request is acted on once, not re-applied every frame")
    func requestIsNotSticky() {
        // The property that makes a bound position usable at all: after a
        // scrollTo lands, the user has to be able to scroll away and STAY away.
        // A naive implementation re-applies the still-present target forever.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })

        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        position.scrollTo(id: 20, anchor: .top)
        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)

        // Move away again, then render twice with that target still sitting in
        // the binding: the earlier row request must not reassert itself.
        position.scrollTo(edge: .top)
        let afterManual = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(afterManual.contains { $0.contains("row 0") })
        let settled = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled.contains { $0.contains("row 0") })
    }

    @Test("A standing target does not undo the user's scroll")
    func standingTargetDoesNotFight() {
        // The binding's environment box is rebuilt with every body
        // evaluation, so the freshness memory must live on the persistent
        // handler. Kept on the box, every frame saw a "new" request and
        // re-pinned the offset: the user could scroll away from a standing
        // scrollTo(edge: .bottom) and be dragged straight back.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })

        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        position.scrollTo(edge: .bottom)
        let bottom = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(bottom.contains { $0.contains("row \(Self.rowCount - 1)") })

        // The user scrolls back to the top; the target still sits in the
        // binding, and must stay spent.
        let handler = focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil, "the ScrollView registered its handler")
        handler?.scrollOffset = 0
        tuiContext.renderCache.clearAll()
        let after = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(after.contains { $0.contains("row 0") }, "\(after)")
        #expect(!after.contains { $0.contains("row \(Self.rowCount - 1)") })
    }

    // MARK: - Reading

    @Test("The scroll view reports the row it is showing")
    func reportsVisibleID() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })

        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        // Frame 1 showed row 0 at the top, and said so — the id VALUE, not the
        // key string the seek matches on.
        #expect(position.viewID(type: Int.self) == 0)
        #expect(position.isPositionedByUser)

        position.scrollTo(id: 25, anchor: .top)
        let landed = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        // The row is reported the SAME frame the seek lands, and the frame
        // after it does not drift — the sample is the first row a person can
        // actually see, not the one the "N more above" indicator is covering.
        #expect(position.viewID(type: Int.self) == 25)
        let settled = renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(landed == settled)
        #expect(position.viewID(type: Int.self) == 25)
    }

    @Test("An unchanged position is not written back every frame")
    func writeBackSettles() {
        // A render-time write to a binding invalidates the subtree that wrote
        // it. Writing unconditionally would schedule a frame from every frame
        // and never settle, so the write is gated on the value CHANGING —
        // `onPreferenceChange`'s discipline, for the same reason.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var writes = 0
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0; writes += 1 })

        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        let afterFirst = writes
        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(list(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(afterFirst == 1)
        #expect(writes == afterFirst)
    }

    @Test("The anchor decides which row is reported")
    func anchorChoosesTheSample() {
        // `.top` reports the first visible row; `.bottom` the last. Same
        // scroll position, different question.
        func reported(anchor: UnitPoint) -> Int? {
            let tuiContext = TUIContext()
            let focusManager = FocusManager()
            var position = ScrollPosition()
            let binding = Binding(get: { position }, set: { position = $0 })
            let view = ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<Self.rowCount, id: \.self) { Text("row \($0)") }
                }
            }
            .scrollPosition(binding, anchor: anchor)
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            return position.viewID(type: Int.self)
        }
        #expect(reported(anchor: .top) == 0)
        #expect((reported(anchor: .bottom) ?? 0) > 0)
    }

    @Test("At the very bottom the LAST row is reported, not the one above it")
    func bottomOfContentReportsTheFinalRow() {
        // With text indicators the viewport's last line is an indicator only
        // while content remains below. At the tail it is readable content —
        // the sample must not step past the final row on account of an
        // indicator that is not there.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(binding, anchor: .bottom)
        .scrollIndicatorStyle(.text)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        position.scrollTo(edge: .bottom)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let landed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            landed.contains { $0.contains("row \(Self.rowCount - 1)") },
            "precondition: the final row is on screen: \(landed)")
        #expect(position.viewID(type: Int.self) == Self.rowCount - 1)
    }

    @Test("Variable-height content reports the visible row too (the exact-walk path)")
    func variableHeightContentReportsVisibleID() {
        // Heights 1/2/3 repeating falsify the uniform hypothesis, sending
        // every frame after the first down the exact viewport-window walk —
        // which never sampled a row at all, so the binding went silent for
        // precisely the composition ScrollPosition's own doc example shows.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<30, id: \.self) { index in
                    Text(
                        Array(repeating: "row \(index)", count: 1 + index % 3)
                            .joined(separator: "\n"))
                }
            }
        }
        .scrollPosition(binding)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(position.viewID(type: Int.self) == 0)

        position.scrollTo(id: 15, anchor: .top)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let landed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            landed.contains { $0.contains("row 15") },
            "precondition: the target row is on screen: \(landed)")
        #expect(position.viewID(type: Int.self) == 15)
    }

    // MARK: - The id: binding

    @Test("scrollPosition(id:) writes the id back")
    func idBindingRoundTrips() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(id: binding)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(visible == 0)

        // …and writing it scrolls there.
        visible = 18
        let after = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(after.contains { $0.contains("row 18") })
    }

    // MARK: - The value type

    @Test("ScrollPosition records what it was last asked for")
    func positionValueSemantics() {
        var position = ScrollPosition()
        #expect(position.viewID(type: Int.self) == nil)
        #expect(position.edge == nil)
        #expect(!position.isPositionedByUser)

        position.scrollTo(edge: .bottom)
        #expect(position.edge == .bottom)
        // Asking for an edge is not asking for a row.
        #expect(position.viewID(type: Int.self) == nil)

        position.scrollTo(id: 7)
        #expect(position.viewID(type: Int.self) == 7)
        #expect(position.edge == nil)
        // A wrong-typed read is nil, not a crash.
        #expect(position.viewID(type: String.self) == nil)
        // Code asking is not the user scrolling.
        #expect(!position.isPositionedByUser)

        #expect(ScrollPosition(edge: .top).edge == .top)
        #expect(ScrollPosition(id: 3).viewID(type: Int.self) == 3)
    }
}
