//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SGRStateTests.swift
//
//  `SGRState` replaces "concatenate every escape and let the terminal sort it
//  out" with an interpretation, so the contract it has to keep is TERMINAL-STATE
//  equivalence: feeding a terminal the original run and feeding it the netted
//  rendering must leave the same styling. Byte equality is explicitly not the
//  contract — being shorter is the whole point.
//
//  These check that equivalence directly, with a reference model of what a
//  terminal does with SGR, over hand-picked cases and a seeded sweep.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("SGR state")
struct SGRStateTests {

    /// A deliberately naive reference: what the terminal ends up in, computed
    /// independently of `SGRState` so the two can disagree.
    private struct Reference: Equatable {
        var on: Set<Int> = []
        var foreground: [String]?
        var background: [String]?

        private static let off: [Int: [Int]] = [
            21: [1], 22: [1, 2], 23: [3], 24: [4], 25: [5, 6], 27: [7], 28: [8], 29: [9],
        ]

        mutating func feed(_ sequence: String) {
            guard sequence.hasSuffix("m") else { return }
            var body = sequence.dropFirst().drop(while: { $0 != "[" }).dropFirst().dropLast()
            if body.isEmpty { body = "0" }
            let codes = body.split(separator: ";", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? "0" : String($0) }
            var index = 0
            while index < codes.count {
                guard let value = Int(codes[index]) else { index += 1; continue }
                index += consume(value, codes, at: index)
            }
        }

        /// Applies one code and reports how many parameters it consumed.
        private mutating func consume(_ value: Int, _ codes: [String], at index: Int) -> Int {
            switch value {
            case 0: self = Self()
            case 1, 2, 3, 4, 5, 6, 7, 8, 9: on.insert(value)
            case 21, 22, 23, 24, 25, 27, 28, 29: (Self.off[value] ?? []).forEach { on.remove($0) }
            case 30...37, 90...97: foreground = [codes[index]]
            case 39: foreground = nil
            case 40...47, 100...107: background = [codes[index]]
            case 49: background = nil
            case 38, 48:
                var span = 1
                if index + 1 < codes.count {
                    if codes[index + 1] == "5" { span = min(3, codes.count - index) }
                    if codes[index + 1] == "2" { span = min(5, codes.count - index) }
                }
                let parameters = Array(codes[index..<min(codes.count, index + span)])
                if value == 38 { foreground = parameters } else { background = parameters }
                return span
            default: break
            }
            return 1
        }
    }

    private func assertEquivalent(_ run: [String], _ label: String) {
        var state = SGRState()
        var direct = Reference()
        for sequence in run {
            state.apply(sequence)
            direct.feed(sequence)
        }
        // The netted rendering, replayed from a clean terminal, must land in the
        // same place as the original run did.
        var replayed = Reference()
        let rendering = state.rendered
        if !rendering.isEmpty { replayed.feed(rendering) }
        #expect(replayed == direct, "\(label): \(rendering.debugDescription) vs run \(run)")
    }

    @Test("An open/reset pair nets to nothing")
    func openAndReset() {
        assertEquivalent(["\u{1B}[1m", "\u{1B}[0m"], "bold then reset")
        assertEquivalent(["\u{1B}[4m", "\u{1B}[24m"], "underline then off")
        assertEquivalent(["\u{1B}[31m", "\u{1B}[39m"], "red then default")
        var state = SGRState()
        state.apply("\u{1B}[1m")
        state.apply("\u{1B}[0m")
        #expect(state.rendered.isEmpty)
        #expect(state.isDefault)
    }

    @Test("The last colour wins, in every form")
    func colours() {
        assertEquivalent(["\u{1B}[31m", "\u{1B}[32m"], "two basics")
        assertEquivalent(["\u{1B}[31m", "\u{1B}[38;5;208m"], "basic then 256")
        assertEquivalent(["\u{1B}[38;5;208m", "\u{1B}[38;2;12;34;56m"], "256 then truecolor")
        assertEquivalent(["\u{1B}[48;2;12;34;56m", "\u{1B}[41m"], "truecolor bg then basic")
        assertEquivalent(["\u{1B}[91m", "\u{1B}[101m"], "bright fg and bg")
    }

