//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GhosttyWarpCompatibilityTests.swift
//
//  Pins the Ghostty and Warp advance models + output paths against the
//  DSR-measured behaviour recorded in Documentation/Terminal-compatibility.md
//  (Ghostty 1.3.1, Warp v0.2026.07.08, alternate screen, 2026-07-14).
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@Suite("Ghostty + Warp terminal compatibility")
struct GhosttyWarpCompatibilityTests {

    // MARK: - Detection

    @Test(
        "TERM_PROGRAM identifies each host, and only that host",
        arguments: [
            ("ghostty", true, false),
            ("WarpTerminal", false, true),
            ("Apple_Terminal", false, false),
            ("iTerm.app", false, false),
            ("", false, false),
        ])
    func detection(termProgram: String, expectGhostty: Bool, expectWarp: Bool) {
        let env = ["TERM_PROGRAM": termProgram]
        #expect(TerminalHost.detectGhostty(environment: env) == expectGhostty)
        #expect(TerminalHost.detectWarp(environment: env) == expectWarp)
        // The new hosts must not be mistaken for the old ones (whose
        // compensation would corrupt their output).
        if expectGhostty || expectWarp {
            #expect(!TerminalHost.detectAppleTerminal(environment: env))
            #expect(!TerminalHost.detectITerm2(environment: env))
        }
    }

    @Test("Ghostty is identified by TERM_PROGRAM, not its xterm-ghostty TERM")
    func ghosttyTermIsNotTheSignal() {
        // TERM is routinely overridden to xterm-256color for compatibility
        // with hosts lacking Ghostty's terminfo; TERM_PROGRAM survives.
        let overridden = ["TERM": "xterm-256color", "TERM_PROGRAM": "ghostty"]
        #expect(TerminalHost.detectGhostty(environment: overridden))
        // And TERM alone must never trigger it.
        #expect(!TerminalHost.detectGhostty(environment: ["TERM": "xterm-ghostty"]))
    }

    // MARK: - Measured advance models

