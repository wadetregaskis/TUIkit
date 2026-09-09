//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+RowBuilder.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Which colour a cell takes

extension ASCIIConverter {
    /// The colour a pixel is drawn in under `mode` — the palette entry it
    /// quantises to, the grey ramp step, or the pixel itself at truecolor —
    /// and `nil` for a mode that draws no colour at all.
    ///
    /// The one place the question is answered. The escape strings
    /// (``foregroundColorCode(for:mode:)``) and the byte writer
    /// (``ANSIRowBuilder``) both spell out what this returns, so the two can
    /// never disagree about which colour a cell got — only about how it is
    /// written down.
    func cellColor(for pixel: RGBA, mode: ASCIIColorMode) -> Color? {
        switch mode {
        case .trueColor:
            return .rgb(pixel.r, pixel.g, pixel.b)
        case .ansi256:
            return ASCIIPalette.ansi256.color(nearestTo: pixel)
        case .ansi16:
            return ASCIIPalette.ansi16.color(nearestTo: pixel)
        case .grayscale:
            return .palette(UInt8(232 + Self.greyRampStep(for: pixel)))
        case .mono:
            return nil
        case .palette(let palette):
            return palette.color(nearestTo: pixel)
        }
    }

    /// Which of the terminal's 24 grey-ramp steps a pixel takes: 0 for palette
    /// entry 232 (`#080808`) through 23 for entry 255 (`#eeeeee`).
    ///
    /// A function rather than an expression inside `cellColor` because
    /// `.grayscale` is 24 shades in BOTH renderings of a picture. The glyph
    /// path sends the step as an index, `38;5;232`…`38;5;255`; a picture
    /// transmitted to the terminal as pixels has no index to send, so
    /// `recoloured` posterises with `greyRampGrey(for:)` instead — the RGB the
    /// terminal would have painted for that same index, at the same stage this
    /// is consulted at. It used to send the raw luminance, and then 246 of the
    /// 256 neutral levels came out a different grey on a terminal with graphics
    /// support than on one without, by up to 17 of 255: pure white drew as
    /// white there and as `#eeeeee` next door.
    ///
    /// Equal slices of the luminance range, deliberately — scaling by 23 gave
    /// the top step exactly one input and clipped every highlight a step dark.
    /// See `GreyRampBandTests`.
    ///
    /// Equal slices also mean the ramp's own entries are NOT fixed points of
    /// this: the bands have pitch 10.625 and the entries pitch 10, so entries
    /// 138…238 each fall one band low. Nothing may write a ramp entry into a
    /// buffer that is later posterised again — see the `PixelQuantiser.grey`
    /// comment.
    @inline(__always)
    static func greyRampStep(for pixel: RGBA) -> Int {
        min(Int(pixel.luminance / 255.0 * 24.0), 23)
    }

    /// The grey the terminal paints for `pixel`'s ramp step: 8, 18, … 238, the
    /// RGB of palette entries 232…255, and so neither pure black nor pure
    /// white. See `greyRampStep(for:)`.
    ///
    /// Not `Color.palette256ToRGB`, which answers the same question: it is
    /// `package` and not inlinable, so it would be a cross-module call — with a
    /// `switch` and the colour cube's array literal behind it — on a loop that
    /// runs per pixel of a megapixel picture. The duplication is pinned to that
    /// function by `GreyRampBandTests`, which asserts the two agree on every
    /// one of the 256 neutral levels.
    @inline(__always)
    static func greyRampGrey(for pixel: RGBA) -> UInt8 {
        UInt8(8 + 10 * greyRampStep(for: pixel))
    }
}

extension ASCIIPalette {
    /// The entry nearest `pixel`, as the colour that will be emitted for it.
    ///
    /// A semantic entry cannot survive `resolved(with:)`, and if one somehow
    /// does the entry's mid-grey stand-in is what is drawn — the same answer
    /// ``sgrParameters(at:background:)`` gives.
    func color(nearestTo pixel: RGBA) -> Color {
        let index = nearestIndex(to: pixel)
        guard colors.indices.contains(index) else { return .rgb(0, 0, 0) }
        if case .semantic = colors[index].value {
            let grey = entries[index].rgba
            return .rgb(grey.r, grey.g, grey.b)
        }
        return colors[index]
    }
}

// MARK: - A row of coloured cells, written as bytes

