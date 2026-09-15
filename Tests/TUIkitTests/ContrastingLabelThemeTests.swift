//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContrastingLabelThemeTests.swift
//
//  A label a built-in view draws on a surface it did not choose — the active tab
//  chip's resting label, a swatch's check mark, a 256-grid index — is the palette's
//  readable ink for that surface, not black or white.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A label on a surface follows the palette")
struct ContrastingLabelThemeTests {

    @Test("A dark surface takes the palette's foreground")
    func darkSurfaceTakesTheForeground() {
        #expect(ContrastingLabel.on(.rgb(10, 10, 10), palette: ThemeProbePalette()) == .rgb(220, 220, 220))
    }

    @Test("A light surface takes the palette's background")
    func lightSurfaceTakesTheBackground() {
        #expect(ContrastingLabel.on(.rgb(250, 250, 250), palette: ThemeProbePalette()) == .rgb(10, 10, 10))
    }

    /// A pin, not a red: `readableText(on:)` and the contrast floor already hand back
    /// the palette's ink on a surface with no RGB (606d7cd8), where the floor used to
    /// walk to white. The tab chip, the swatch mark and the 256-grid index all read it
    /// from here.
    @Test("A surface with no RGB takes the palette's foreground")
    func unmeasurableSurfaceTakesTheForeground() {
        TerminalColors.withCurrent(.unknown) {
            for surface in [Color(value: .terminalBackground), .default] {
                #expect(
                    ContrastingLabel.on(surface, palette: ThemeProbePalette()) == .rgb(220, 220, 220),
                    "on \(surface)")
                #expect(
                    _SwatchGridCore.markEnds(for: surface, palette: ThemeProbePalette()).bright
                        == .rgb(220, 220, 220), "a swatch of \(surface)")
            }
        }
    }

    /// Unfocused, so the active label does not breathe: what is drawn is its resting
    /// colour. Under this palette's dark surface that was white.
    @Test("An unfocused tab strip's active label is the palette's ink")
    func activeTabLabelIsThePalettesInk() throws {
        let view = TabView(selection: .constant(0)) {
            Tab("Alpha", value: 0) { Text("A") }
            Tab("Bravo", value: 1) { Text("B") }
        }
        .tabViewStyle(.bordered)
        let context = makeRenderContext(width: 40, height: 8) { environment, _ in
            environment.palette = ThemeProbePalette()
        }
        // A sentinel registered first holds the focus, so the strip rests.
        context.environment.focusManager?.register(FocusSentinel())
        let drawn = ColorDepth.withCurrent(.truecolor) { renderToBuffer(view, context: context) }
        let label = try #require(cells(of: "l", in: drawn).first, "\(drawn.lines.map(\.stripped))")
        let line = drawn.lines[label.row]
        #expect(
            truecolorInk(line, atColumn: label.column) == "220;220;220", "\(line.debugDescription)")
        #expect(!drawn.lines.joined().contains("38;2;255;255;255"), "\(line.debugDescription)")
    }

    @Test("A 256-grid index is drawn in the palette's ink")
    func gridIndexIsThePalettesInk() {
        let text = ColorDepth.withCurrent(.truecolor) {
            _Color256GridCore.cellText(
                index: 16, cellWidth: 5, mark: nil, showNumbers: true, palette: ThemeProbePalette())
        }
        #expect(text.contains("38;2;220;220;220"), "\(text.debugDescription)")
    }

    /// A pin, not a red: black and white were opaque anyway. The resting end of the
    /// active chip's breath must agree with its loud end, which is spent, so a
    /// translucent ink has to be spent here too.
    @Test("A translucent palette ink comes back opaque")
    func translucentInkIsSpent() {
        var palette = ThemeProbePalette()
        palette.foreground = Color.rgb(220, 220, 220).opacity(0.5)
        #expect(ContrastingLabel.on(.rgb(10, 10, 10), palette: palette).alpha == .max)
    }
}
