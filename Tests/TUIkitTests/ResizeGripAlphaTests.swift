//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ResizeGripAlphaTests.swift
//
//  A resizable view's grips under a faded tint or palette: every frame at its
//  opaque spelling, and each grip cell claiming its ink and the page's field
//  (§62). Before, the still frame handed the raw tint to the emitter.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A resizable view's grips under a faded palette")
struct ResizeGripAlphaTests {

    /// Rendered under `palette`, with a focus manager of its own when `focused` — so
    /// the resizable view, the only thing registering, takes the focus.
    private func render<V: View>(_ view: V, palette: any Palette, focused: Bool) -> FrameBuffer {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = palette
        environment.applyRuntimeServices(from: tuiContext)
        if focused { environment.focusManager = FocusManager() }
        let context = RenderContext(
            availableWidth: 30, availableHeight: 6, environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    /// The box, and the grips it wears: every cell whose glyph differs from the same
    /// box's without `.userResizable()`.
    private func grips(
        palette: any Palette, focused: Bool, tint: Color? = nil
    ) -> (drawn: FrameBuffer, cells: [(column: Int, row: Int)]) {
        let box = Text("hello").frame(width: 12, height: 3).border()
        let drawn: FrameBuffer
        let plain: FrameBuffer
        if let tint {
            drawn = render(box.userResizable().tint(tint), palette: palette, focused: focused)
            plain = render(box.tint(tint), palette: palette, focused: focused)
        } else {
            drawn = render(box.userResizable(), palette: palette, focused: focused)
            plain = render(box, palette: palette, focused: focused)
        }
        let cells = zip(drawn.lines, plain.lines).enumerated().flatMap { row, pair in
            zip(Array(pair.0.stripped), Array(pair.1.stripped)).enumerated().compactMap { column, glyphs in
                glyphs.0 == glyphs.1 ? nil : (column: column, row: row)
            }
        }
        return (drawn, cells)
    }

    /// At rest the grips are the border's colour, floored against the page and keeping
    /// its alpha, on the page's own background: each owes both.
    @Test("Resting grips under a faded palette owe the border's ink and the page's field")
    func restingGripsClaim() throws {
        let palette = FadedAll()
        let (drawn, cells) = grips(palette: palette, focused: false)
        try #require(!cells.isEmpty, "no grip was drawn: \(drawn.lines.map(\.stripped))")
        for (column, row) in cells {
            let owes = owed(atColumn: column, row: row, in: drawn)
            #expect(
                owes.ink == owed(palette.border) && owes.field == owed(palette.background),
                "grip (\(column), \(row)) owes \(owes)")
        }
    }

    /// Focused, the grips breathe through `activeSection`, whose ends are both spent:
    /// the ink owes nothing in any frame, the field still owes the page's alpha, and
    /// every run replays onto the cells the render drew.
    @Test("Focused grips under a faded palette breathe opaque ink over the page's field")
    func focusedGripsClaim() throws {
        let palette = FadedAll()
        let (drawn, cells) = grips(palette: palette, focused: true)
        try #require(!cells.isEmpty, "no grip was drawn: \(drawn.lines.map(\.stripped))")
        #expect(!drawn.animatedCells.isEmpty, "focused grips breathe")
        expectReplayIsIdentity(drawn, "a grip's run moved the cells")
        for (column, row) in cells {
            let owes = owed(atColumn: column, row: row, in: drawn)
            #expect(owes.ink == 1 && owes.field == owed(palette.background), "grip (\(column), \(row)) owes \(owes)")
        }
    }

    /// Under a faded tint alone the breath's ends are spent and the page is opaque, so
    /// the grips claim nothing — and the frame drawn is the one the run replays.
    @Test("Focused grips under a faded tint draw what their run replays")
    func focusedGripsUnderAFadedTint() throws {
        let (drawn, cells) = grips(palette: SystemPalette.default, focused: true, tint: Color.red.opacity(0.5))
        try #require(!cells.isEmpty, "no grip was drawn: \(drawn.lines.map(\.stripped))")
        #expect(!drawn.animatedCells.isEmpty, "focused grips breathe")
        expectReplayIsIdentity(drawn, "a grip's run moved the cells")
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    /// The control: an opaque palette's grips claim nothing, at rest or focused.
    @Test("An opaque palette's grips claim nothing", arguments: [false, true])
    func opaqueGripsClaimNothing(focused: Bool) throws {
        let (drawn, cells) = grips(palette: SystemPalette.default, focused: focused)
        try #require(!cells.isEmpty, "no grip was drawn: \(drawn.lines.map(\.stripped))")
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }
}
