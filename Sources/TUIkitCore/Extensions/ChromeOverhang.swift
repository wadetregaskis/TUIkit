//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeOverhang.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Chrome that paints wider than it advances

extension TerminalWidthTraits {

    /// Which of the framework's own chrome codepoints THIS host paints across
    /// two cells while advancing the cursor one — the paint fact, not the
    /// cursor one.
    ///
    /// This is NOT the advance question, which is measured and closed: all 29
    /// chrome corpus rows (`chrome_key`, `chrome_glyph`) advance exactly one
    /// cell on Ghostty 1.3.1, iTerm2 3.6.11, Apple Terminal 455.1 and Warp
    /// v0.2026.09.02 — `ChromeGlyphAdvanceTests` reads those records. This is
    /// the question that measurement left open: `↵` (U+21B5) was reported in
    /// Ghostty to swallow the space the status bar puts between a shortcut and
    /// its label, so `↵ activate` reads as `↵activate` — the grid intact, the
    /// ink over the line. U+21B5 is East Asian Width *Neutral*, so no width
    /// table predicts it and only a look at the screen can say which glyphs do
    /// it.
    ///
    /// ## The measurement
    ///
    /// Read on 2026-09-04 with `Tools/TerminalProbes/overhang_card.py`, which
    /// draws each chrome glyph in one cell between two flanks of solid magenta
    /// so that overhanging ink shows as a mark on a flank. A **paint**
    /// measurement read by a person, not a DSR reply: the machine version
    /// (`landing_probe.py`) needs screenshots, and those need a Screen
    /// Recording grant this project does not have.
    /// `Documentation/Terminal-compatibility.md` carries the reading in full,
    /// including what the card said about the rows that do NOT overhang.
    ///
    /// ## Why this follows the host, when the claim's own rule says otherwise
    ///
    /// TUIkit's standing rule is that a claim covers the widest painter and
    /// the narrow painters take a blank cell (`Character`'s
    /// `isBarePictographUnderAdvancer` states it). Under that rule this would
    /// be one host-independent table: the union of the eight codepoints below.
    ///
    /// The union is wrong for 24 of the 32 measured (host, glyph) pairs —
    /// eight codepoints against four hosts, only eight of those cells reading
    /// "overhangs". It would put a stray blank cell after all eight glyphs on
    /// Apple Terminal and iTerm2, after seven of them on Ghostty, and after
    /// `↵` on Warp. And the two overhanging sets are DISJOINT — Ghostty's one
    /// glyph is not in Warp's seven — so no uniform claim is right for both:
    /// whichever way a single table leans, it scatters blanks through the
    /// status bar of hosts whose glyphs fit. ``TerminalWidthTraits``'s own
    /// "What this does not cover" said a class like this "would need its own
    /// measured rule"; this now has one, on all four hosts.
    ///
    /// The claim still covers the widest painter — per host, which is the
    /// unit the measurement came in.
    public enum ChromeOverhang: String, Sendable, Equatable, CaseIterable {

        /// Every chrome glyph's ink stays inside the cell it advances.
        ///
        /// Apple Terminal 455.1 and iTerm2 3.6.11, card-read 2026-09-04: not
        /// one of the 29 rows marked a flank. Also every host TUIkit has NOT
        /// measured, `TerminalClient.Program.unidentified` and tmux included —
        /// widening a claim on an unmeasured host would scatter blank cells
        /// through its status bar for a defect nobody has seen there.
        ///
        /// Deliberately not spelled `none`: this type appears in optional
        /// positions (`Optional<ChromeOverhang>.none`), and a case that
        /// collides with `Optional`'s own is how an implicit member resolves
        /// to the wrong thing without a diagnostic.
        case contained

        /// `↵` U+21B5 alone. Ghostty 1.3.1, card-read 2026-09-04 — the glyph
        /// the original report named, on the host it named, and the only row
        /// Ghostty marked a flank for. The seven Warp overhangs do not: this
        /// set is not a subset of that one.
        case returnArrow

        /// The seven keyboard symbols `⎋ ⏎ ⌫ ⌦ ␣ ⌥ ⌘`. Warp v0.2026.09.02,
        /// card-read 2026-09-04.
        ///
        /// **Not `↵` U+21B5**, which Warp draws inside its cell — the exact
        /// reverse of Ghostty, and the reason this dimension cannot be one
        /// table. Not the arrows (`↑ ↓ ← →`), `⇥ ⇤`, `⇧` or `⌃` either; the
        /// table below is the authority on which seven.
        case keyboardSymbols
    }
}

extension TerminalWidthTraits.ChromeOverhang {

