//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalWidthTraitsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The claim follows the host now, so that a cluster the host draws wide is
/// ALLOCATED wide rather than cut down to fit — see ``TerminalWidthTraits``.
///
/// Every expectation here is a measurement taken on the alternate screen on
/// 2026-08-26, recorded in `Documentation/Terminal-compatibility.md`.
@Suite("Terminal width traits")
struct TerminalWidthTraitsTests {

    private static let warp = TerminalWidthTraits(
        zwjSequences: .decomposedDroppingJoiners, skinTone: .detached)
    /// The raw-cluster truth on Warp (and the explorer's option): each kept
    /// joiner costs a column. The SHIPPED Warp walk drops the joiners instead
    /// (2026-08-28), so `Self.warp` above mirrors `widthTraits(of: .warp)`
    /// while this pins the keeping arithmetic on its own.
    private static let warpKeptJoiners = TerminalWidthTraits(
        zwjSequences: .decomposedKeepingJoiners, skinTone: .detached)
    // Apple Terminal's walk REWRITES the two classes below (ZWJ decomposition
    // dropping the joiners, skin-tone separation with a ZWNJ column), so its
    // claims follow the rewritten forms — see `TerminalClient.widthTraits(of:)`.
    private static let apple = TerminalWidthTraits(
        zwjSequences: .decomposedDroppingJoiners,
        skinTone: .separated)
    private static let iTerm = TerminalWidthTraits(
        zwjSequences: .composed, skinTone: .detachedOnBMPBases)

    // MARK: - The measured widths

    @Test(
        "Kept-joiner ZWJ widths are the segment sum plus a cell per joiner (Warp's raw clusters)",
        arguments: [
            ("👩‍🚀", 5), ("🧑‍🌾", 5), ("👩‍🦰", 5), ("❤️‍🔥", 5),
            ("⛓️‍💥", 5), ("🏳️‍🌈", 5), ("🏴‍☠️", 5),
            ("👨‍👩‍👧", 8), ("👨‍❤️‍👨", 8), ("👨‍👩‍👧‍👦", 11),
            // The case that proves the two rules compose rather than duplicate:
            // 4 for the skin-toned segment, 1 for the joiner, 2 for the rocket.
            ("👩🏽‍🚀", 7),
        ] as [(String, Int)])
    func warpZWJWidths(text: String, expected: Int) {
        TerminalWidthTraits.withTraits(Self.warpKeptJoiners) {
            #expect(Character(text).terminalWidth == expected)
        }
    }

