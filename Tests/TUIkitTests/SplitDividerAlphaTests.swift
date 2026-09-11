//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitDividerAlphaTests.swift
//
//  A resizable NavigationSplitView's divider under a faded palette or tint: its
//  grip dots and pulsing background at their opaque spelling, and the dots'
//  alpha claimed (§63). Before, a faded tertiary rung trapped at rest, and a
//  faded accent trapped on hover.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A split view's divider under a faded palette")
struct SplitDividerAlphaTests {

    /// What the resize machinery needs — a focus manager, state storage, a mouse
    /// dispatcher — under `palette`.
    private func context(palette: any Palette) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = palette
        return RenderContext(
            availableWidth: 60, availableHeight: 12, environment: environment, tuiContext: TUIContext())
    }

    /// One render pass, bracketed as the run loop brackets it.
    private func frame(_ view: some View, _ context: RenderContext) -> FrameBuffer {
        let states = context.environment.stateStorage!
        let focus = context.environment.focusManager!
        states.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        states.endRenderPass()
        return buffer
    }

    private var split: some View {
        NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
    }

    /// The claims covering the divider's column.
    private func onTheDivider(_ drawn: FrameBuffer, column: Int) -> [OpacityRegion] {
        drawn.opacityRegions.filter { $0.offsetX <= column && column < $0.offsetX + $0.width }
    }

    /// At rest the dots are the quiet tertiary rung, which a wholly faded palette
    /// fades: each owes its alpha as ink, and the rest of the divider owes nothing.
    @Test("A resting divider's dots owe the quiet rung's alpha")
    func restingDotsClaim() throws {
        let palette = FadedAll()
        try #require(!palette.foregroundTertiary.isOpaque, "the premise")
        let drawn = frame(split, context(palette: palette))
        let dots = cells(of: "◦", in: drawn)
        try #require(dots.count == 3, "\(drawn.lines.map(\.stripped))")
        for (column, row) in dots {
            let owes = owed(atColumn: column, row: row, in: drawn)
            #expect(
                owes.ink == owed(palette.foregroundTertiary) && owes.field == 1,
                "dot (\(column), \(row)) owes \(owes)")
        }
        let column = dots[0].column
        for row in 0..<drawn.height where !dots.contains(where: { $0.row == row }) {
            let owes = owed(atColumn: column, row: row, in: drawn)
            #expect(owes.ink == 1 && owes.field == 1, "divider (\(column), \(row)) owes \(owes)")
        }
    }

    /// Hovered, the dots breathe toward the accent. That breath's bright end kept a
    /// faded tint's alpha while its dim end spent it; both are spent now, so every
    /// frame is opaque, nothing on the divider claims, and each run replays onto the
    /// cells drawn.
    @Test("A hovered divider's dots breathe opaque under a faded tint")
    func hoveredDotsUnderAFadedTint() throws {
        let context = context(palette: SystemPalette.default)
        let view = split.tint(Color.red.opacity(0.5))
        let dispatcher = try #require(context.environment.mouseEventDispatcher)
        // Motion must be on for the dispatcher to synthesise an enter.
        dispatcher.setActiveSupport(MouseSupport(clicks: true, scrolling: true, drag: true, motion: true))
        let resting = frame(view, context)
        dispatcher.setRegions(resting.hitTestRegions)
        let dots = cells(of: "◦", in: resting)
        try #require(dots.count == 3, "\(resting.lines.map(\.stripped))")
        let centre = dots[1]
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .moved, x: centre.column, y: centre.row))
        let hovered = frame(view, context)
        #expect(!hovered.animatedCells.isEmpty, "the hovered dots breathe")
        expectReplayIsIdentity(hovered, "a divider run moved the cells")
        let claims = onTheDivider(hovered, column: centre.column)
        #expect(claims.isEmpty, "\(claims)")
    }

    /// Focused, the whole divider's background breathes through `accentFillPulse`,
    /// spent at both ends, and the dots keep the quiet rung: each owes that rung's
    /// alpha over an opaque field in every frame, and every run replays onto the
    /// cells drawn.
    @Test("A focused divider under a faded palette claims its dots over an opaque field")
    func focusedDividerClaims() throws {
        let palette = FadedAll()
        let context = context(palette: palette)
        let focus = try #require(context.environment.focusManager)
        _ = frame(split, context)
        let section = try #require(dividerSectionID(in: focus))
        focus.activateSection(id: section)
        let drawn = frame(split, context)
        #expect(!drawn.animatedCells.isEmpty, "the focused divider breathes")
        expectReplayIsIdentity(drawn, "a divider run moved the cells")
        let dots = cells(of: "◦", in: drawn)
        try #require(dots.count == 3, "\(drawn.lines.map(\.stripped))")
        for (column, row) in dots {
            let owes = owed(atColumn: column, row: row, in: drawn)
            #expect(
                owes.ink == owed(palette.foregroundTertiary) && owes.field == 1,
                "dot (\(column), \(row)) owes \(owes)")
        }
    }

    /// The control: an opaque palette's divider claims nothing, resting or focused.
    @Test("An opaque palette's divider claims nothing")
    func opaqueDividerClaimsNothing() throws {
        let context = context(palette: SystemPalette.default)
        let focus = try #require(context.environment.focusManager)
        let resting = frame(split, context)
        let section = try #require(dividerSectionID(in: focus))
        focus.activateSection(id: section)
        let focused = frame(split, context)
        for drawn in [resting, focused] {
            let column = try #require(cells(of: "◦", in: drawn).first?.column)
            let claims = onTheDivider(drawn, column: column)
            #expect(claims.isEmpty, "\(claims)")
        }
    }
}
