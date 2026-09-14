//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabChipBreathAlphaTests.swift
//
//  A focused TabView's active chip breathes its label from a black or white
//  resting tone to the accent. The resting end is opaque by construction; the
//  accent carried a faded tint's or palette's alpha, so the breath's alpha moved
//  with its phase, and every frame of the chip's run was blended at the alpha of
//  whichever one the strip happened to draw (§29). The accent is spent over the
//  chip's surface now, then floored, and every phase is opaque.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A tab chip's breath is opaque at every phase")
struct TabChipBreathAlphaTests {

    /// Every shipped palette under a half-faded tint, and one whose every slot is
    /// faded — the chip's surface included.
    private var palettes: [any Palette] {
        PaletteRegistry.all.map { TintedPalette(base: $0, tint: $0.accent.opacity(0.5)) }
            + [FadedAll()]
    }

    /// Every PHASE, not the two ends: the drift is in the middle, where a cycle
    /// interpolates alpha as a fourth channel between ends that disagree (§29.3).
    @Test(
        "Every phase of a focused chip's label is opaque, and its loud end stays readable",
        arguments: TextCursorStyle.Animation.allCases)
    func everyPhaseIsOpaque(animation: TextCursorStyle.Animation) {
        var offenders: [String] = []
        var unreadable: [String] = []
        for palette in palettes {
            let chip = chip(palette: palette, animation: animation)
            let colors = chip.cycle.colors(dim: chip.labelDim, bright: chip.labelBright)
            if !colors.allSatisfy(\.isOpaque) || !chip.labelNow.isOpaque {
                offenders.append("\(palette.name): \(colors.map(\.alpha))")
            }
            // Measured as the floor measures it: both colours through the 256 cube.
            let rendered = chip.labelBright.downsampledToPalette256()
                .contrastRatio(against: chip.surface.downsampledToPalette256())
            if rendered < ViewConstants.labelContrastFloor {
                unreadable.append("\(palette.name): \(rendered)")
            }
        }
        #expect(offenders.isEmpty, "the chip's breath carries an alpha: \(offenders)")
        #expect(unreadable.isEmpty, "the loud end falls under the floor: \(unreadable)")
    }

    /// The compact strip draws its active chip at the breath's current phase and
    /// claims what that phase owes, then replays every other phase under that one
    /// claim. With no cursor timer running, the current phase is the first — the
    /// pulse's BRIGHT end, which carried the faded accent: so the label claimed half
    /// its ink, and every frame of the run was blended at it.
    @Test("A focused compact strip's breathing chip owes no ink")
    func breathingChipOwesNoInk() throws {
        let palettes: [any Palette] = [
            FadedAll(), TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5)),
        ]
        for palette in palettes {
            let view = TabView(selection: .constant(1)) {
                Tab("One", value: 0) { Text("first") }
                Tab("Two", value: 1) { Text("second") }
            }
            .tabViewStyle(.compact)
            let context = makeRenderContext(width: 30, height: 6) { environment, _ in
                environment.palette = palette
            }
            // Rendered twice, so the frame asserted on is not the one the strip
            // registered its focus in.
            _ = renderToBuffer(view, context: context)
            let drawn = renderToBuffer(view, context: context)
            let label = try #require(
                cells(of: "T", in: drawn).first, "\(palette.name): \(drawn.lines.map(\.stripped))")
            #expect(
                drawn.animatedCells.contains { $0.offsetY == label.row },
                "\(palette.name): the active chip does not breathe")
            for column in label.column..<(label.column + 3) {
                let owes = owed(atColumn: column, row: label.row, in: drawn)
                #expect(owes.ink == 1, "\(palette.name): the breathing label's (\(column), \(label.row)) owes \(owes)")
            }
        }
    }

    /// The bordered strip draws its labels through a raw colorize, so under a faded
    /// tint alone — every other colour opaque — the breath's translucent loud end
    /// went to the emitter directly: a trap in a debug build. The first phase is
    /// that loud end, with no cursor timer running.
    @Test("A focused bordered strip renders under a faded tint, and breathes")
    func borderedStripUnderAFadedTint() throws {
        let palette = TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5))
        let view = TabView(selection: .constant(1)) {
            Tab("One", value: 0) { Text("first") }
            Tab("Two", value: 1) { Text("second") }
        }
        .tabViewStyle(.bordered)
        let context = makeRenderContext(width: 30, height: 10) { environment, _ in
            environment.palette = palette
        }
        _ = renderToBuffer(view, context: context)
        let drawn = renderToBuffer(view, context: context)
        let label = try #require(cells(of: "T", in: drawn).first, "\(drawn.lines.map(\.stripped))")
        #expect(drawn.animatedCells.contains { $0.offsetY == label.row }, "the active chip does not breathe")
    }

    // MARK: - Helpers

    /// Built as a TabView builds it: on its page-level surface, resting in black or
    /// white for that surface.
    private func chip(palette: any Palette, animation: TextCursorStyle.Animation) -> ActiveChipCycle {
        var environment = EnvironmentValues()
        environment.palette = palette
        environment.selectionIndicatorStyle = animation
        let context = RenderContext(
            availableWidth: 20, availableHeight: 3, environment: environment, tuiContext: TUIContext())
        let surface = palette.liftedBackground.resolve(with: palette)
        return ActiveChipCycle(
            surface: surface,
            restingLabel: _TabViewCore<Int>.contrastingForeground(for: surface, palette: palette),
            palette: palette, isFocused: true, context: context)
    }
}