    /// What Warp ships now: the walk drops the joiners, so the claim is the
    /// bare segment sum — card-measured 2026-08-28, every dropped form
    /// rendering the same components adjacent with followers and the CHA
    /// landing true.
    @Test(
        "Warp's shipped ZWJ widths drop the joiners",
        arguments: [
            ("👩‍🚀", 4), ("❤️‍🔥", 4), ("🏳️‍🌈", 4),
            ("👨‍👩‍👧‍👦", 8), ("👩🏽‍🚀", 6),
        ] as [(String, Int)])
    func warpDroppedZWJWidths(text: String, expected: Int) {
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(Character(text).terminalWidth == expected)
        }
    }

    @Test(
        "A detached skin-tone cluster is the base's width plus two",
        arguments: [
            ("👍🏽", 4), ("🤙🏽", 4), ("✊🏻", 4),
            // A 1-cell text-presentation base gives 3 …
            ("☝🏽", 3),
            // … and a redundant VS-16 on it does NOT widen the claim: the
            // walk strips the selector before emission (the modifier alone
            // forces emoji presentation), so both spellings price the
            // normalized pair — measured at exactly 3 on iTerm2 and Warp.
            ("☝️🏽", 3),
        ] as [(String, Int)])
    func detachedSkinToneWidths(text: String, expected: Int) {
        // Warp, not Apple Terminal: Warp genuinely draws the base and the
        // modifier side by side, which is what a detached claim describes.
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(Character(text).terminalWidth == expected)
        }
    }

    @Test("iTerm2 and tmux merge an SMP base and detach only a BMP one")
    func detachedOnBMPBasesOnly() {
        TerminalWidthTraits.withTraits(Self.iTerm) {
            #expect(Character("👍🏽").terminalWidth == 2, "SMP base merges")
            #expect(Character("✊🏻").terminalWidth == 4, "BMP base detaches")
            #expect(Character("☝🏽").terminalWidth == 3, "1-cell BMP base")
        }
    }

    /// Apple Terminal's ZWJ claims are the DECOMPOSED widths with the joiners
    /// dropped, because that is what the walk emits: every cursor-move repair
    /// that kept the composed glyph was measured (treatment cards 2–3,
    /// 2026-08-27) to leave later absolute positioning on the row displaced by
    /// the cluster's stored-width surplus, and the full-width DCH variants
    /// wrapped. The segments each carry their own class treatment, which is
    /// why ❤️\u{200D}🔥 claims 4 (an ECH'd ❤️ plus a bare 🔥) and 👩🏽\u{200D}🚀
    /// claims 7 (a separated 👩+ZWNJ+🏽 plus a bare 🚀).
    @Test(
        "Apple Terminal claims the decomposed width and the walk emits the segments",
        arguments: [
            ("👩\u{200D}🚀", 4, "👩🚀"),
            ("🧑\u{200D}🌾", 4, "🧑🌾"),
            ("👨\u{200D}👩\u{200D}👧\u{200D}👦", 8, "👨👩👧👦"),
            ("❤️\u{200D}🔥", 4, "\u{1B}[2X❤️\u{1B}[1C🔥"),
            ("👩🏽\u{200D}🚀", 7, "👩\u{200C}🏽🚀"),
        ] as [(String, Int, String)])
    func appleClaimsDecomposedWidth(text: String, claim: Int, emission: String) {
        #expect(
            TerminalClient.widthTraits(of: .appleTerminal)
                == TerminalWidthTraits(
                    zwjSequences: .decomposedDroppingJoiners,
                    skinTone: .separated))
        TerminalWidthTraits.withTraits(Self.apple) {
            #expect(Character(text).terminalWidth == claim)
            let out = TerminalClient.compensating(text, for: .appleTerminal)
            #expect(out == emission, "|\(out)|")
        }
    }

    /// Every skin-tone cluster is rewritten as base + ZWNJ + modifier and
    /// claims the separated width of base + 3, the ZWNJ occupying its own
    /// column (measured: 🤙+ZWNJ+🏽 advances 5 and paints base, blank, swatch,
    /// with followers and absolute moves all landing true — treatment cards
    /// 2–3). An emoji-presentation base needs no cursor moves at all. A
    /// text-presentation base (☝🏻 ✍🏿) is promoted with VS-16 — the bare
    /// rewrite measured misaligned, and the pull-back it shipped with
    /// re-rendered the bare narrow glyph beside a blank cell (user-reported
    /// 2026-08-28) — and the promoted cluster's internal advance (1+1+2) falls
    /// one short of the claim, so the walk's ordinary under-advance arm wraps
    /// it: `ECH(5)` + cluster + `CUF(1)`, card-measured aligned, sequential
    /// and absolute followers both true, tone kept as a swatch.
    @Test(
        "Skin tones separate: plain on emoji bases, VS-16-promoted on text ones",
        arguments: [
            ("🤙🏽", 5, "🤙\u{200C}🏽"),
            ("✊🏿", 5, "✊\u{200C}🏿"),
            ("👍🏽", 5, "👍\u{200C}🏽"),
            ("☝🏻", 5, "\u{1B}[5X☝\u{FE0F}\u{200C}\u{1F3FB}\u{1B}[1C"),
            ("✍🏿", 5, "\u{1B}[5X✍\u{FE0F}\u{200C}\u{1F3FF}\u{1B}[1C"),
            ("⛹🏾", 5, "\u{1B}[5X⛹\u{FE0F}\u{200C}\u{1F3FE}\u{1B}[1C"),
            // Already VS-16-promoted by the author: nothing is double-added.
            ("☝\u{FE0F}\u{1F3FD}", 5, "\u{1B}[5X☝\u{FE0F}\u{200C}\u{1F3FD}\u{1B}[1C"),
        ] as [(String, Int, String)])
    func appleSkinTonesSeparateOrPullBack(text: String, claim: Int, emission: String) {
        TerminalWidthTraits.withTraits(Self.apple) {
            #expect(Character(text).terminalWidth == claim)
            let out = TerminalClient.compensating(text, for: .appleTerminal)
            #expect(out == emission, "|\(out)|")
        }
    }

    /// A degenerate cluster carrying TWO Fitzpatrick scalars — invalid emoji,
    /// one valid grapheme, possible in arbitrary user data — is priced per
    /// modifier, because that is the emission's own arithmetic: the Apple
    /// walk separates it into base + (ZWNJ + modifier) per modifier, and a
    /// constant one-swatch claim left a 3-cell conservation gap that came out
    /// as an uncarded CUB(3). With the claim equal to the emission, the walk
    /// emits it with no cursor moves at all.
    @Test("A doubled modifier is priced per modifier, and separates with no moves")
    func doubledModifierPricesPerModifier() {
        let doubled = "\u{1F44D}\u{1F3FD}\u{1F3FD}"  // 👍🏽🏽, one grapheme
        #expect(doubled.count == 1)
        TerminalWidthTraits.withTraits(Self.apple) {
            // base 2 + (separator 1 + swatch 2) × 2
            #expect(Character(doubled).terminalWidth == 8)
            let out = TerminalClient.compensating(doubled, for: .appleTerminal)
            #expect(
                out == "\u{1F44D}\u{200C}\u{1F3FD}\u{200C}\u{1F3FD}",
                "separated, landing exactly on the claim — no CUB, no CUF: |\(out)|")
        }
        TerminalWidthTraits.withTraits(Self.warp) {
            // base 2 + swatch 2 × 2 — extrapolated, consistent with the
            // verbatim emission on a host that detaches every modifier.
            #expect(Character(doubled).terminalWidth == 6)
            let out = TerminalClient.compensating(doubled, for: .warp)
            #expect(out == doubled, "|\(out)|")
        }
    }

    /// A redundant VS-16 before a Fitzpatrick modifier (☝️🏽) is stripped by
    /// every walk: UTS #51 has the modifier itself force emoji presentation,
    /// so the normalized pair is the same emoji — and the one each host was
    /// measured to handle (the `tone_point_up` ledger rows), where the
    /// spelled form was "one cluster, two hosts, two answers": Ghostty
    /// detached it across 4 cells against a 2-cell claim, iTerm2 painted 3
    /// into a 4-cell claim. (Apple Terminal is pinned above: its separation
    /// re-promotes the base, so both spellings emit identical bytes.)
    @Test("A redundant VS-16 on a tone cluster is stripped and priced away")
    func redundantToneVS16IsNormalized() {
        let spelled = "\u{261D}\u{FE0F}\u{1F3FD}"
        // Ghostty merges the normalized pair (advance 1, ledger) — the plain
        // under-advance repair lands it on the composed 2-cell claim with the
        // tone KEPT, where the spelled form sheared 2 cells.
        TerminalWidthTraits.withTraits(.composing) {
            #expect(Character(spelled).terminalWidth == 2)
            let out = TerminalClient.compensating(spelled, for: .ghostty)
            #expect(out == "\u{1B}[2X\u{261D}\u{1F3FD}\u{1B}[1C", "|\(out)|")
        }
        // iTerm2 renders the detached BMP pair in bare-base + swatch = 3
        // cells (ledger: advance 3, ink 3) — claim 3, emitted verbatim,
        // aligned, where the spelled form left a one-cell hole in a 4-cell
        // claim.
        TerminalWidthTraits.withTraits(Self.iTerm) {
            #expect(Character(spelled).terminalWidth == 3)
            let out = TerminalClient.compensating(spelled, for: .iTerm2)
            #expect(out == "\u{261D}\u{1F3FD}", "|\(out)|")
        }
        // Warp likewise: 3 normalized where the spelled form took 4 — same
        // alignment, one cell tighter.
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(Character(spelled).terminalWidth == 3)
            let out = TerminalClient.compensating(spelled, for: .warp)
            #expect(out == "\u{261D}\u{1F3FD}", "|\(out)|")
        }
    }

    /// Flag pairs and keycaps are stored one column wider than they paint, and
    /// the store poisons everything later on the row — so the walk deletes the
    /// surplus stored column: `CUB(1)`, `DCH(1)`, `CUF(1)` (the one emission of
    /// ten card variants whose sequential AND absolutely-placed followers both
    /// landed true; treatment card 4, 2026-08-27).
    @Test(
        "Flags and keycaps get the stored-column surgery",
        arguments: ["🇺🇸", "1\u{FE0F}\u{20E3}", "#\u{FE0F}\u{20E3}"])
    func flagsAndKeycapsGetStoreSurgery(text: String) {
        TerminalWidthTraits.withTraits(Self.apple) {
            let character = Character(text)
            #expect(character.terminalWidth == 2, "claim")
            #expect(character.terminalAppCursorAdvance == 2, "internal, DSR-measured")
            #expect(character.terminalAppStoresWiderThanPainted)
            let out = TerminalClient.compensating(text, for: .appleTerminal)
            #expect(out == text + "\u{1B}[1D\u{1B}[1P\u{1B}[1C", "|\(out)|")
        }
    }

    /// A BARE keycap (1⃣ — no VS-16) is a different cluster: claimed 1 (the
    /// base's own width) but Apple Terminal advances it 2 (DSR, the advance
    /// battery record — the only host that does; the other three advance 1,
    /// matching the claim). It used to satisfy the stores-wider predicate,
    /// fall through the model to its claim, pass the surgery's
    /// advance-equals-claim guard on the strength of that wrong number, and
    /// take a `CUB(1)` `DCH(1)` `CUF(1)` calibrated for the FE0F form: the
    /// emission ended at the cursor's real column, one past the claim, and
    /// deleted a stored column never measured to be surplus. Now it is
    /// modelled at its measured 2 and pulled back like any over-advancer.
    /// (Paint and store for the bare form are unmeasured — a pixel card is
    /// queued; the pull-back is the alignment-safe treatment meanwhile.)
    @Test("A bare keycap is pulled back, not store-surgered")
    func bareKeycapIsPulledBackNotSurgered() {
        let bare = "1\u{20E3}"
        TerminalWidthTraits.withTraits(Self.apple) {
            let character = Character(bare)
            #expect(character.terminalWidth == 1, "claim — the base's own width")
            #expect(character.terminalAppCursorAdvance == 2, "internal, DSR-measured")
            #expect(!character.terminalAppStoresWiderThanPainted, "surgery is the FE0F form's")
            let out = TerminalClient.compensating(bare, for: .appleTerminal)
            #expect(out == bare + "\u{1B}[1D", "|\(out)|")
        }
        // The other three hosts advance it 1, exactly the claim: untouched.
        for (traits, program) in [
            (Self.iTerm, TerminalClient.Program.iTerm2),
            (.composing, .ghostty),
            (Self.warp, .warp),
        ] as [(TerminalWidthTraits, TerminalClient.Program)] {
            TerminalWidthTraits.withTraits(traits) {
                #expect(TerminalClient.compensating(bare, for: program) == bare, "\(program)")
            }
        }
    }

    /// Every advance the models report is the INTERNAL column measured by DSR
    /// on the real terminal — for both hosts. (An interim Apple model reported
    /// the paint position instead; the conservation test then verified paint
    /// and was blind to the internal drift that wraps full-width rows.)
    @Test(
        "The per-host advance models match what the terminals actually do",
        arguments: [
            ("👩‍🚀", 5, 5), ("👨‍👩‍👧‍👦", 11, 11), ("👩🏽‍🚀", 7, 7),
            ("❤️‍🔥", 4, 5), ("🏳️‍🌈", 4, 5),
            ("👍🏽", 4, 4), ("👍", 2, 2), ("中", 2, 2),
        ] as [(String, Int, Int)])
    func advanceModelsMatchMeasurement(text: String, apple: Int, warp: Int) {
        let character = Character(text)
        TerminalWidthTraits.withTraits(Self.apple) {
            #expect(character.terminalAppCursorAdvance == apple, "Apple Terminal")
        }
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(character.warpCursorAdvance == warp, "Warp")
        }
    }

    @Test("A composing host is unchanged, and is the default")
    func composingIsTheDefault() {
        #expect(TerminalWidthTraits.current == .composing)
        for text in ["👩‍🚀", "👨‍👩‍👧‍👦", "👍🏽", "☝🏽", "🏳️‍🌈"] {
            #expect(Character(text).terminalWidth == 2, "\(text) claims 2 when composed")
        }
    }

    @Test("Ghostty is the composing host")
    func ghosttyComposes() {
        #expect(TerminalClient.widthTraits(of: .ghostty) == .composing)
        #expect(TerminalClient.widthTraits(of: .unidentified) == .composing)
    }

    // MARK: - What the claim buys

    /// The point of the whole change: the modifier survives.
    @Test(
        "A claim that fits the cluster stops the modifier being stripped",
        arguments: [
            TerminalClient.Program.appleTerminal, .iTerm2, .warp,
        ])
    func skinToneSurvivesWhenClaimed(program: TerminalClient.Program) {
        let row = "│ ✊🏻 │"          // a BMP base: detached on every one of these
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            let out = TerminalClient.compensating(row, for: program)
            #expect(
                out.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) },
                "\(program) must keep the Fitzpatrick modifier once the claim holds it")
        }
    }

    /// And without the claim, the old behaviour stands — a caller who has not
    /// published the host's traits must not be handed an over-advancing row.
    @Test(
        "Without the claim the modifier is still stripped",
        arguments: [TerminalClient.Program.iTerm2, .warp, .tmux])
    func skinToneStrippedWhenUnclaimed(program: TerminalClient.Program) {
        let row = "│ ✊🏻 │"
        TerminalWidthTraits.withTraits(.composing) {
            let out = TerminalClient.compensating(row, for: program)
            #expect(!out.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) })
        }
    }

    /// tmux is held at the old behaviour on purpose: its skin-tone widths do
    /// not split by base plane. Measured on 3.7b, 👍🏽 🙏🏽 👋🏽 merge to 2 while
    /// 🤙🏽 🤚🏽 — also SMP — detach to 4, and ☝🏽 is 4 where a base-plus-two rule
    /// predicts 3. The line falls where tmux's Unicode data has a modifier base
    /// and where it does not, which is a per-codepoint fact this enum cannot
    /// express. A claim wrong in both directions misaligns rows; the strip at
    /// least aligns them.
    ///
    /// Caught by the Example emoji page rendering a SHORT row under tmux —
    /// unpainted cells at the right edge — which is exactly the defect the
    /// Fitzpatrick strip was introduced to avoid.
    @Test("tmux keeps stripping until its widths are measured per codepoint")
    func tmuxIsNotWidenedYet() {
        #expect(TerminalClient.widthTraits(of: .tmux) == .composing)
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .tmux)) {
            let out = TerminalClient.compensating(
                "│ ✊🏻 │", for: .tmux)
            #expect(!out.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) })
        }
    }

    /// Warp's walk drops the ZWJ joiners in software (2026-08-28): the
    /// components render adjacent (the kept joiner's column was just a gap),
    /// claims equal the segment sums, and the card measured sequential and
    /// absolute followers landing true for every dropped form.
    @Test(
        "Warp's walk emits ZWJ sequences as their segments, joiners dropped",
        arguments: [
            ("👩\u{200D}🚀", "👩🚀"),
            ("👨\u{200D}👩\u{200D}👧\u{200D}👦", "👨👩👧👦"),
            ("❤️\u{200D}🔥", "❤️🔥"),
            ("👩🏽\u{200D}🚀", "👩🏽🚀"),
        ] as [(String, String)])
    func warpDropsJoiners(text: String, emission: String) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .warp)) {
            let out = TerminalClient.compensating(text, for: .warp)
            #expect(out == emission, "|\(out)|")
        }
    }

    /// Claim equals advance for these classes, so the compensation machinery
    /// has nothing to do — no CUF, no ECH, no rewrite. That is the test that
    /// says the two models agree rather than fighting.
    @Test(
        "A claimed cluster needs no compensation at all",
        arguments: [
            (TerminalClient.Program.warp, "👨👩👧👦"),
            (.warp, "👩🏽🚀"),
            (.warp, "✊🏻"),

            (.iTerm2, "✊🏻"),

            (.appleTerminal, "🤙\u{200C}🏽"),
            (.appleTerminal, "👨👩👧👦"),
        ] as [(TerminalClient.Program, String)])
    func claimedClustersAreEmittedVerbatim(program: TerminalClient.Program, text: String) {
        // The Apple cases are the walk's own rewritten forms: re-compensating
        // an already-separated or already-decomposed emission must be the
        // identity, or a row would grow on every rebuild.
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            let out = TerminalClient.compensating(text, for: program)
            #expect(out == text, "expected verbatim, got \(out.debugDescription)")
        }
    }

    /// A pin must not leak: `TerminalWidthTraits` is read from the render path
    /// by every layout pass, and Swift Testing runs suites in parallel.
    @Test("A scoped pin does not outlive its scope")
    func pinIsScoped() {
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(Character("👩‍🚀").terminalWidth == 4)
        }
        #expect(Character("👩‍🚀").terminalWidth == 2, "the pin must not have escaped")
    }

    // MARK: - Measured against the terminals

    /// Advances that a synthetic probe never asked about, found by measuring
    /// every distinct cluster the Example emoji page actually draws against
    /// each terminal — 90-odd per host — and comparing them to the model.
    ///
    /// Three real shears turned up that way, all of them invisible to the unit
    /// tests and to the row-width arithmetic, because a model and a framework
    /// that share the same wrong number agree with each other perfectly.
    @Test(
        "Advances measured on the page match the models",
        arguments: [
            // Warp gave every SF Symbol 2 and the terminal gives 1: the only
            // one of the five models with no Plane-16 case, so no CUF was
            // emitted and the SF Symbols panel drew its border a cell left per
            // symbol.
            ("\u{100038}", TerminalClient.Program.warp, 1),
            ("\u{101867}", .warp, 1),
            // Ghostty merges a BMP text-presentation base and its modifier into
            // ONE cell, not two.
            ("☝🏻", .ghostty, 1), ("✌🏼", .ghostty, 1),
            ("✍🏽", .ghostty, 1), ("⛹🏾", .ghostty, 1),
            // iTerm2: a ZWJ sequence whose first segment carries VS-16 advances
            // 1. The base's plane is not the discriminator — ❤️ is BMP and 🏳️
            // is SMP and both behave the same.
            ("❤️‍🔥", .iTerm2, 1), ("🏳️‍🌈", .iTerm2, 1),
            // Controls: unchanged by any of the above.
            ("👍", .ghostty, 2), ("中", .iTerm2, 2), ("👍🏽", .warp, 4),
        ] as [(String, TerminalClient.Program, Int)])
    func measuredAdvancesMatchTheModels(
        text: String, program: TerminalClient.Program, expected: Int
    ) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            #expect(
                TerminalClient.cursorAdvance(of: Character(text), on: program) == expected,
                "\(program) advance for \(text)")
        }
    }

    // MARK: - The right edge

    /// The mechanism behind the original defect: a wide cluster written with
    /// fewer columns left than it needs is not split — Apple Terminal pushes
    /// the whole glyph to the next line and strands the remaining columns
    /// unpainted, which is the blank cell at the end of the row. (Warp instead
    /// runs the cursor past the right margin.) Measured on both.
    ///
    /// So the framework must never place one there. Truncation stops BEFORE
    /// adding a cluster that would exceed the budget, and it measures with
    /// `Character.terminalWidth` — now host-aware, so it respects the widened
    /// claim without being told about it. Swept over every target width, for
    /// every host, so a boundary cannot hide.
    @Test(
        "Truncation never exceeds the budget, at any width, on any host",
        arguments: [
            TerminalClient.Program.appleTerminal, .iTerm2, .ghostty, .warp, .tmux,
        ])
    func truncationNeverOverflows(program: TerminalClient.Program) {
        let rows = [
            "│ 👍🏽 ✊🏻 ☝🏽 │", "│ 👩‍🚀 👨‍👩‍👧‍👦 │", "│ ❤️‍🔥 🏳️‍🌈 │",
            "abc 👍🏽 def", "👨‍👩‍👧‍👦", "👍🏽",
        ]
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            for row in rows {
                for budget in 0...(row.strippedLength + 2) {
                    let cut = row.ansiAwarePrefix(visibleCount: budget)
                    #expect(
                        cut.strippedLength <= budget,
                        "\(program): \(row.debugDescription) cut to \(budget) measured \(cut.strippedLength)")
                    // A prefix in whole clusters — never a cluster halved.
                    #expect(
                        row.hasPrefix(cut),
                        "\(program): truncation split a cluster in \(row.debugDescription)")
                }
            }
        }
    }

    /// Truncate-then-pad — what a renderer does to fit a row to the terminal —
    /// must land on the width EXACTLY, whatever widened clusters the row holds.
    ///
    /// This is the arithmetic behind "the border lands in the right place", and
    /// both failure directions are real defects seen on a terminal: a row that
    /// measures short strands unpainted cells at the right edge, and one that
    /// measures long wraps the line.
    ///
    /// Swept from 1 to well past the content width so the boundary where a
    /// widened cluster stops fitting is crossed for every host.
    @Test(
        "Truncate-then-pad lands on the width exactly, at every width",
        arguments: [
            TerminalClient.Program.appleTerminal, .iTerm2, .ghostty, .warp, .tmux,
        ])
    func fittingARowLandsExactly(program: TerminalClient.Program) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            for content in ["👍🏽", "👩‍🚀", "👨‍👩‍👧‍👦", "❤️‍🔥", "✊🏻", "x"] {
                let row = "│ " + content + " │"
                for target in 1...(row.strippedLength + 4) {
                    let fitted = row.ansiAwarePrefix(visibleCount: target)
                        .padToVisibleWidth(target)
                    #expect(
                        fitted.strippedLength == target,
                        "\(program): \(content) fitted to \(target) measured \(fitted.strippedLength)")
                }
            }
        }
    }
}

