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

import Foundation
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

    // MARK: - The shapes that draw a whole cycle

    /// Renders `view` focused, at 256 colours, and returns the ramps built.
    ///
    /// A real render rather than a hand-built cycle, because the defect this
    /// counts is not in the cycle: it is in what each drawing site does WITH
    /// one, and only rendering exercises that.
    private func buildsRendering<V: View>(_ view: V) -> (builds: Int, buffer: FrameBuffer) {
        ColorDepth.withCurrent(.palette256) {
            // `.focusable()` at the call site plus a fresh manager: the first
            // stop registered takes the focus.
            let context = makeRenderContext(width: 30, height: 6)
            let before = SelectionEmphasis.rampBuilds
            let buffer = renderToBuffer(view, context: context)
            return (SelectionEmphasis.rampBuilds - before, buffer)
        }
    }

    @Test("A focused button's caps breathe on one ramp, not one per frame")
    func buttonCapsBuildOneRamp() {
        let (builds, buffer) = buildsRendering(Button("OK") {})
        // Or an unfocused render — which builds nothing at all — would pass.
        #expect(!buffer.animatedCells.isEmpty, "the button did not draw a breath")
        // One: `ButtonCapCycle` builds the breath in its init and both readers
        // — the colour drawn now, and the frames of BOTH end-cap runs — spend
        // that one. It was three (one per cap run, plus `colorNow`'s), and 33
        // before `SelectionEmphasisCycle.run` stopped rebuilding per frame.
        #expect(builds == 1, "built \(builds)")
    }

    @Test("A focused plain button's indicator does too")
    func focusIndicatorBuildsOneRamp() {
        let (builds, buffer) = buildsRendering(Button("OK") {}.buttonStyle(.plain))
        #expect(!buffer.animatedCells.isEmpty, "the button did not draw a breath")
        // One: the prefixes come from a single `colors(dim:bright:)`, where
        // `focusIndicatorPrefix` used to resolve its own colour per frame — 16,
        // one for every frame of the cycle it was asked to draw.
        #expect(builds == 1, "built \(builds)")
    }

    @Test("A Color256Grid's cursor swatch does too")
    func colorGridCursorBuildsOneRamp() {
        // Two: the mark drawn NOW (one ramp, for the grid's one cursor cell)
        // and the run's sixteen frames (one more, shared by all of them). It
        // was seventeen.
        let selection = Binding<Color>(get: { .palette(33) }, set: { _ in })
        let (builds, buffer) = buildsRendering(_Color256GridCore(selection: selection))
        #expect(!buffer.animatedCells.isEmpty, "the grid did not draw a breath")
        #expect(builds == 2, "built \(builds)")
    }

    @Test("A SwatchGrid's cursor swatch does too")
    func swatchGridCursorBuildsOneRamp() {
        let selection = Binding<Color>(get: { .rgb(10, 20, 30) }, set: { _ in })
        let (builds, buffer) = buildsRendering(
            _SwatchGridCore(
                entries: [.rgb(10, 20, 30), .rgb(200, 40, 40), .rgb(40, 200, 40)],
                columns: 3, selection: selection))
        #expect(!buffer.animatedCells.isEmpty, "the grid did not draw a breath")
        // Two, for the same two reasons the 256 grid's are: the mark drawn now,
        // and the run's frames. It was seventeen.
        #expect(builds == 2, "built \(builds)")
    }

    @Test("A breathing LABEL — a focused Link — builds one too")
    func breathingLabelBuildsOneRamp() {
        // The other plain-button path: `indicatesFocusInLabel` breathes the
        // label itself instead of opening a gutter for a bullet, and renders
        // the label once per frame of the cycle. Rendering it per frame is
        // deliberate (the cells can carry an underline, a symbol, bold);
        // rebuilding the RAMP per frame was not.
        let (builds, buffer) = buildsRendering(
            Link("Docs", destination: URL(string: "https://example.invalid")!))
        #expect(!buffer.animatedCells.isEmpty, "the label did not breathe")
        #expect(builds == 1, "built \(builds)")
    }

    @Test("An open drop-down's two pulses cost two ramps, not two per frame")
    func dropdownBuildsTwoRamps() {
        // The popup's cycle is `cycle(true)` unconditionally — an open menu
        // holds the focus by definition — so this shape needs no focus
        // plumbing, only a render.
        let builds = ColorDepth.withCurrent(.palette256) { () -> Int in
            let context = makeRenderContext(width: 30, height: 12)
            let config = DropdownMenu.Configuration(
                rows: [.option("One"), .option("Two"), .divider, .option("Three")],
                highlightedRow: 0, innerWidth: 12, scroll: ScrollAxis(),
                followHighlight: true, autoRepeatToken: "ramp-test")
            let before = SelectionEmphasis.rampBuilds
            _ = DropdownMenu.popup(
                config, context: context, onHover: { _ in }, onActivate: { _ in },
                onDismiss: {})
            return SelectionEmphasis.rampBuilds - before
        }
        // Two, because the popup breathes two things between DIFFERENT ends:
        // the highlighted row's background and the border echoing it. Two ramps
        // per cycle, where it used to be two per FRAME — 32 for one open menu.
        #expect(builds == 2, "built \(builds)")
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