    /// Every row is a DSR measurement from the committed compatibility table.
    @Test(
        "Ghostty advance model matches the measured battery",
        arguments: [
            // (cluster, claimed width, measured Ghostty advance)
            ("a", 1, 1),
            ("中", 2, 2),
            ("\u{2764}\u{FE0F}", 2, 2),  // ❤️ — correct here, unlike Apple/iTerm2
            ("\u{1F44D}", 2, 2),  // 👍
            ("\u{1F44D}\u{1F3FD}", 2, 2),  // 👍🏽 merged — no strip needed
            ("\u{1F469}\u{200D}\u{1F680}", 2, 2),  // 👩‍🚀 ZWJ correct
            ("1\u{FE0F}\u{20E3}", 2, 2),  // 1️⃣ keycap correct
            ("\u{1F1FA}\u{1F1F8}", 2, 2),  // 🇺🇸
            ("\u{1F1E6}", 2, 2),  // lone RI correct (unlike Apple/Warp)
            ("\u{3030}\u{FE0F}", 2, 2),  // 〰️
            ("\u{2588}", 1, 1),  // █ — one cluster; "██" would be two
            // The two quirks:
            ("\u{2B1B}\u{FE0E}", 2, 1),  // ⬛︎ VS-15 chrome: paints 2, advances 1
            ("\u{2B1C}\u{FE0E}", 2, 1),  // ⬜︎
            ("\u{100038}", 2, 1),  // SF Symbol PUA
        ])
    func ghosttyAdvanceModel(cluster: String, claimed: Int, advance: Int) {
        let char = Character(cluster)
        #expect(char.terminalWidth == claimed, "claim for \(cluster.debugDescription)")
        #expect(
            char.ghosttyCursorAdvance == advance,
            "Ghostty advance for \(cluster.debugDescription)")
    }

    @Test(
        "Warp advance model matches the measured battery",
        arguments: [
            ("a", 1, 1),
            ("中", 2, 2),
            ("\u{2764}\u{FE0F}", 2, 2),  // ❤️ correct on the ALTERNATE screen
            ("\u{2B1B}\u{FE0E}", 2, 2),  // ⬛︎ chrome correct (unlike Ghostty)
            ("\u{1F44D}", 2, 2),
            ("\u{1F1FA}\u{1F1F8}", 2, 2),
            ("\u{1F1E6}", 2, 1),  // lone RI under-advances, as on Apple Terminal
        ])
    func warpAdvanceModel(cluster: String, claimed: Int, advance: Int) {
        let char = Character(cluster)
        #expect(char.terminalWidth == claimed, "claim for \(cluster.debugDescription)")
        #expect(char.warpCursorAdvance == advance, "Warp advance for \(cluster.debugDescription)")
    }

    // MARK: - Bare SMP pictographs (the selector-less form)

    /// Every terminal measured advances these by 1 against a claim of 2, so
    /// EVERY host model must report 1 or no CUF is emitted and the row shears.
    /// Apple/iTerm2 paint 2 (Apple Color Emoji fallback — `paintcard.py`
    /// 2026-07-14), which is why the claim of 2 is right and this is a model
    /// fix, not a claim fix.
    @Test(
        "A bare SMP pictograph under-advances on every host",
        arguments: [
            "\u{1F5A5}",  // 🖥 desktop computer
            "\u{1F6E1}",  // 🛡 shield
            "\u{1F579}",  // 🕹 joystick
            "\u{1F577}",  // 🕷 spider
            "\u{1F39E}",  // 🎞 film frames
            "\u{1F3D9}",  // 🏙 cityscape
        ])
    func barePictographUnderAdvancesEverywhere(cluster: String) {
        let char = Character(cluster)
        #expect(char.terminalWidth == 2, "claim (Apple paints 2 via emoji fallback)")
        #expect(char.terminalAppCursorAdvance == 1, "Apple measured 1")
        #expect(char.iTerm2CursorAdvance == 1, "iTerm2 measured 1")
        #expect(char.ghosttyCursorAdvance == 1, "Ghostty measured 1")
        #expect(char.warpCursorAdvance == 1, "Warp measured 1")
    }

    @Test("Each host's walk emits the CUF that keeps the row aligned")
    func barePictographIsCompensated() {
        // Without the model fix every one of these is a no-op and the "|"
        // lands a cell early — the shear this whole class is about.
        let raw = "\u{1F5A5}|"
        #expect(raw.withTerminalAppCursorCompensation() == "\u{1F5A5}\u{1B}[1C|")
        #expect(raw.withITerm2CursorCompensation() == "\u{1F5A5}\u{1B}[1C|")
        #expect(raw.withGhosttyCursorCompensation() == "\u{1F5A5}\u{1B}[1C|")
        #expect(raw.withWarpCursorCompensation() == "\u{1F5A5}\u{1B}[1C|")
    }

    @Test(
        "The VS-16 form and the BMP twins are untouched by the bare-form fix",
        arguments: [
            // 🖥️ — the form the demo app actually uses. Already correct:
            // Apple/iTerm2 under-advance it (isVS16UnderAdvancer), Ghostty and
            // Warp advance it properly. Must not double-compensate.
            ("\u{1F5A5}\u{FE0F}", 2, 1, 2),
            ("\u{1F6E1}\u{FE0F}", 2, 1, 2),
            // BMP text-presentation twins: claim 1, advance 1 — nothing to do.
            ("\u{270F}", 1, 1, 1),
            ("\u{2764}", 1, 1, 1),
            ("\u{261D}", 1, 1, 1),
        ])
    func neighbouringFormsUnaffected(
        cluster: String, claim: Int, appleAdvance: Int, ghosttyAdvance: Int
    ) {
        let char = Character(cluster)
        #expect(char.terminalWidth == claim)
        #expect(char.terminalAppCursorAdvance == appleAdvance)
        #expect(char.ghosttyCursorAdvance == ghosttyAdvance)
    }

    @Test(
        "Emoji-presentation neighbours keep advancing their full 2",
        arguments: ["\u{1F44D}", "\u{1F004}"])  // 👍 thumbs, 🀄 mahjong red dragon
    func emojiPresentationUnaffected(cluster: String) {
        // These live in the same 0x1F000–0x1FBFF block but are
        // Emoji_Presentation=Yes: they paint AND advance 2 everywhere, so a
        // CUF here would shove the rest of the row a cell right.
        let char = Character(cluster)
        #expect(char.terminalWidth == 2)
        for advance in [
            char.terminalAppCursorAdvance, char.iTerm2CursorAdvance,
            char.ghosttyCursorAdvance, char.warpCursorAdvance,
        ] {
            #expect(advance == 2, "must not be treated as an under-advancer")
        }
    }

    // MARK: - Compensation walks

    @Test("Ghostty compensation pushes the cursor past an under-advanced ⬛︎")
    func ghosttyCompensatesChrome() {
        // The confirmed Toggle-demo bug: `⬛︎ On` rendered as `■On` because the
        // glyph paints 2 cells but the cursor only moved 1, so the space was
        // overwritten. One CUF(1) restores the claimed 2 cells.
        let compensated = "\u{2B1B}\u{FE0E} On".withGhosttyCursorCompensation()
        #expect(compensated.contains("\u{1B}[1C"), "expected a CUF(1): \(compensated.debugDescription)")
        #expect(compensated.hasPrefix("\u{2B1B}\u{FE0E}\u{1B}[1C"), "CUF must follow the glyph")
    }

    @Test("Ghostty compensation pushes the cursor past an SF Symbol")
    func ghosttyCompensatesSFSymbol() {
        let compensated = "\u{100038}x".withGhosttyCursorCompensation()
        #expect(compensated == "\u{100038}\u{1B}[1Cx")
    }

    @Test("Ghostty compensation leaves the classes Ghostty gets right alone")
    func ghosttyLeavesCorrectClustersUntouched() {
        // Injecting CUF here would shift the rest of the row one cell right —
        // the exact corruption the Apple-only gating exists to avoid.
        for good in ["\u{2764}\u{FE0F}", "\u{1F44D}\u{1F3FD}", "1\u{FE0F}\u{20E3}", "\u{1F1E6}"] {
            #expect(
                good.withGhosttyCursorCompensation() == good,
                "must be untouched: \(good.debugDescription)")
        }
    }

    @Test("Ghostty keeps merged skin tones — no swatch strip")
    @MainActor
    func ghosttyDoesNotStripSkinTones() {
        // Ghostty renders 👍🏽 as one merged 2-cell glyph. Stripping (as the
        // iTerm2/Warp paths must) would throw that away for nothing.
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: true, isWarp: false)
        let line = buildLine(writer, raw: "\u{1F44D}\u{1F3FD}")
        #expect(line.hasSkinToneModifier, "modifier must survive: \(line.debugDescription)")
    }

    @Test("Warp strips skin tones, as iTerm2 does")
    @MainActor
    func warpStripsSkinTones() {
        // Warp paints base + separate swatch at 4 cells against a claim of 2 —
        // confirmed visually as a sheared feature-box border in the demo app.
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: true)
        let line = buildLine(writer, raw: "\u{1F44D}\u{1F3FD}")
        #expect(!line.hasSkinToneModifier, "modifier must be stripped: \(line.debugDescription)")
        #expect(line.contains("\u{1F44D}"), "base must survive")
    }

    @Test("An unknown terminal is still left completely untouched")
    @MainActor
    func unknownHostUnchanged() {
        // The safety property the whole gating exists for: kitty, WezTerm,
        // Alacritty, Linux consoles… get no rewriting at all.
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false)
        let line = buildLine(writer, raw: "\u{2B1B}\u{FE0E}\u{1F44D}\u{1F3FD}")
        #expect(!line.contains("\u{1B}[1C"), "no CUF for an unknown host")
        #expect(line.hasSkinToneModifier, "no strip for an unknown host")
    }

    /// Renders one raw line through the writer's real build path.
    @MainActor
    private func buildLine(_ writer: FrameDiffWriter, raw: String) -> String {
        var buffer = FrameBuffer(emptyWithWidth: 20, height: 1)
        buffer.lines = [raw]
        return writer.buildOutputLines(
            buffer: buffer, terminalWidth: 20, terminalHeight: 1,
            bgCode: "", reset: "\u{1B}[0m"
        ).joined()
    }
}

extension String {
    /// Whether any Fitzpatrick modifier scalar survives in this string.
    ///
    /// Scalar-level on purpose: `"👍🏽".contains("🏽")` is FALSE, because
    /// `String.contains` matches whole grapheme clusters and the modifier is
    /// fused into the thumbs-up cluster. Asserting the strip with `contains`
    /// therefore passes whether or not the strip ran.
    fileprivate var hasSkinToneModifier: Bool {
        unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
    }
}