/// Assembles one row of the glyph renderer's output as UTF-8 bytes, emitting
/// a colour escape only where the colour changes, and turns it into a
/// `String` once at the end.
///
/// ## Why bytes
///
/// The converters used to build an escape STRING for every cell — the
/// `"\(csi)38;2;\(r);\(g);\(b)m"` interpolation — compare it with the last
/// cell's, and append it when it differed. Profiled at truecolor, 120×50
/// cells, release: 97% of the frame was inside `convertHalfBlocksColor`, and
/// almost all of that was the interpolation itself — `_int64ToString`,
/// `_StringGuts.append`, the allocation and free of three small strings per
/// cell, and the availability checks String's appends make on macOS. Not the
/// picture; the spelling of the picture. 790 ns a cell for a mode that
/// searches no palette at all.
///
/// So the colour is decided as a `Color` — an enum compare against the last
/// cell — and only a CHANGE is written, straight into a byte array with a
/// three-digit formatter, and the row becomes a `String` once. The bytes are
/// exactly the ones the strings were: the same escapes, in the same order,
/// with the same resets, so every converter's output is byte-identical to
/// what it produced before, and the tests that pin those outputs say so.
struct ANSIRowBuilder {
    private var bytes: [UInt8] = []
    private var foreground: Color?
    private var background: Color?
    /// Whether the row has emitted any colour yet — what decides the closing
    /// reset, and (for the converters that only reset between two colours)
    /// whether a change is preceded by one.
    private var painted = false

    /// - Parameter capacity: A guess at the row's bytes, so the common case
    ///   never reallocates.
    init(capacity: Int) {
        bytes.reserveCapacity(capacity)
    }

    /// Sets the colours for the cells that follow, writing escapes only if
    /// either differs from the current ones.
    ///
    /// - Parameters:
    ///   - foreground: The foreground, or `nil` for none.
    ///   - background: The background, or `nil` for none.
    ///   - bold: Whether to precede the colours with SGR 1 — the half-block
    ///     renderer's guard for a foreground that has to survive a bold
    ///     terminal. Written only on a change, with the colours.
    ///   - resetFirst: Whether a change is always preceded by a reset, even
    ///     the row's first. The half-block renderer always resets; the others
    ///     reset only between two painted runs. Both spellings are kept
    ///     exactly, because both are pinned by tests.
    mutating func setColors(
        foreground: Color?, background: Color?, bold: Bool = false, resetFirst: Bool = false
    ) {
        guard foreground != self.foreground || background != self.background else { return }
        if resetFirst || painted { reset() }
        if bold { appendCSI([0x31]) }  // "1"
        if let foreground { appendEscape(foreground, background: false) }
        if let background { appendEscape(background, background: true) }
        self.foreground = foreground
        self.background = background
        painted = painted || foreground != nil || background != nil
    }

    /// Appends one cell's glyph.
    mutating func append(_ character: Character) {
        bytes.append(contentsOf: character.utf8)
    }

    /// Appends one ASCII byte — a space, most often.
    mutating func append(ascii byte: UInt8) {
        bytes.append(byte)
    }

    /// The row, with a closing reset if anything was painted.
    mutating func finish() -> String {
        if foreground != nil || background != nil { reset() }
        return String(unsafeUninitializedCapacity: bytes.count) { buffer in
            _ = buffer.initialize(fromContentsOf: bytes)
            return bytes.count
        }
    }

    // MARK: - Escapes

    private mutating func reset() {
        bytes.append(contentsOf: [0x1B, 0x5B, 0x30, 0x6D])  // ESC [ 0 m
    }

    /// `ESC [ <parameters> m`.
    private mutating func appendCSI(_ parameters: [UInt8]) {
        bytes.append(0x1B)
        bytes.append(0x5B)
        bytes.append(contentsOf: parameters)
        bytes.append(0x6D)
    }

    /// The colour's SGR escape — what ``ASCIIPalette/sgrParameters(at:background:)``
    /// spells, written as bytes.
    private mutating func appendEscape(_ color: Color, background: Bool) {
        bytes.append(0x1B)
        bytes.append(0x5B)
        switch color.value {
        case .rgb(let red, let green, let blue):
            appendNumber(background ? 48 : 38)
            bytes.append(0x3B)
            bytes.append(0x32)  // "2"
            bytes.append(0x3B)
            appendNumber(Int(red))
            bytes.append(0x3B)
            appendNumber(Int(green))
            bytes.append(0x3B)
            appendNumber(Int(blue))
        case .palette256(let index):
            appendNumber(background ? 48 : 38)
            bytes.append(0x3B)
            bytes.append(0x35)  // "5"
            bytes.append(0x3B)
            appendNumber(Int(index))
        case .standard(let ansi):
            appendNumber((background ? 40 : 30) + Int(ansi.rawValue))
        case .bright(let ansi):
            appendNumber((background ? 100 : 90) + Int(ansi.rawValue))
        case .semantic:
            // Unreachable after `cellColor`, which stands a semantic entry in
            // with its grey; written as the default so a row is never left
            // with a half-emitted escape.
            appendNumber(background ? 49 : 39)
        }
        bytes.append(0x6D)
    }

    /// A non-negative decimal, at most three digits — every SGR parameter
    /// the converters emit.
    private mutating func appendNumber(_ value: Int) {
        if value >= 100 {
            bytes.append(UInt8(0x30 + value / 100))
            bytes.append(UInt8(0x30 + (value / 10) % 10))
            bytes.append(UInt8(0x30 + value % 10))
        } else if value >= 10 {
            bytes.append(UInt8(0x30 + value / 10))
            bytes.append(UInt8(0x30 + value % 10))
        } else {
            bytes.append(UInt8(0x30 + value))
        }
    }
}
