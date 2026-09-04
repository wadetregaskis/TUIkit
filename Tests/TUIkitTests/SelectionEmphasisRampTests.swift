//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectionEmphasisRampTests.swift
//
//  A pulse ramp is a pure function of its two endpoints and the terminal's
//  colour depth — never of the frame being coloured. `SelectionEmphasisCycle`
//  builds one per cycle and spends it across every frame, and
//  `Color.pulseRamp` memoises the result, so a caller that fails to hoist pays
//  a dictionary hit rather than a 256-sample walk. There is deliberately no
//  build counter in the framework: the memoisation makes a per-frame rebuild
//  cheap by construction, so the thing to pin is that the colours are right
//  and that the ramp is genuinely reused, not how many times a private
//  function was entered.
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

    /// The safety net under the hoist: `colors` (one ramp, shared) must agree
    /// frame for frame with the per-frame `color(dim:bright:)` it replaced, or
    /// "the same work, done once" would be the wrong description.
    ///
    /// Pinning the depth is REQUIRED, not tidiness: `pulseRamp` returns the two
    /// raw endpoints without quantising at truecolor, and the test runner's own
    /// environment detects as truecolor — so unpinned this passes for the wrong
    /// reason. Task-local, so a parallel suite is unaffected.
    @Test("Hoisting the ramp changes no colour")
    func hoistingIsBehaviourPreserving() {
        let cycle = self.cycle()
        ColorDepth.withCurrent(.palette256) {
            let hoisted = cycle.colors(dim: dim, bright: bright)
            let perFrame = cycle.frames.map { $0.color(dim: dim, bright: bright) }
            #expect(hoisted == perFrame)
        }
    }

    @Test("Every frame's colour is drawn from the one ramp")
    func everyFrameComesFromTheRamp() {
        ColorDepth.withCurrent(.palette256) {
            let ramp = Set(Color.pulseRamp(from: dim, to: bright, depth: .palette256))
            let colours = cycle().colors(dim: dim, bright: bright)
            #expect(colours.allSatisfy { ramp.contains($0) }, "a frame colour outside the ramp: \(colours)")
        }
    }

    @Test("A blink cycle reads no ramp, and an unfocused one sits at bright")
    func degenerateCyclesNeedNoRamp() {
        ColorDepth.withCurrent(.palette256) {
            // A blink is one endpoint or the other, never a shade between —
            // and the RAW endpoints, not rendered ones: it reads no ramp, so
            // nothing quantises them (the ANSI layer does that at emission).
            let blink = Set(cycle(animation: .blink).colors(dim: dim, bright: bright))
            #expect(blink.isSubset(of: [dim, bright]))
            // An unfocused cycle is bright throughout — it stays visible when
            // focus moves elsewhere.
            let unfocused = cycle(isFocused: false).colors(dim: dim, bright: bright)
            #expect(unfocused.allSatisfy { $0 == bright })
        }
    }

    // MARK: - The shapes that draw a whole cycle

    /// Renders `view` focused, at 256 colours, and returns its buffer.
    ///
    /// A real render rather than a hand-built cycle, because what these pin is
    /// not the cycle: it is that each drawing site actually breathes when
    /// focused — the run it leaves behind is what the loop replays without a
    /// re-render.
    private func renderFocused<V: View>(_ view: V) -> FrameBuffer {
        ColorDepth.withCurrent(.palette256) {
            renderToBuffer(view, context: makeRenderContext(width: 30, height: 6))
        }
    }

    @Test("A focused button's caps breathe")
    func buttonCapsBreathe() {
        #expect(!renderFocused(Button("OK") {}).animatedCells.isEmpty, "no breath")
    }

    @Test("A focused plain button's indicator breathes")
    func focusIndicatorBreathes() {
        #expect(!renderFocused(Button("OK") {}.buttonStyle(.plain)).animatedCells.isEmpty, "no breath")
    }

    @Test("A Color256Grid's cursor swatch breathes")
    func colorGridCursorBreathes() {
        let selection = Binding<Color>(get: { .palette(33) }, set: { _ in })
        #expect(!renderFocused(_Color256GridCore(selection: selection)).animatedCells.isEmpty, "no breath")
    }

    @Test("A SwatchGrid's cursor swatch breathes")
    func swatchGridCursorBreathes() {
        let selection = Binding<Color>(get: { .rgb(10, 20, 30) }, set: { _ in })
        let grid = _SwatchGridCore(
            entries: [.rgb(10, 20, 30), .rgb(200, 40, 40), .rgb(40, 200, 40)],
            columns: 3, selection: selection)
        #expect(!renderFocused(grid).animatedCells.isEmpty, "no breath")
    }

    @Test("A breathing label — a focused Link — breathes")
    func breathingLabelBreathes() {
        let link = Link("Docs", destination: URL(string: "https://example.invalid")!)
        #expect(!renderFocused(link).animatedCells.isEmpty, "no breath")
    }

    @Test("An open drop-down breathes")
    func dropdownBreathes() {
        ColorDepth.withCurrent(.palette256) {
            let context = makeRenderContext(width: 30, height: 12)
            let config = DropdownMenu.Configuration(
                rows: [.option("One"), .option("Two"), .divider, .option("Three")],
                highlightedRow: 0, innerWidth: 12, scroll: ScrollAxis(),
                followHighlight: true, autoRepeatToken: "ramp-test")
            let buffer = DropdownMenu.popup(
                config, context: context, onHover: { _ in }, onActivate: { _ in }, onDismiss: {})
            #expect(!buffer.animatedCells.isEmpty, "the open menu did not breathe")
        }
    }
}

// MARK: - The ramp cache

@Suite("Pulse ramp memoisation")
struct PulseRampCacheTests {

    /// The ramp is a pure function of its inputs, so a repeat asks the cache,
    /// not the quantiser — but the ANSWER must be identical either way, which
    /// is the only part a test can see without reaching into a private cache.
    @Test("The same request answers the same ramp every time")
    func idempotent() {
        let dim = Color.rgb(20, 24, 30)
        let bright = Color.rgb(90, 200, 250)
        let first = Color.pulseRamp(from: dim, to: bright, depth: .palette256)
        let second = Color.pulseRamp(from: dim, to: bright, depth: .palette256)
        #expect(first == second)
        #expect(first.count > 1, "a real fade should have distinct shades: \(first)")
    }

    /// The depth is part of the key, so two depths do not share a cached ramp —
    /// the 16-colour answer is coarser than the 256-colour one and must not be
    /// served for it.
    @Test("Different depths do not collide in the cache")
    func depthIsPartOfTheKey() {
        let dim = Color.rgb(20, 24, 30)
        let bright = Color.rgb(90, 200, 250)
        let palette = Color.pulseRamp(from: dim, to: bright, depth: .palette256)
        let ansi16 = Color.pulseRamp(from: dim, to: bright, depth: .basic16)
        #expect(palette != ansi16, "the two depths quantise the same span differently")
        // And truecolor keeps the raw endpoints, quantising nothing.
        #expect(Color.pulseRamp(from: dim, to: bright, depth: .truecolor) == [dim, bright])
    }
}
