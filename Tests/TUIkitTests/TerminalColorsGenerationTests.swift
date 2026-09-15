//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorsGenerationTests.swift
//
//  What is kept from the terminal's colours goes when they change. The render
//  cache clears at the next pass once `TerminalColors.generation` has moved, and
//  the pulse ramp, the quantised ramp and the chrome track each key their memo on
//  it, so colours reported after a frame are not served answers built from the
//  colours before them.
//
//  None of these tests moves the process generation. That would clear the caches
//  of every suite running beside them. Each memo takes the generation as an
//  argument instead, and the render cache's recorded generation is aged directly.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling
@testable import TUIkitView

/// A page and ink that are the terminal's own, with an accent that is not.
private struct CarriedPagePalette: Palette {
    let id = "carried-page"
    let name = "Carried page"
    let background = Color(value: .terminalBackground)
    let foreground = Color(value: .terminalForeground)
    let accent = Color.rgb(90, 200, 250)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@MainActor
@Suite("What is kept from the terminal's colours goes when they change")
struct TerminalColorsGenerationTests {

    /// One Dark's pair, as the carried-colour tests use.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    private static let page = Color(value: .terminalBackground)
    private static let accent = Color.rgb(90, 200, 250)

    // Each memo test asks under a generation no real caller uses, since the
    // process counter starts at 0 and only counts up, and under its own pair, so
    // no other test can have filled or be filling the same entry.

    @Test("A move in the terminal's colours clears the render cache at the next pass, and only that pass")
    func renderCacheClearsOnAMove() {
        let cache = RenderCache()
        cache.store(
            identity: ViewIdentity(path: "A"), view: 1, buffer: FrameBuffer(text: "a"),
            contextWidth: 80, contextHeight: 24)
        cache.store(
            identity: ViewIdentity(path: "B"), view: 2, buffer: FrameBuffer(text: "b"),
            contextWidth: 80, contextHeight: 24)

        cache.renderedUnderTerminalColorsGeneration = TerminalColors.generation &- 1
        cache.beginRenderPass()
        #expect(cache.isEmpty, "buffers rendered under the old colours survived the pass")
        #expect(cache.stats.clears == 1)

        cache.store(
            identity: ViewIdentity(path: "A"), view: 1, buffer: FrameBuffer(text: "a"),
            contextWidth: 80, contextHeight: 24)
        cache.beginRenderPass()
        #expect(cache.count == 1, "the pass after the move cleared again")
    }

    /// Asked once while the terminal has said nothing, and once, a generation
    /// later, with its colours reported. The second is not the first, and it is
    /// what a cold ask under the reported colours gives, at a generation nothing
    /// has asked under: the memo missed.
    @Test("The pulse ramp is built again when the generation moves")
    func pulseRampMissesOnAMove() {
        let before = TerminalColors.withCurrent(.unknown) {
            Color.pulseRamp(
                from: Self.page, to: Self.accent, depth: .palette256, terminalColorsGeneration: -1_001)
        }
        TerminalColors.withCurrent(Self.reported) {
            let after = Color.pulseRamp(
                from: Self.page, to: Self.accent, depth: .palette256, terminalColorsGeneration: -1_000)
            let cold = Color.pulseRamp(
                from: Self.page, to: Self.accent, depth: .palette256, terminalColorsGeneration: -999)
            #expect(after != before, "a moved generation was served the ramp built before it: \(after)")
            #expect(after == cold, "not the ramp the reported colours give")
        }
    }

    @Test("The quantised ramp is built again when the generation moves")
    func quantisedRampMissesOnAMove() {
        let gradient = Gradient(colors: [Self.page, Color.rgb(250, 120, 60)])
        for depth in [ColorDepth.truecolor, .palette256] {
            let before = TerminalColors.withCurrent(.unknown) {
                Color.quantisedRamp(gradient, count: 12, depth: depth, terminalColorsGeneration: -2_001)
            }
            TerminalColors.withCurrent(Self.reported) {
                let after = Color.quantisedRamp(
                    gradient, count: 12, depth: depth, terminalColorsGeneration: -2_000)
                let cold = Color.quantisedRamp(
                    gradient, count: 12, depth: depth, terminalColorsGeneration: -1_999)
                #expect(after != before, "@\(depth): a moved generation was served the ramp built before it")
                #expect(after == cold, "@\(depth): not the ramp the reported colours give")
            }
        }
    }

    /// A rung too close to the reported page. While the page cannot be measured,
    /// no step can be shown to clear it, so the rung stands; once reported, the
    /// walk moves it. Served from the memo, it would stand in both.
    @Test("The chrome track is resolved again when the generation moves")
    func chromeTrackMissesOnAMove() {
        let palette = CarriedPagePalette()
        let rung = Color.rgb(44, 48, 57)
        let before = TerminalColors.withCurrent(.unknown) {
            ChromeTrack.track(from: rung, in: palette, terminalColorsGeneration: -3_001)
        }
        TerminalColors.withCurrent(Self.reported) {
            let after = ChromeTrack.track(from: rung, in: palette, terminalColorsGeneration: -3_000)
            let cold = ChromeTrack.resolvedTrack(
                base: rung, accent: palette.accent, page: palette.background, ink: palette.foreground)
            #expect(cold != before, "the fixture: the reported page must move the rung")
            #expect(after == cold, "a moved generation was served the track resolved before it")
        }
    }
}
