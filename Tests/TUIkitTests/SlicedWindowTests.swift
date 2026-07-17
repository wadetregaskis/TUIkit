//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SlicedWindowTests.swift
//
//  Stage 6 of "Locating things without drawing them": renderedContent draws
//  only the window. With the reply channel, the windowed stack returns just
//  the rendered band plus (origin, total) metadata — no more O(total) blank
//  lines — and the ScrollView clips the band directly, rebasing offsets and
//  regions by the slice origin. The identity gate that rides along also
//  fixes a latent bug: a lazy stack that is NOT the ScrollView's direct
//  content (one sibling among several, e.g. below a header) must not
//  consume the window — its rows are not at the scroll origin, and
//  windowing there blanked the wrong rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("sliced windowing (Stage 6)")
struct SlicedWindowTests {
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager,
        width: Int = 30, height: Int = 6
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
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

    @Test("With a reply channel, the stack emits the band, not 100k lines")
    func bandNotCanvas() {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<100_000, id: \.self) { i in Text("row \(i)") }
        }
        let reply = ScrollContentReply()
        var context = makeBareRenderContext(width: 20, height: 50)
        context.environment.scrollContentWindow = ScrollContentWindow(
            offset: 50_000, viewportHeight: 5, contentIdentity: nil, reply: reply)

        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.height < 20, "the buffer is the band, got \(buffer.height) lines")
        #expect(reply.sliceOriginY == 49_999, "band starts at the top margin row")
        #expect(reply.sliceTotalHeight == 100_000, "the total is exact for uniform rows")

        let lines = buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(lines[0] == "row 49999", "band-local coordinates start at the slice origin")
        #expect(lines[1] == "row 50000")
        #expect(lines[6] == "row 50005", "…through the bottom margin row")
    }

    @Test("20k rows through the real ScrollView: reveal works over the sliced pipeline")
    func endToEndSlicedReveal() {
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20_000, id: \.self) { i in
                    Button("row \(i)") {}
                }
            }
        }
        .frame(height: 6)
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("row 0") }, "starts at the top: \(first)")

        // Jump to the tail by focus id (key surgery on row 0's default id).
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        let idTail = id0.replacingOccurrences(of: "[0]", with: "[19999]")
        focusManager.focus(id: idTail)
        var revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        if revealed.contains(where: { $0.contains("row 19999") }) == false {
            revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        #expect(focusManager.currentFocusedID == idTail, "focus landed 19,993 rows away")
        #expect(
            revealed.contains { $0.contains("row 19999") },
            "the sliced pipeline revealed the tail: \(revealed)")

        // Steady after reveal, and back to the top.
        let settled = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(settled.contains { $0.contains("row 19999") }, "stable: \(settled)")
        focusManager.focus(id: id0)
        var back = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        if back.contains(where: { $0.contains("row 0 ") }) == false {
            back = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        #expect(back.contains { $0.contains("row 0") }, "and back up: \(back)")
    }

    @Test("A lazy stack below a header must NOT consume the window (identity gate)")
    func nonDirectContentIsGated() {
        // Pre-gate, the leaked window blanked rows against scroll-origin
        // coordinates while the stack sat header-height lower — revealing a
        // mid row showed misplaced blanks. With the gate the stack renders
        // eagerly (exactly like main), and reveal shows the row correctly.
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("header one")
                Text("header two")
                Text("header three")
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<800, id: \.self) { i in
                        Button("inner \(i)") {}
                    }
                }
            }
        }
        .frame(height: 6)
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("header one") })
        #expect(first.contains { $0.contains("inner 0") })

        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        let idMid = id0.replacingOccurrences(of: "[0]", with: "[400]")
        focusManager.focus(id: idMid)
        var revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        if revealed.contains(where: { $0.contains("inner 400") }) == false {
            revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        #expect(
            revealed.contains { $0.contains("inner 400") },
            "the mid row reveals correctly under a header: \(revealed)")
        #expect(
            revealed.contains { $0.contains("inner 399") } || revealed.contains { $0.contains("inner 401") },
            "…surrounded by its real neighbours, not misaligned blanks: \(revealed)")
    }
}
