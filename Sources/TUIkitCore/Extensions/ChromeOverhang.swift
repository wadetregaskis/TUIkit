//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeOverhang.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Chrome that paints wider than it advances

/// The framework's own chrome codepoints whose INK covers two cells while
/// every host advances them one — the paint fact, not the cursor one.
///
/// This is NOT the advance question, which is measured and closed: all 29
/// chrome corpus rows (`chrome_key`, `chrome_glyph`) advance exactly one cell
/// on Ghostty 1.3.1, iTerm2 3.6.11, Apple Terminal 455.1 and Warp
/// v0.2026.09.02 — `ChromeGlyphAdvanceTests` reads those records. It is the
/// question that measurement left open. `↵` (U+21B5) was reported in Ghostty
/// to swallow the space the status bar puts between a shortcut and its label,
/// so `↵ activate` reads as `↵activate`: the grid intact, the ink over the
/// line. U+21B5 is East Asian Width *Neutral*, so no width table predicts it
/// and only a look at the screen can say which glyphs do it.
///
/// A glyph that paints two cells occupies two cells whatever its cursor
/// advance says, and this framework's rule for that has never moved: **a claim
/// is host-independent and must cover the widest painter, or content is
/// overwritten** (``Swift/Character/isBarePictographUnderAdvancer`` states it;
/// Terminal-compatibility.md declines a per-host claim for Ghostty's SF
/// Symbols on the same grounds). The rule is about who pays, not about which
/// way the claim moves, and the asymmetry favours it more here than there: an
/// over-claim wastes a cell on hosts that draw the glyph narrow, while an
/// under-claim puts one glyph's ink on top of another's, which is the defect
/// being reported.
///
/// So a listed codepoint claims two cells everywhere, every per-host advance
/// model reports the measured one, and the existing `ECH(2)` + glyph + `CUF(1)`
/// walk — the one SF Symbols, VS-15 chrome and lone regional indicators
/// already take — squares them. Nothing here is a new kind of repair; it is a
/// new member of an existing class.
///
/// ## The table is empty, and that is the shipped state
///
/// The ink of these glyphs has never been measured on any host. There is one
/// user's observation of one glyph on one terminal, which is a report, not a
/// measurement — and a table built from it would be a guess about the other
/// twenty-eight rows and the other three hosts.
/// `Tools/TerminalProbes/overhang_card.py` is the measurement: run it inside
/// the host under test and it draws each chrome glyph in a cell flanked by
/// solid colour, so overhanging ink shows as a mark on a flank. Add one row
/// below per codepoint it shows overhanging, and record the same reading in
/// `Documentation/Terminal-compatibility.md` — with the FONT and its size,
/// because overhang is a font property at least as much as a host one.
///
/// While the table is empty every path below folds to the behaviour that
/// shipped before it existed: the claim is unchanged, no model reports a
/// shortfall, and ``Swift/String/utf8MayNeedCompensation`` admits exactly the
/// bytes it always did (``chromeOverhangGateMask`` is zero).
///
/// ## What is outside the mechanism on purpose
///
/// Box Drawing and Block Elements (`─ │ █ ▌ ▐ ▒`, U+2500…U+259F) can never be
/// listed, and ``isChromeOverhangCodepoint(_:)`` refuses them rather than
/// leaving that to whoever edits the table. For a border glyph a two-cell
/// claim is not a remedy but a second defect: every row inside the border
/// would lose a column, and the framework's most repeated glyph would double
/// in cost. If one of those is ever measured to overhang, the fix is a
/// different glyph — the choice `Documentation/Terminal-compatibility.md`
/// calls chrome glyph selection — not a wider claim.
///
/// - Note: nothing is listed yet. Do not add a row from a bug report; add it
///   from a card reading.
let chromeOverhangCodepoints: [UInt32] = [
    // 0x21B5,  // ↵ Shortcut.enter — <host> <version>, <font> <size>, <date>
]

