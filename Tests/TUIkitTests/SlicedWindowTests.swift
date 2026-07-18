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

    @Test("Five million rows through the real ScrollView, interactively")
    func fiveMillionRows() {
        // The design doc's §1 composition at the scale it was designed for.
        // Frame 1's measures use the sample-based estimate (no persisted
        // hypothesis exists yet — seeding is render-only); the render seeds
        // and seeks; every frame builds O(window) rows and the buffer is the
        // band. Before this branch, this test would not have completed.
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<5_000_000, id: \.self) { i in
                    Button("row \(i)") {}
                }
            }
        }
        .frame(height: 6)
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("row 0") }, "top of five million: \(first)")

        // Jump 4,999,993 rows by focus id: the pending-intent key scan is
        // the documented Ω(n) id→ordinal cost — touching keys, never
        // building rows — and the reveal rides the sliced pipeline.
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        let idTail = id0.replacingOccurrences(of: "[0]", with: "[4999999]")
        focusManager.focus(id: idTail)
        var revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        if revealed.contains(where: { $0.contains("row 4999999") }) == false {
            revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        #expect(
            revealed.contains { $0.contains("row 4999999") },
            "revealed the five-millionth row: \(revealed)")
    }

    /// One live-loop-shaped frame against a bare windowed stack (no
    /// ScrollView), returning the raw band buffer and its reply — for
    /// asserting on the band's SIZE, which the ScrollView's clip hides.
    private func renderBandFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager,
        offset: Int, viewportHeight: Int = 5
    ) -> (buffer: FrameBuffer, reply: ScrollContentReply) {
        let reply = ScrollContentReply()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: viewportHeight, contentIdentity: nil, reply: reply)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 50,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return (buffer, reply)
    }

    @Test("A focused row a million rows from the window keeps the band compact (uniform)")
    func farFocusedRowCompactBandUniform() {
        // The focused row must render every frame (registration keeps focus
        // alive), but it must NOT drag the band with it: materialising the
        // focus→window gap as blank lines costs O(distance) time and memory
        // per frame, forever, while the user stays scrolled away.
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<1_000_000, id: \.self) { i in Button("row \(i)") {} }
        }
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        _ = renderBandFrame(view, tuiContext: tuiContext, focusManager: focusManager, offset: 0)
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        focusManager.focus(id: id0)
        _ = renderBandFrame(view, tuiContext: tuiContext, focusManager: focusManager, offset: 0)

        let far = renderBandFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, offset: 999_990)
        #expect(far.buffer.height < 40, "band, not gap: \(far.buffer.height) lines")
        #expect(
            far.reply.sliceOriginY == 999_989,
            "the band anchors on the WINDOW, not the focused row: \(String(describing: far.reply.sliceOriginY))")
        #expect(
            far.buffer.lines.contains { $0.contains("row 999990") },
            "the window rows themselves render")
        #expect(focusManager.currentFocusedID == id0, "the far focused row still registers")

        // The focused row's region rides along at its true content-space y
        // (band-local, so negative here), so reveal-on-focus still sees it.
        let region = far.buffer.hitTestRegions.first { $0.focusID == id0 }
        #expect(region != nil, "the focused row's hit region is grafted into the band")
        if let region, let origin = far.reply.sliceOriginY {
            #expect(region.offsetY + origin == 0, "region sits at row 0 in content space")
        }
    }

    @Test("A focused row far from the window keeps the band compact (anchored)")
    func farFocusedRowCompactBandAnchored() {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<100_000, id: \.self) { i in
                Button("row \(i)") {}.frame(height: i % 3 + 1)
            }
        }
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        _ = renderBandFrame(view, tuiContext: tuiContext, focusManager: focusManager, offset: 0)
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        focusManager.focus(id: id0)
        _ = renderBandFrame(view, tuiContext: tuiContext, focusManager: focusManager, offset: 0)

        let far = renderBandFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, offset: 150_000)
        #expect(far.buffer.height < 60, "band, not gap: \(far.buffer.height) lines")
        #expect(
            (far.reply.sliceOriginY ?? 0) > 100_000,
            "the band anchors near the WINDOW, not the focused row: \(String(describing: far.reply.sliceOriginY))")
        #expect(focusManager.currentFocusedID == id0, "the far focused row still registers")
        #expect(
            far.buffer.hitTestRegions.contains { $0.focusID == id0 },
            "the focused row's hit region is grafted into the band")
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
