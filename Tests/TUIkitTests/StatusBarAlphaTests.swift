//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarAlphaTests.swift
//
//  `StatusBarState.highlightColor` and `.labelColor` are public `var`s, and each
//  paints a DIFFERENT run of every item.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A translucent status bar colour")
struct StatusBarAlphaTests {

    private func faded(_ base: Color, _ alpha: UInt8) -> Color {
        var colour = base
        colour.alpha = alpha
        return colour
    }

    private func bar(
        highlight: Color? = nil, label: Color? = nil, width: Int = 40
    ) -> FrameBuffer {
        let view = StatusBar(
            userItems: [StatusBarItem(shortcut: "q", label: "Quit")],
            systemItems: [],
            style: .compact,
            alignment: .justified,
            highlightColor: highlight,
            labelColor: label)
        let context = RenderContext(
            availableWidth: width, availableHeight: view.height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    @Test("Opaque colours claim nothing")
    func opaqueClaimsNothing() {
        #expect(bar().opacityRegions.isEmpty)
        #expect(bar(highlight: .ansi(.cyan), label: .ansi(.white)).opacityRegions.isEmpty)
    }

    @Test("A faded highlight claims the shortcut and not the label")
    func fadedHighlight() throws {
        let drawn = bar(highlight: faded(.ansi(.cyan), 128), label: .ansi(.white))
        let claim = try #require(drawn.opacityRegions.first)
        #expect(drawn.opacityRegions.count == 1, "one run, not the whole item")
        #expect(claim.width == 1, "the shortcut `q` is one cell: \(claim)")
        #expect(claim.inkOpacity == 128.0 / 255)
    }

    @Test("A faded label claims the label and not the shortcut")
    func fadedLabel() throws {
        let drawn = bar(highlight: .ansi(.cyan), label: faded(.ansi(.white), 64))
        let claim = try #require(drawn.opacityRegions.first)
        #expect(drawn.opacityRegions.count == 1)
        #expect(claim.offsetX >= 1, "starts after the shortcut: \(claim)")
        #expect(claim.width == 5, "` Quit` — the separating space is the label's")
        #expect(claim.inkOpacity == 64.0 / 255)
    }

    @Test("Both faded claims two runs, each at its own alpha")
    func bothFaded() {
        let drawn = bar(highlight: faded(.ansi(.cyan), 128), label: faded(.ansi(.white), 64))
        #expect(drawn.opacityRegions.count == 2, "\(drawn.opacityRegions)")
        // The two runs are adjacent and disjoint: together they are the item, and
        // neither the gap nor the last cell belongs to nobody. Claimed twice, the
        // overlap would resolve at the product of the two alphas.
        let sorted = drawn.opacityRegions.sorted { $0.offsetX < $1.offsetX }
        #expect(sorted[0].offsetX + sorted[0].width == sorted[1].offsetX, "\(sorted)")
        #expect(sorted[0].inkOpacity != sorted[1].inkOpacity, "each at its own alpha")
    }

    @Test("The bytes are the colours at full strength")
    func bytesAreOpaque() {
        let drawn = bar(highlight: faded(.ansi(.cyan), 128))
        #expect(
            drawn.lines[0].contains(Color.ansi(.cyan).foregroundCodes().joined(separator: ";")),
            "\(drawn.lines[0].debugDescription)")
    }

    /// A bar showing a one-line tooltip under `palette`, over one opaque item — so
    /// the items claim nothing, and every region is the chrome's or the row's.
    private func tooltipBar(style: ChromeStyle, palette: any Palette) -> FrameBuffer {
        let view = StatusBar(
            userItems: [StatusBarItem(shortcut: "q", label: "Quit")], style: style,
            tooltipLines: ["Rebuild the index"])
        var environment = EnvironmentValues()
        environment.palette = palette
        let context = RenderContext(
            availableWidth: 40, availableHeight: view.height, environment: environment,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    /// The tooltip row paints `palette.foregroundSecondary`, and handed it to the
    /// emitter raw: the `isOpaque` assertion in debug, a row at full strength inside
    /// a faded bar in release. `FadedAll` never names that slot — `Palette` defaults
    /// it to `foreground` — which is the point: fading the one is enough to reach
    /// it. The popover presentation of the same tooltip already claimed its text.
    @Test("A faded palette's tooltip row is spelled opaque and claimed, in every bar style")
    func fadedTooltipRowIsClaimed() throws {
        let palette = FadedAll()
        let ink = palette.foregroundSecondary
        let opaqueInk = ink.opaqueSpelling.foregroundCodes().joined(separator: ";")
        // Where the text sits, written out rather than asked of
        // `ChromeStyle.barContentWidth`, which the claim is computed from: flush on
        // the first row of a compact bar and under a rule, and inside a bordered
        // bar's wall and its space of padding on either side.
        let placements: [(style: ChromeStyle, row: Int, column: Int, width: Int)] = [
            (.compact, 0, 0, 40), (.rule, 1, 0, 40), (.bordered, 1, 2, 36),
        ]
        for placement in placements {
            let drawn = tooltipBar(style: placement.style, palette: palette)
            let claims = drawn.opacityRegions.filter {
                $0.offsetY == placement.row && $0.offsetX == placement.column
                    && $0.width == placement.width
            }
            #expect(claims.count == 1, "\(placement.style): \(drawn.opacityRegions)")
            let claim = try #require(claims.first)
            #expect(claim.height == 1, "one wrapped line is one row: \(claim)")
            #expect(claim.inkOpacity == Double(ink.alpha) / 255, "\(placement.style): \(claim)")
            #expect(
                drawn.lines[placement.row].contains(opaqueInk),
                "\(placement.style): \(drawn.lines[placement.row].debugDescription)")
        }
    }
}