    /// The codepoints this host paints two cells wide while advancing one.
    ///
    /// The one table. The enum selects among these sets and the sets live
    /// here, so that the gate mask, the box-drawing refusal and every test can
    /// be derived from the same rows rather than restating them — a constant
    /// transcribed twice is how this project shipped seventeen passing tests
    /// against the wrong codepoint.
    ///
    /// Internal, not public: which glyphs a host smears is the framework's own
    /// record of its own chrome, not something an app composes against. The
    /// case is public because the traits value carrying it is.
    var codepoints: [UInt32] {
        switch self {
        // The empty array literal is the shared empty singleton — no
        // allocation, which matters because `overhangs(_:)` is per scalar.
        case .contained: []
        case .returnArrow: Self.ghosttyCodepoints
        case .keyboardSymbols: Self.warpCodepoints
        }
    }

    /// Ghostty 1.3.1, `overhang_card.py`, 2026-09-04.
    static let ghosttyCodepoints: [UInt32] = [
        0x21B5  // ↵ key_return — Shortcut.enter
    ]

    /// Warp v0.2026.09.02, `overhang_card.py`, 2026-09-04.
    static let warpCodepoints: [UInt32] = [
        0x238B,  // ⎋ key_escape — Shortcut.escape
        0x23CE,  // ⏎ key_return_symbol — Shortcut.returnKey
        0x232B,  // ⌫ key_backspace — Shortcut.backspace
        0x2326,  // ⌦ key_delete — Shortcut.delete
        0x2423,  // ␣ key_space — Shortcut.space
        0x2325,  // ⌥ key_option — Shortcut.option
        0x2318,  // ⌘ key_command — Shortcut.command
    ]

    /// Whether this host paints `value` across two cells.
    ///
    /// Box Drawing and Block Elements are refused HERE rather than merely
    /// being absent from the tables, so that a mistaken row is inert instead
    /// of catastrophic. For a border glyph a two-cell claim is not a remedy
    /// but a second defect: every row inside the border would lose a column,
    /// and the framework's most repeated glyph would double in cost. The card
    /// measured all six (`─ │ █ ▌ ▐ ▒`) contained on all four hosts; if one is
    /// ever measured to overhang, the fix is a different glyph — the choice
    /// `Documentation/Terminal-compatibility.md` calls chrome glyph
    /// selection — not a wider claim.
    func overhangs(_ value: UInt32) -> Bool {
        guard !(0x2500...0x259F).contains(value) else { return false }
        return codepoints.contains(value)
    }
}

/// The window every listed codepoint must fall in: the keyboard symbols the
/// status bar draws (U+2190…U+2423) through the geometric shapes its radio
/// buttons, disclosure triangles and steppers are drawn from (U+25A0…U+25EF).
///
/// The two hot callers — ``Swift/Unicode/Scalar/loneTerminalWidth`` and
/// ``Swift/Character/isOverhangingChromeGlyph`` — spell these bounds as
/// literals rather than reading these globals, because a width path pays a
/// one-time-initialization check for every global it touches and this one runs
/// per scalar. `ChromeOverhangTests` pins every host's table inside the
/// literals, so the duplication cannot drift silently.
let chromeOverhangFloor: UInt32 = 0x2190
let chromeOverhangCeiling: UInt32 = 0x25EF

/// Whether `value` is a chrome codepoint the host in force was measured to
/// paint two cells wide while advancing one.
///
/// Reads ``TerminalWidthTraits/current`` — the CLAIM in force, which is what
/// this question is about. It is not a lookup keyed by the host doing the
/// painting: the shortfall a widened claim opens is owed by whichever advance
/// model emits the row, so all five models ask this same question and get the
/// same answer (see ``Swift/Character/isOverhangingChromeGlyph``).
///
/// Out of line deliberately: the callers gate it behind the two-comparison
/// window above, so the common answer costs those two comparisons and this
/// function's body never grows the inlinable width path that calls it.
@inline(never)
func isChromeOverhangCodepoint(_ value: UInt32) -> Bool {
    // The host-INDEPENDENT union first, and this ordering is about cost rather
    // than correctness: before the sets followed the host this function was one
    // walk of one constant array, and ▶ ● ◯ ▲ — the geometric shapes a page is
    // full of — are inside the window and in no host's set. Rejecting them
    // against the union leaves that case exactly as cheap as it was, and only
    // the eight glyphs that COULD be widened pay for the task-local read that
    // asks whose terminal this is.
    guard chromeOverhangUnion.contains(value) else { return false }
    return TerminalWidthTraits.current.chromeOverhang.overhangs(value)
}

