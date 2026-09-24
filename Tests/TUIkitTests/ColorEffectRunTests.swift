//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorEffectRunTests.swift
//
//  A colour effect recolours the runs of the subtree it covers exactly as it
//  recolours the lines: every frame's ink and field, and what the containers
//  inside the effect painted beneath the runs' cells (`AnimatedCellRun.ground`).
//  The replay draws a frame over its ground wherever the frame names no field,
//  so a ground the effect left alone put a spinner inside `.background(.blue)
//  .colorInvert()` back on blue on every tick, and frames the effect left alone
//  drew its glyph in the ink it had before the effect.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("A colour effect recolours the runs it covers")
struct ColorEffectRunTests {

    /// Every colour effect, at an amount that changes a colour.
    enum Effect: String, CaseIterable, Sendable {
        case colorInvert, grayscale, hueRotation, brightness, contrast, saturation, colorMultiply

        @MainActor @ViewBuilder
        func applied(to view: some View) -> some View {
            switch self {
            case .colorInvert: view.colorInvert()
            case .grayscale: view.grayscale(1)
            case .hueRotation: view.hueRotation(.degrees(90))
            case .brightness: view.brightness(0.3)
            case .contrast: view.contrast(0.5)
            case .saturation: view.saturation(0.3)
            case .colorMultiply: view.colorMultiply(Color.rgb(255, 128, 0))
            }
        }
    }

    /// A spinner on a colour of its own, under the effect — the review's shape.
    private func rendered(_ effect: Effect) -> FrameBuffer {
        let spinner = Spinner().foregroundStyle(Color.rgb(40, 200, 40)).background(Color.rgb(40, 40, 200))
        return ColorDepth.withCurrent(.truecolor) {
            renderToScreen(effect.applied(to: spinner), context: makeRenderContext(width: 8, height: 1))
        }
    }

    @Test("The drawn frame, replayed over its ground, is the recoloured row", arguments: Effect.allCases)
    func replayIsTheRecolouredRow(effect: Effect) throws {
        let buffer = rendered(effect)
        let run = try #require(buffer.animatedCells.first, "\(effect) dropped the spinner's run")
        let cells = paintedCells(buffer.lines[run.offsetY])
        let shown = (run.offsetX..<(run.offsetX + run.width)).map { cells[$0] }
        // Not vacuous: the effect moved both colours away from the spinner's own.
        #expect(shown.allSatisfy { $0.background != "\u{1B}[48;2;40;40;200m" }, "\(effect) left the field")
        // What is under the cells is what the row shows under them.
        #expect(run.groundFields(onPage: "").map(spelled) == shown.map(\.background), "\(effect): the ground")
        // And the frame drawn at render time, spliced back, draws the same cells
        // in the same ink on the same field.
        expectReplayIsIdentity(buffer, "\(effect): the replay does not draw what the effect drew")
    }
}
