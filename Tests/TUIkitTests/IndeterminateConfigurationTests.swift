//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateConfigurationTests.swift
//
//  The indeterminate side of the "named styles are presets of one recipe"
//  claim: what `.custom(_:)` can say, and that saying the preset's own words
//  produces the preset.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@Suite("Indeterminate configuration")
struct IndeterminateConfigurationTests {

    private let filled = Color.rgb(150, 150, 150)
    private let empty = Color.rgb(80, 80, 80)
    private let accent = Color.rgb(0, 200, 255)

    private func render(_ style: IndeterminateStyle, width: Int = 24, at elapsed: Double) -> String {
        IndeterminateRenderer.render(
            width: width, style: style, fillColor: filled, backgroundColor: empty,
            accentColor: accent, elapsed: elapsed,
            palette: SystemPalette.green
        ).text
    }

    private static let builtIns: [(name: String, style: IndeterminateStyle)] = [
        ("sweep", .sweep), ("barberPole", .barberPole), ("pulse", .pulse),
        ("knightRider", .knightRider), ("gradient", .gradient()),
        ("gradient(c)", .gradient(Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)]))),
    ]

    /// The claim the refactor rests on: a named style is nothing more than a
    /// configuration, so handing its own configuration back through
    /// `.custom(_:)` has to draw the identical frame — byte for byte, at every
    /// point of the cycle, or the presets are a second renderer wearing a hat.
    @Test("Every named style is exactly its own configuration")
    func namedStylesArePresets() {
        for (name, style) in Self.builtIns {
            for step in 0..<12 {
                let elapsed = Double(step) * 0.17
                let named = render(style, at: elapsed)
                let rebuilt = render(.custom(style.configuration), at: elapsed)
                #expect(
                    named == rebuilt,
                    "\(name) at \(elapsed): preset and .custom disagree")
            }
        }
    }

    /// The width contract, which the row builder is the only thing enforcing:
    /// a multi-cell fill coarsens the animation and must never widen it.
    @Test("Every motion draws exactly the width it was asked for")
    func widthIsExact() {
        let fills = ["█", "●", "◢◤", "🎵", "漢字", ""]
        for motion in IndeterminateConfiguration.Motion.allCases {
            for fill in fills {
                for width in [1, 2, 3, 7, 24, 25] {
                    let style = IndeterminateStyle.custom(
                        IndeterminateConfiguration(motion: motion, fill: fill, background: "·"))
                    for step in 0..<5 {
                        let line = render(style, width: width, at: Double(step) * 0.31)
                        #expect(
                            line.strippedLength == width,
                            """
                            \(motion) fill=\(fill.isEmpty ? "<empty>" : fill) width=\(width) \
                            step=\(step): drew \(line.strippedLength) cells — \
                            |\(line.stripped)|
                            """)
                    }
                }
            }
        }
    }

    @Test("A custom fill and background pattern are what gets drawn")
    func customGlyphsAreDrawn() {
        let style = IndeterminateStyle.custom(
            IndeterminateConfiguration(motion: .knightRider, fill: "●", background: "·", period: 4))
        let line = render(style, at: 0.4).stripped
        #expect(line.contains("●"), "the fill: |\(line)|")
        #expect(line.contains("·"), "the background pattern: |\(line)|")
        #expect(!line.contains("█"), "the preset's glyph should be gone: |\(line)|")
    }

    /// `pulse` lights every cell in one colour, and used to emit that as a
    /// single escape and a run of blocks. Per-cell emission would be invisible
    /// on screen and paid again on every replay tick, so the row builder
    /// collapses equal-colour runs — this is what says it still does.
    @Test("One colour across the row is one escape")
    func equalColourCellsShareAnEscape() {
        let line = render(.pulse, width: 40, at: 0.4)
        #expect(line.strippedLength == 40)
        #expect(
            line.utf8.count < 40 * 4,
            "a per-cell escape for a single-colour row: \(line.utf8.count) bytes")
    }

    @Test("The period is what the cycle is built over")
    func periodDrivesTheCycle() {
        let slow = IndeterminateStyle.custom(
            IndeterminateConfiguration(motion: .sweep, period: 4))
        let quick = IndeterminateStyle.custom(
            IndeterminateConfiguration(motion: .sweep, period: 1))
        #expect(IndeterminateRenderer.period(of: slow) == 4)
        #expect(IndeterminateRenderer.period(of: quick) == 1)
        let slowCycle = IndeterminateRenderer.cycle(
            width: 12, style: slow, fillColor: filled, backgroundColor: empty, accentColor: accent,
            palette: SystemPalette.green)
        let quickCycle = IndeterminateRenderer.cycle(
            width: 12, style: quick, fillColor: filled, backgroundColor: empty, accentColor: accent,
            palette: SystemPalette.green)
        #expect(slowCycle.frames.count == 4 * quickCycle.frames.count)
    }

    /// A configuration is a value an app can build from a text field, so the
    /// degenerate ones have to render rather than trap.
    @Test("A non-positive period falls back instead of dividing by zero")
    func degeneratePeriodIsSurvivable() {
        for period in [0.0, -3.0] {
            let style = IndeterminateStyle.custom(
                IndeterminateConfiguration(motion: .sweep, period: period))
            #expect(IndeterminateRenderer.period(of: style) == 1.6)
            #expect(render(style, at: 0.4).strippedLength == 24)
        }
    }

    @Test("A zero or negative extent still lights one cell")
    func extentAlwaysLightsSomething() {
        for extent in [0.0, -1.0] {
            let style = IndeterminateStyle.custom(
                IndeterminateConfiguration(motion: .sweep, extent: extent))
            let line = render(style, at: 0.4).stripped
            #expect(line.contains("█"), "extent \(extent) lit nothing: |\(line)|")
        }
    }

    /// The colours are the motion's to interpret, and a ramp reads them from
    /// dim to bright — so a two-stop ramp of its own must reach the bright end
    /// at the head of the sweep.
    @Test("A custom ramp is what the trail fades through")
    func customRampColoursTheTrail() {
        let period = 1.6
        let style = IndeterminateStyle.custom(
            IndeterminateConfiguration(
                motion: .pulse,
                gradient: Gradient(colors: [.rgb(10, 20, 30), .rgb(240, 230, 220)]),
                period: period))
        // The two ends are reached at exact points of the cycle, not merely
        // approached: `(1 − cos)/2` is 0 at the start of a period and 1 at its
        // midpoint. Sampling on a grid that misses those lands between stops
        // and proves nothing about either end.
        #expect(render(style, width: 4, at: 0).contains("10;20;30"), "the dim end")
        #expect(
            render(style, width: 4, at: period / 2).contains("240;230;220"), "the bright end")
        let frames = (0..<24).map { render(style, width: 4, at: Double($0) * period / 24) }
        #expect(
            !frames.contains { $0.contains("0;200;255") },
            "the palette accent should not appear when colours were given")
    }
}
