//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalImagePlaceholder.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The one Plane-16 codepoint that is not a glyph

extension Unicode.Scalar {

    /// U+10EFFF — the Kitty graphics protocol's **image placeholder**: the
    /// character a terminal replaces with part of a picture.
    ///
    /// An image transmitted to a terminal and given a *virtual* placement is
    /// not drawn anywhere until cells carrying this codepoint appear. Each
    /// such cell says which image (the id, carried in the cell's foreground
    /// colour) and which part of it (the row and column, carried in combining
    /// diacritics), and the terminal paints that part of the picture there.
    /// The image is therefore made of ordinary cells — measured, clipped,
    /// scrolled, composited and diffed like any other text — which is the
    /// whole reason this framework can afford to draw pictures at all. See
    /// `Documentation/Terminal graphics protocols.md`.
    ///
    /// ## Why it needs naming here, in the width code
    ///
    /// It sits inside the Plane-16 Private Use Area, U+100000…U+10FFFD, and
    /// this framework has a rule about that whole range: those codepoints are
    /// SF Symbols, every measured host paints one **two cells wide and
    /// advances one**, and the walks compensate with `ECH` + glyph + `CUF`
    /// (``TerminalQuirks/planeSixteenPUA``).
    ///
    /// A placeholder is the opposite kind of thing. It is not a glyph at all —
    /// no font has it, and a terminal implementing the protocol never draws it
    /// — so it occupies **one** cell and advances one, like a letter.
    /// Measured 2026-09-02 with `Tools/TerminalProbes/placement_probe.py` on
    /// Ghostty 1.3.1, Warp and Apple Terminal 455.1: a row of twelve
    /// placeholder cells advances exactly twelve columns on all three,
    /// including the two that do not implement the protocol.
    ///
    /// Left inside the general rule, every placeholder cell would be erased
    /// and pushed past, and an image would shear one cell further right on
    /// each column — which reads as a picture in the wrong place rather than
    /// as a bug, and is why the exemption is by codepoint and tested.
    public static let terminalImagePlaceholder: Unicode.Scalar = "\u{10EFFF}"
}

// MARK: - Distinguishing the two

extension Character {

    /// Whether `value` is a Plane-16 Private Use Area codepoint a terminal
    /// draws as a **glyph** — an SF Symbol — rather than
    /// ``Unicode/Scalar/terminalImagePlaceholder``, which it intercepts.
    ///
    /// Every Plane-16 test in this module goes through here, so the exemption
    /// cannot be applied in the width table and forgotten in one host's
    /// advance model — a discrepancy that would not shear the row (both
    /// numbers would be self-consistently wrong by different amounts) but
    /// would emit a compensation for a character that needs none.
    static func isPlaneSixteenGlyph(_ value: UInt32) -> Bool {
        (0x100000...0x10FFFD).contains(value)
            && value != Unicode.Scalar.terminalImagePlaceholder.value
    }
}
