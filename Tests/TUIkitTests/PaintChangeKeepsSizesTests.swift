//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaintChangeKeepsSizesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// A paint applied above memoised rows changes their ink and nothing else,
/// so a change to it drops their buffers and keeps their sizes: the rows
/// re-render in the new colour, and the measure walks do not touch them.
@MainActor
@Suite("A paint change re-inks memoised rows without re-measuring them", .serialized)
struct PaintChangeKeepsSizesTests {

    private struct CountingCell: View, Renderable, Layoutable {
        let width: Int
        var body: Never { fatalError("CountingCell renders via Renderable") }
        func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
            Counters.measures += 1
            return ViewSize.fixed(width, 1)
        }
        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            Counters.renders += 1
            let colour = context.environment.foregroundStyle?.representative ?? .ansi(.white)
            return FrameBuffer(text: ANSIRenderer.colorize(String(repeating: "x", count: width), foreground: colour))
        }
    }

    private enum Counters {
        nonisolated(unsafe) static var measures = 0
        nonisolated(unsafe) static var renders = 0
        static func reset() {
            measures = 0
            renders = 0
        }
    }

    private static func frame(colour: Color, tui: TUIContext) -> FrameBuffer {
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { index in CountingCell(width: 3 + index % 5) }
            }
            .foregroundStyle(colour)
        }
        let context = RenderContext(availableWidth: 40, availableHeight: 6, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.renderCache.removeInactive()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    @Test("New colour: every row re-renders, no row is re-measured")
    func colourChangeKeepsSizes() {
        let tui = TUIContext()
        _ = Self.frame(colour: .ansi(.red), tui: tui)
        _ = Self.frame(colour: .ansi(.red), tui: tui)
        Counters.reset()
        let steady = Self.frame(colour: .ansi(.red), tui: tui)
        // All 40 rows draw (the ScrollView clips, it does not window here), so a
        // warm frame serves 40 buffers and the verifier re-renders each once.
        #expect(
            Counters.measures == 0 && Counters.renders == verifierRenders(hits: 40),
            "warm: \(Counters.measures)/\(Counters.renders)")

        Counters.reset()
        let recoloured = Self.frame(colour: .ansi(.green), tui: tui)
        #expect(recoloured.lines.first != steady.lines.first, "the ink changed")
        #expect(Counters.renders >= 40, "every row re-rendered: \(Counters.renders)")
        #expect(Counters.measures == 0, "no row was re-measured for a colour: \(Counters.measures)")
    }
}
