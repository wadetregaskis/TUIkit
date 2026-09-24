//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayedEraseFieldTests.swift
//
//  On every host that advances too little over some glyph — Apple Terminal,
//  iTerm2, Ghostty, Warp (`Documentation/Terminal-compatibility.md`) — the
//  writer's cursor-advance compensation puts an erase (`ECH`, `ESC[nX`) in front
//  of it, and an erase paints in whatever background is in force at that moment.
//  So when a replayed frame is compensated matters as much as how: its fields
//  have to be in force first. Compensated before its fields were restated, a
//  glyph after a reset was erased over the terminal's own background; with the
//  page put back after every reset first, it was erased over the page's,
//  whatever container it sat in.
//
//  The rows are rendered and built the way the run loop builds them, with each
//  host's writer, so the erase the render wrote is the oracle for the one the
//  replay writes: same cells, same count, same field.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("A replayed frame erases in the field of the cells it erases")
struct ReplayedEraseFieldTests {

    /// Every host that erases under a glyph it advances too little over, and a
    /// glyph it does that for.
    enum Host: String, CaseIterable, Sendable {
        case appleTerminal, iTerm2, ghostty, warp

        @MainActor var writer: FrameDiffWriter {
            FrameDiffWriter(
                isAppleTerminal: self == .appleTerminal, isITerm2: self == .iTerm2,
                isGhostty: self == .ghostty, isWarp: self == .warp, isTmux: false)
        }

        /// Two cells claimed, fewer advanced — measured per host; see
        /// `Documentation/Terminal-compatibility.md`.
        var glyph: String {
            switch self {
            case .appleTerminal, .iTerm2: "\u{2699}\u{FE0F}"  // ⚙️
            case .ghostty: "\u{2B1B}\u{FE0E}"  // ⬛︎
            case .warp: "\u{1F1E6}"  // a lone regional indicator
            }
        }
    }

    enum Ground: String, CaseIterable, Sendable {
        /// The glyph sits on the page.
        case page
        /// The glyph sits on a container's own field, in a row on the page.
        case panel
    }

    private static let page = "\u{1B}[48;2;5;10;5m"
    private static let panel = Color.rgb(13, 26, 13)
    private static let width = 12

    /// A focus breath's frames for the glyph, opening on the collapsed reset the
    /// opacity resolution and `collapsingAdjacentSGR()` both spell — the one a
    /// search for the literal `ESC[0m` does not see.
    private static func frames(_ glyph: String) -> [String] {
        ["\u{1B}[0;38;5;35m" + glyph + ANSIRenderer.reset, "\u{1B}[0;38;5;34m" + glyph + ANSIRenderer.reset]
    }

    /// `ab`, then the glyph — breathing — on `ground`, then `z`.
    @ViewBuilder
    private func row(_ host: Host, on ground: Ground) -> some View {
        let glyph = Text(host.glyph).animatedCells([
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: host.glyph.strippedLength, frames: Self.frames(host.glyph),
                clock: .content)
        ])
        switch ground {
        case .page:
            HStack(spacing: 0) { Text("ab"); glyph; Text(" z") }
        case .panel:
            HStack(spacing: 0) {
                Text("ab")
                HStack(spacing: 0) { Text(" "); glyph; Text(" ") }.background(Self.panel)
                Text("z")
            }
        }
    }

    /// Every erase the replay writes runs in the background the render erased
    /// the same cells in, and every cell keeps the field it was drawn on.
    ///
    /// The render is right by construction: `buildLine` compensates the whole
    /// row after every container has painted it. The replay compensates a
    /// frame that has been through none of that, so where its erase lands
    /// relative to the frame's fields is the whole question — ahead of them, a
    /// wide glyph's second cell keeps whatever the erase painted, on every tick.
    @Test(
        "Every erase in a replayed frame runs in the render's field",
        arguments: Host.allCases, Ground.allCases)
    func erasesRunInTheRendersField(host: Host, ground: Ground) throws {
        let writer = host.writer
        let buffer = ColorDepth.withCurrent(.truecolor) {
            renderToScreen(row(host, on: ground), context: makeRenderContext(width: Self.width, height: 1))
        }
        let run = try #require(buffer.animatedCells.first, "the glyph left no run")
        let built = writer.buildOutputLines(
            buffer: buffer, terminalWidth: Self.width, terminalHeight: 1,
            bgCode: Self.page, reset: ANSIRenderer.reset)[0]
        let rendered = erasures(built)
        try #require(!rendered.isEmpty, "\(host) does not erase under \(host.glyph.debugDescription): nothing to test")
        let field = paintedCells(built)[run.offsetX].background
        #expect(field == (ground == .page ? Self.page : "\u{1B}[48;2;13;26;13m"), "the fixture's field")
        #expect(rendered.allSatisfy { $0.background == field }, "the render erased off its field: \(rendered)")

        for frame in run.frames {
            let patched = writer.patchingAnimatedRun(
                run, showing: frame, in: built, fields: run.fields(onPage: Self.page))
            let replayed = erasures(patched)
            #expect(
                replayed == rendered,
                """
                \(host) on the \(ground): the replay erased \(replayed) where the render erased \(rendered): \
                \(patched.debugDescription)
                """)
            #expect(
                paintedCells(patched).map(\.background) == paintedCells(built).map(\.background),
                "\(host) on the \(ground): a cell changed field")
        }
    }
}