    @Test("Attributes and colours combine in one sequence")
    func combined() {
        assertEquivalent(["\u{1B}[1;4;31;44m"], "one multi-parameter escape")
        assertEquivalent(["\u{1B}[1m\u{1B}[4m"], "adjacent escapes in one string")
        assertEquivalent(["\u{1B}[0;1;38;5;9m"], "reset then set")
    }

    /// The blow-up this exists to stop: a long accumulated run must net to
    /// something bounded, not to itself.
    @Test("A long accumulated run nets to a bounded rendering")
    func longRunStaysBounded() {
        var run: [String] = []
        for step in 0..<200 {
            run.append("\u{1B}[7m")
            run.append("\u{1B}[0m")
            run.append("\u{1B}[38;5;\(step % 256)m")
        }
        assertEquivalent(run, "200 chips")
        var state = SGRState()
        for sequence in run { state.apply(sequence) }
        #expect(
            state.rendered.utf8.count < 24,
            "netted to \(state.rendered.utf8.count) bytes: \(state.rendered.debugDescription)")
    }

    @Test("A non-SGR escape is not styling and is ignored")
    func nonSGRIgnored() {
        var state = SGRState()
        state.apply("\u{1B}[2J")  // clear screen
        state.apply("\u{1B}[10;20H")  // cursor position
        #expect(state.isDefault)
    }

    @Test("The same state always renders identically")
    func renderingIsStable() {
        var first = SGRState()
        first.apply("\u{1B}[4m")
        first.apply("\u{1B}[1m")
        first.apply("\u{1B}[31m")
        var second = SGRState()
        second.apply("\u{1B}[31m")
        second.apply("\u{1B}[1m")
        second.apply("\u{1B}[4m")
        // Order of arrival differs; the resulting STATE does not, so neither may
        // the bytes — an unstable rendering would make equal buffers compare
        // unequal and defeat the render memo.
        #expect(first.rendered == second.rendered)
        #expect(first == second)
    }

    @Test("Randomised runs stay equivalent")
    func randomisedSweep() {
        let pool = [
            "\u{1B}[0m", "\u{1B}[1m", "\u{1B}[2m", "\u{1B}[4m", "\u{1B}[7m",
            "\u{1B}[22m", "\u{1B}[24m", "\u{1B}[27m",
            "\u{1B}[31m", "\u{1B}[92m", "\u{1B}[39m",
            "\u{1B}[44m", "\u{1B}[103m", "\u{1B}[49m",
            "\u{1B}[38;5;208m", "\u{1B}[48;5;17m",
            "\u{1B}[38;2;1;2;3m", "\u{1B}[48;2;4;5;6m",
            "\u{1B}[1;4;31m",
        ]
        var seed: UInt64 = 0x0BAD_F00D
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for sample in 0..<60 {
            var run: [String] = []
            for _ in 0..<(1 + next(12)) { run.append(pool[next(pool.count)]) }
            assertEquivalent(run, "random #\(sample)")
        }
    }

    // MARK: - Deltas

    /// The delta's contract: a terminal put into `from` and then fed
    /// `to.rendered(changingFrom: from)` must end up exactly where
    /// `to.rendered` would have put a clean one. Checked against the same
    /// independent reference model, so the delta cannot be graded by the code
    /// that produces it.
    private func assertDeltaEquivalent(from: [String], to: [String], _ label: String) {
        var before = SGRState()
        for sequence in from { before.apply(sequence) }
        var after = SGRState()
        for sequence in to { after.apply(sequence) }

        var target = Reference()
        let absolute = after.rendered
        if !absolute.isEmpty { target.feed(absolute) }

        var stepped = Reference()
        if !before.rendered.isEmpty { stepped.feed(before.rendered) }
        let delta = after.rendered(changingFrom: before)
        if !delta.isEmpty { stepped.feed(delta) }

        let detail =
            "\(label): delta \(delta.debugDescription) from \(before.rendered.debugDescription) "
            + "did not reach \(absolute.debugDescription)"
        #expect(stepped == target, "\(detail)")
    }

    @Test("A state already in force emits nothing")
    func deltaToSelf() {
        var state = SGRState()
        state.apply("\u{1B}[1;38;5;208;48;5;17m")
        #expect(state.rendered(changingFrom: state).isEmpty)
    }

    @Test("Only the changed component is emitted")
    func deltaSaysOnlyWhatChanged() {
        var background = SGRState()
        background.apply("\u{1B}[0;48;5;16m")
        var withText = SGRState()
        withText.apply("\u{1B}[0;38;5;22;48;5;16m")
        // The two commonest transitions in a divider drag, and the reason this
        // exists: 19 bytes and 12 bytes of absolute became 11 and 5.
        #expect(withText.rendered(changingFrom: background) == "\u{1B}[38;5;22m")
        #expect(background.rendered(changingFrom: withText) == "\u{1B}[39m")
    }

    @Test("A default component is spelled out, not left standing")
    func deltaToDefaultComponent() {
        var coloured = SGRState()
        coloured.apply("\u{1B}[0;38;5;22;48;5;28m")
        var neither = SGRState()
        neither.apply("\u{1B}[0;1m")
        // Bold arrives, and BOTH colours go back to the terminal's own — a
        // delta that omitted 39/49 would leave the old colours in force.
        assertDeltaEquivalent(
            from: ["\u{1B}[0;38;5;22;48;5;28m"], to: ["\u{1B}[0;1m"], "colours to default")
        // Here the delta would be `ESC[1;39;49m` and the reset-prefixed
        // absolute is `ESC[0;1m` — same meaning, two bytes fewer. Both spellings
        // are correct, so the shorter one wins; what must never happen is the
        // colours being left standing.
        #expect(neither.rendered(changingFrom: coloured) == "\u{1B}[0;1m")
    }

    @Test("Whichever spelling is shorter wins, and both are equivalent")
    func deltaTakesTheShorterSpelling() {
        var coloured = SGRState()
        coloured.apply("\u{1B}[0;38;5;22;48;5;16m")
        // Everything off: `ESC[39;49m` says it in nine bytes, `ESC[0m` in four.
        #expect(SGRState().rendered(changingFrom: coloured) == "\u{1B}[0m")
        assertDeltaEquivalent(from: ["\u{1B}[0;38;5;22;48;5;16m"], to: ["\u{1B}[0m"], "all off")
        // And the other way, where the delta really is shorter, it stays.
        #expect(coloured.rendered(changingFrom: SGRState()) == "\u{1B}[38;5;22;48;5;16m")
    }

    @Test("Turning an attribute off falls back to a reset-prefixed absolute")
    func deltaAttributeOff() {
        var bold = SGRState()
        bold.apply("\u{1B}[0;1;38;5;9m")
        var plain = SGRState()
        plain.apply("\u{1B}[0;38;5;9m")
        // 21 vs 22 is where terminals genuinely disagree, so the delta declines
        // to bet and states the whole thing from a reset.
        #expect(plain.rendered(changingFrom: bold) == "\u{1B}[0;38;5;9m")
        assertDeltaEquivalent(from: ["\u{1B}[0;1;38;5;9m"], to: ["\u{1B}[0;38;5;9m"], "bold off")
    }

    @Test("Randomised transitions stay equivalent")
    func randomisedDeltaSweep() {
        let pool = [
            "\u{1B}[0m", "\u{1B}[1m", "\u{1B}[2m", "\u{1B}[4m", "\u{1B}[7m",
            "\u{1B}[22m", "\u{1B}[24m", "\u{1B}[27m",
            "\u{1B}[31m", "\u{1B}[92m", "\u{1B}[39m",
            "\u{1B}[44m", "\u{1B}[103m", "\u{1B}[49m",
            "\u{1B}[38;5;208m", "\u{1B}[48;5;17m",
            "\u{1B}[38;2;1;2;3m", "\u{1B}[48;2;4;5;6m",
            "\u{1B}[1;4;31m",
        ]
        var seed: UInt64 = 0x5EED_1CE5
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for sample in 0..<200 {
            var from: [String] = []
            for _ in 0..<(1 + next(6)) { from.append(pool[next(pool.count)]) }
            var to: [String] = []
            for _ in 0..<(1 + next(6)) { to.append(pool[next(pool.count)]) }
            assertDeltaEquivalent(from: from, to: to, "random transition #\(sample)")
        }
    }
}