/// These mutate the PROCESS-wide traits, which every other suite's width
/// reads would see, so they are serialized — the same treatment
/// `TerminalClientSimulationTests` gets for mutating `TerminalClient.simulated`.
@Suite("Terminal width traits — process-wide", .serialized)
struct TerminalWidthTraitsProcessTests {

    private static let keptJoiners = TerminalWidthTraits(
        zwjSequences: .decomposedKeepingJoiners, skinTone: .detached)

    @Test("Changing the process traits bumps the generation; a no-op change does not")
    @MainActor
    func generationTracksRealChanges() {
        let before = TerminalWidthTraits.generation
        let saved = TerminalWidthTraits.current
        defer { TerminalWidthTraits.current = saved }

        TerminalWidthTraits.current = Self.keptJoiners
        let afterChange = TerminalWidthTraits.generation
        #expect(afterChange > before, "a real change must bump the generation")

        TerminalWidthTraits.current = Self.keptJoiners
        #expect(
            TerminalWidthTraits.generation == afterChange,
            "assigning the same value must not invalidate every cache in the process")
    }

    @Test("A scoped pin does NOT bump the generation")
    func pinDoesNotBumpGeneration() {
        // A pin is scoped to the work that opted into it; the render path did
        // not, so bumping here would drop every cache for a test's benefit.
        let before = TerminalWidthTraits.generation
        TerminalWidthTraits.withTraits(Self.keptJoiners) {
            #expect(Character("👩‍🚀").terminalWidth == 5)
        }
        #expect(TerminalWidthTraits.generation == before)
    }

    @Test("Simulating another client republishes its traits")
    @MainActor
    func simulatingRepublishesTraits() {
        let savedSimulated = TerminalClient.simulated
        let savedTraits = TerminalWidthTraits.current
        defer {
            TerminalClient.simulated = savedSimulated
            TerminalWidthTraits.current = savedTraits
        }
        TerminalClient.simulated = .warp
        #expect(TerminalWidthTraits.current.zwjSequences == .decomposedDroppingJoiners,
                "the picker must move the claim, not just the compensation")
        TerminalClient.simulated = .ghostty
        #expect(TerminalWidthTraits.current == .composing)
    }
}
