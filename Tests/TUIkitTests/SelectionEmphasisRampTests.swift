//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectionEmphasisRampTests.swift
//
//  A pulse ramp is a pure function of its two endpoints and the terminal's
//  colour depth — never of the frame being coloured — so a cycle needs exactly
//  one, and building it per frame is invisible in the output and expensive in
//  the profile. These tests count the builds, because counting is the only
//  thing that can tell the two arrangements apart.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("Selection emphasis pulse ramp")
struct SelectionEmphasisRampTests {

    /// A regular-speed pulse: 800 ms cycle over 50 ms cursor ticks.
    private func cycle(
        animation: TextCursorStyle.Animation = .pulse, isFocused: Bool = true, ticks: Int = 16
    ) -> SelectionEmphasisCycle {
        SelectionEmphasisCycle(
            frames: (0..<ticks).map { tick in
                SelectionEmphasis(
                    isFocused: isFocused, animation: animation,
                    phase: Double(tick) / Double(ticks), blinkOn: tick.isMultiple(of: 2))
            },
            step: 0)
    }

    private let dim = Color.rgb(20, 24, 30)
    private let bright = Color.rgb(90, 200, 250)

    /// Pinning the depth is REQUIRED, not tidiness: `pulseRamp` returns `nil`
    /// without building anything at truecolor, and the test runner's own
    /// environment detects as truecolor — so unpinned every count below is zero
    /// and every assertion passes vacuously. Task-local, so a parallel suite is
    /// unaffected.
    ///
    /// The body must not suspend: the counter is process-wide, and holding the
    /// main actor throughout is what keeps another test's rendering out of the
    /// delta.
    private func counting(_ body: () -> Void) -> Int {
        ColorDepth.withCurrent(.palette256) {
            let before = SelectionEmphasis.rampBuilds
            body()
            return SelectionEmphasis.rampBuilds - before
        }
    }

    @Test("A run builds one ramp for the whole cycle, not one per frame")
    func runBuildsOneRampPerCycle() {
        let cycle = self.cycle()
        let builds = counting {
            _ = cycle.run(dim: dim, bright: bright, offsetX: 0, offsetY: 0) { _ in "x" }
        }
        #expect(builds == 1, "one ramp for \(cycle.frames.count) frames, built \(builds)")
    }

    @Test("The glyph run does too — it is the route the built-ins take")
    func glyphRunBuildsOneRampPerCycle() {
        let cycle = self.cycle()
        let builds = counting {
            _ = cycle.run("●", dim: dim, bright: bright, offsetX: 0, offsetY: 0)
        }
        #expect(builds == 1, "one ramp for \(cycle.frames.count) frames, built \(builds)")
    }

    @Test("colors() builds one as well")
    func colorsBuildsOneRampPerCycle() {
        let cycle = self.cycle()
        let builds = counting { _ = cycle.colors(dim: dim, bright: bright) }
        #expect(builds == 1, "built \(builds)")
    }

    @Test("A blink cycle builds none — nothing reads a ramp it never fades along")
    func blinkBuildsNoRamp() {
        let blink = cycle(animation: .blink)
        let runBuilds = counting {
            _ = blink.run(dim: dim, bright: bright, offsetX: 0, offsetY: 0) { _ in "x" }
        }
        let colorBuilds = counting { _ = blink.colors(dim: dim, bright: bright) }
        let nowBuilds = counting { _ = blink.colorNow(dim: dim, bright: bright) }
        #expect(runBuilds == 0, "built \(runBuilds)")
        #expect(colorBuilds == 0, "built \(colorBuilds)")
        #expect(nowBuilds == 0, "built \(nowBuilds)")
    }

    @Test("An unfocused cycle builds none either — it sits at bright")
    func unfocusedBuildsNoRamp() {
        let unfocused = cycle(isFocused: false)
        let builds = counting {
            _ = unfocused.colors(dim: dim, bright: bright)
        }
        #expect(builds == 0, "built \(builds)")
    }

    @Test("Hoisting the ramp changes no colour")
    func hoistingIsBehaviourPreserving() {
        // The safety net under all of the above: `run` and `colors` must agree
        // frame for frame with the per-frame `color(dim:bright:)` they replaced,
        // or "the same work, done once" would be the wrong description.
        let cycle = self.cycle()
        ColorDepth.withCurrent(.palette256) {
            let hoisted = cycle.colors(dim: dim, bright: bright)
            let perFrame = cycle.frames.map { $0.color(dim: dim, bright: bright) }
            #expect(hoisted == perFrame)
        }
    }
}