/// Every codepoint ANY measured host smears — the constant the hot path tests
/// before it asks which host is painting.
///
/// Not a second table: derived from the per-host sets, like
/// ``chromeOverhangGateMask``, so it cannot name a codepoint no host lists.
let chromeOverhangUnion: [UInt32] = TerminalWidthTraits.ChromeOverhang.allCases
    .flatMap(\.codepoints)

/// The UTF-8 continuation bytes ``Swift/String/utf8MayNeedCompensation`` must
/// admit for the tables' codepoints: bit *n* is set when a lead `0xE2`
/// followed by `0x80 + n` can carry an overhanging glyph on ANY host.
///
/// The union of every host's set, and host-independent on purpose. The gate
/// decides only whether the per-`Character` walk RUNS; the walk then asks the
/// claim in force, per character, what to emit. So a false positive costs a
/// walk that finds nothing, while a false negative skips a row that needed a
/// `CUF` and shears it — and a per-host mask would have to be re-read whenever
/// the traits moved, in a gate whose whole job is to be a byte test cheap
/// enough to run on every rebuilt row.
///
/// Derived from the tables rather than written beside them. The gate and the
/// tables have to agree — `CompensationGateTests` fails when a walk would
/// change a string the gate skipped — and a hand-maintained second list is
/// exactly how that pairing would drift.
///
/// A `UInt64` because a UTF-8 continuation byte is `0x80…0xBF`: sixty-four
/// values, one bit each, and the gate's test is a shift and an `AND` on a
/// value it hoists out of its byte loop.
let chromeOverhangGateMask: UInt64 = TerminalWidthTraits.ChromeOverhang.allCases
    .flatMap(\.codepoints)
    .reduce(into: 0) { mask, value in
        // A U+0800…U+FFFF scalar encodes as `1110xxxx 10xxxxxx 10xxxxxx`, so
        // its SECOND byte is `0x80 | ((value >> 6) & 0x3F)` — the byte the
        // gate can test without decoding anything.
        mask |= 1 << UInt64((value >> 6) & 0x3F)
    }

extension Character {
    /// Whether this cluster is a single chrome scalar whose ink overhangs the
    /// one cell every measured host advances it — claimed two, advanced one.
    ///
    /// Read by every per-host advance model exactly as
    /// ``isBarePictographUnderAdvancer`` is, and — this is the surprising
    /// part — the answer does NOT depend on which model is asking. It depends
    /// on the traits in force, because the shortfall is not a host's defect:
    /// it is the price of a claim TUIkit widened, so whoever emits a row under
    /// that claim owes the `CUF` that closes it. That is why the models share
    /// one question, why an unidentified host is compensated too (see
    /// ``Swift/String/withChromeOverhangCompensation()``), and why a
    /// diagnostic rendering as another client stays self-consistent.
    ///
    /// In a real app the two coincide: startup publishes the identified host's
    /// traits, so the claim in force IS this host's measurement.
    var isOverhangingChromeGlyph: Bool {
        let scalars = unicodeScalars
        guard scalars.count == 1, let only = scalars.first else { return false }
        let value = only.value
        // The window from `chromeOverhangFloor`/`Ceiling`, as literals — see
        // their note.
        guard value >= 0x2190, value <= 0x25EF else { return false }
        return isChromeOverhangCodepoint(value)
    }

    /// The columns an UNIDENTIFIED host moves the cursor by — the fifth entry
    /// in a table of four measured models, and the only one that is a
    /// deduction rather than a measurement.
    ///
    /// The claim, because a terminal TUIkit cannot name is assumed to have no
    /// defects. The exception is the chrome-overhang class, where the claim is
    /// TUIkit's own over-claim rather than a description of the host: every
    /// measured host advances these one cell, and every `wcwidth` in existence
    /// answers one for them, so one is what an unnamed host is assumed to do
    /// as well.
    ///
    /// An unidentified host's own traits are ``TerminalWidthTraits/ChromeOverhang/contained``,
    /// so in an ordinary unidentified process nothing is widened and this
    /// answers the claim for every cluster. It earns its keep when the traits
    /// in force came from somewhere else — the quirks explorer pinning a
    /// measured host's claims while emitting through the unidentified path —
    /// where the widened claim must still be squared.
    ///
    /// Spelled once and shared by the walk that compensates such a host
    /// (``Swift/String/withChromeOverhangCompensation()``) and by the oracle
    /// that checks the walk conserves — two spellings of one model is how a
    /// conservation test comes to certify a walk against itself.
    public var unidentifiedHostCursorAdvance: Int {
        isOverhangingChromeGlyph ? 1 : terminalWidth
    }
}
