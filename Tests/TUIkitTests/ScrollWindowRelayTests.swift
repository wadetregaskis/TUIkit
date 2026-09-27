//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollWindowRelayTests.swift
//
//  What a `Section` does with the band its content claims through the relayed
//  scroll window (`ScrollWindowRelay`), for bands the anchored window's
//  estimates can produce and the section tests' rows do not reach: one that
//  starts at the content's 0 without its first row, and one whose content 0
//  lies inside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Content that claims, through the window's reply, a band of `lines` lines
/// starting at `originY` in its own coordinates, holding its first row or not.
private struct ClaimedBand: View, Renderable {
    let lines: Int
    let originY: Int
    let holdsFirstRow: Bool

    var body: Never { fatalError("ClaimedBand renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if let reply = context.environment.scrollContentWindow?.reply {
            reply.sliceOriginY = originY
            reply.sliceTotalHeight = originY + lines + 20
            reply.sliceHoldsFirstRow = holdsFirstRow
            reply.sliceHoldsLastRow = false
        }
        return FrameBuffer(lines: (0..<lines).map { "band \($0)" })
    }
}

@MainActor
@Suite("A section places its own lines by what its content's band says")
struct ScrollWindowRelayTests {
    /// `view` drawn at 30x8 at a scroll content's origin, with the reply the
    /// scroll view reads.
    private func draw<V: View>(_ view: V) -> (buffer: FrameBuffer, reply: ScrollContentReply) {
        let (tui, focusManager) = (TUIContext(), FocusManager())
        let reply = ScrollContentReply()
        var window = ScrollContentWindow(offset: 0, viewportHeight: 8)
        window.reply = reply
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.scrollContentWindow = window
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        return (buffer, reply)
    }

    @Test(
        "The header joins the band when the band holds the first row, wherever it starts",
        arguments: [(0, false), (3, true)])
    func headerJoinsByTheFirstRow(originY: Int, holdsFirstRow: Bool) {
        // The anchored window places its rows from an anchor, by estimate:
        // a band can start at its 0 without its first row, or hold the first
        // row somewhere below 0. Only the band's word says which.
        let (buffer, reply) = draw(
            Section {
                ClaimedBand(lines: 4, originY: originY, holdsFirstRow: holdsFirstRow)
            } header: {
                Text("header")
            })
        let lines = buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect((lines.first == "header") == holdsFirstRow, "\(lines)")
        // The section's buffer starts at the header's line when it joins, and
        // at the band's first line, one header line down, when it does not.
        #expect(reply.sliceOriginY == originY + (holdsFirstRow ? 0 : 1))
        #expect(reply.sliceHoldsFirstRow == holdsFirstRow)
    }

    @Test("A header left out of a band that holds the content's 0 is carried above the band, not into it")
    func headerControlIsCarriedAboveTheBand() {
        // The band starts two lines above the content's 0, without its first
        // row: the header's place, one line above that 0, is the band's second
        // line. Its control carried there would lie over a line of the band.
        let (buffer, _) = draw(
            Section {
                ClaimedBand(lines: 4, originY: -2, holdsFirstRow: false)
            } header: {
                Button("top") {}
            })
        let control = buffer.hitTestRegions.filter { $0.focusID?.hasPrefix("button-") == true }
        #expect(!control.isEmpty, "precondition: the header's control is carried")
        #expect(
            control.allSatisfy { $0.offsetY + $0.height <= 0 },
            "the header's control lies over the band: \(control)")
    }
}
