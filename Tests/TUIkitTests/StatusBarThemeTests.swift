//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarThemeTests.swift
//
//  A `StatusBar`'s two colours are drawn from the palette in the environment, on
//  its own and not only when the run loop builds it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A status bar's colours follow the palette")
struct StatusBarThemeTests {

    /// A one-item compact bar, rendered under ``ThemeProbePalette`` in truecolor, so
    /// a role's RGB is spelled out in the bytes.
    private func bar(highlight: Color, label: Color? = nil) -> FrameBuffer {
        let view = StatusBar(
            items: [StatusBarItem(shortcut: "q", label: "Quit")], style: .compact,
            highlightColor: highlight, labelColor: label)
        let context = makeRenderContext(width: 40, height: 3) { env, _ in
            env.palette = ThemeProbePalette()
        }
        return ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
    }

    /// A palette role handed to the bar as its highlight reached the emitter
    /// unresolved, and the emitter traps on a semantic colour.
    @Test("A role as the highlight paints the palette's colour for it")
    func roleHighlightIsResolved() {
        let drawn = bar(highlight: .palette.warning).lines.joined()
        #expect(drawn.contains("38;2;240;200;40"), "\(drawn.debugDescription)")
    }

    @Test("A role as the label colour paints the palette's colour for it")
    func roleLabelIsResolved() {
        let drawn = bar(highlight: .palette.warning, label: .palette.foregroundSecondary)
            .lines.joined()
        #expect(drawn.contains("38;2;170;170;170"), "\(drawn.debugDescription)")
    }

    /// Resolving a role must not drop the alpha the call site gave it: the claim
    /// over the shortcut still carries it.
    @Test("A translucent role as the highlight keeps its alpha in the claim")
    func translucentRoleHighlightKeepsAlpha() throws {
        let drawn = bar(highlight: Color.palette.warning.opacity(0.5))
        let claim = try #require(drawn.opacityRegions.first)
        #expect(drawn.opacityRegions.count == 1, "\(drawn.opacityRegions)")
        #expect(claim.width == 1, "the shortcut `q` is one cell: \(claim)")
        #expect(claim.inkOpacity == 128.0 / 255)
        #expect(drawn.lines.joined().contains("38;2;240;200;40"))
    }
}