/// The window every listed codepoint must fall in: the keyboard symbols the
/// status bar draws (U+2190…U+2423) through the geometric shapes its radio
/// buttons, disclosure triangles and steppers are drawn from (U+25A0…U+25EF).
///
/// The two hot callers — ``Swift/Unicode/Scalar/loneTerminalWidth`` and
/// ``Swift/Character/isOverhangingChromeGlyph`` — spell these bounds as
/// literals rather than reading these globals, because a width path pays a
/// one-time-initialization check for every global it touches and this one runs
/// per scalar. `ChromeOverhangTests` pins the table inside the literals, so
/// the duplication cannot drift silently.
let chromeOverhangFloor: UInt32 = 0x2190
let chromeOverhangCeiling: UInt32 = 0x25EF

/// Whether `value` is a chrome codepoint measured to paint two cells while
/// advancing one.
///
/// Out of line deliberately: the callers gate it behind the two-comparison
/// window above, so the common answer costs those two comparisons and this
/// function's body never grows the inlinable width path that calls it.
@inline(never)
func isChromeOverhangCodepoint(_ value: UInt32) -> Bool {
    // Box Drawing and Block Elements are refused here, not merely absent from
    // the table — see the table's own note. A mistaken row must not be able to
    // double every border in the framework.
    guard !(0x2500...0x259F).contains(value) else { return false }
    return chromeOverhangCodepoints.contains(value)
}

/// The UTF-8 continuation bytes ``Swift/String/utf8MayNeedCompensation`` must
/// admit for the table's codepoints: bit *n* is set when a lead `0xE2`
/// followed by `0x80 + n` can carry an overhanging glyph.
///
/// Derived from the table rather than written beside it. The gate and the
/// table have to agree — `CompensationGateTests` fails when a walk would
/// change a string the gate skipped — and a hand-maintained second list is
/// exactly how that pairing would drift. **Zero while the table is empty**, so
/// until something is measured the gate admits byte-for-byte what it always
/// has.
///
/// A `UInt64` because a UTF-8 continuation byte is `0x80…0xBF`: sixty-four
/// values, one bit each, and the gate's test is a shift and an `AND` on a
/// value it hoists out of its byte loop.
let chromeOverhangGateMask: UInt64 = chromeOverhangCodepoints.reduce(into: 0) { mask, value in
    // A U+0800…U+FFFF scalar encodes as `1110xxxx 10xxxxxx 10xxxxxx`, so its
    // SECOND byte is `0x80 | ((value >> 6) & 0x3F)` — the byte the gate can
    // test without decoding anything.
    mask |= 1 << UInt64((value >> 6) & 0x3F)
}

extension Character {
    /// Whether this cluster is a single chrome scalar whose ink overhangs the
    /// one cell every measured host advances it — claimed two, advanced one.
    ///
    /// Read by every per-host advance model exactly as
    /// ``isBarePictographUnderAdvancer`` is, so that the shortfall the widened
    /// claim opens is reported identically on every host and the one shared
    /// `ECH` + `CUF` walk closes it. The shortfall is not a host's defect: it
    /// is the price of a claim TUIkit chose, which is why every model owes it
    /// and why an unidentified host is compensated too (see
    /// ``Swift/String/withChromeOverhangCompensation()``).
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
    /// TUIkit's own deliberate over-claim rather than a description of the
    /// host: every measured host advances these one cell, and every `wcwidth`
    /// in existence answers one for them, so one is what an unnamed host is
    /// assumed to do as well.
    ///
    /// Spelled once and shared by the walk that compensates such a host
    /// (``Swift/String/withChromeOverhangCompensation()``) and by the oracle
    /// that checks the walk conserves — two spellings of one model is how a
    /// conservation test comes to certify a walk against itself.
    public var unidentifiedHostCursorAdvance: Int {
        isOverhangingChromeGlyph ? 1 : terminalWidth
    }
}
