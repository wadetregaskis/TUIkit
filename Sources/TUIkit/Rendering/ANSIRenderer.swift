//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Generates ANSI escape codes for terminal formatting.
///
/// `ANSIRenderer` translates `TextStyle` and `Color` into the corresponding
/// ANSI escape sequences that are understood by most terminals.
enum ANSIRenderer {
    /// The escape character for ANSI sequences.
    static let escape = "\u{1B}"

    /// The Control Sequence Introducer (CSI).
    static let csi = "\(escape)["

    /// Reset code that clears all formatting.
    static let reset = "\(csi)0m"

    /// Dim/faint text style code.
    static let dim = "\(csi)2m"

    // MARK: - SGR Style Codes

    /// Named constants for ANSI SGR (Select Graphic Rendition) attribute codes.
    ///
    /// These replace bare string literals like `"1"`, `"7"` in `buildStyleCodes()`.
    private enum StyleCode {
        static let bold = "1"
        static let dim = "2"
        static let italic = "3"
        static let underline = "4"
        static let blink = "5"
        static let inverse = "7"
        static let strikethrough = "9"
    }

    // MARK: - Cursor Control

    /// Hides the cursor.
    static let hideCursor = "\(csi)?25l"

    /// Shows the cursor.
    static let showCursor = "\(csi)?25h"

    // MARK: - Alternate Screen Buffer

    /// Enters the alternate screen buffer.
    static let enterAlternateScreen = "\(csi)?1049h"

    /// Exits the alternate screen buffer.
    static let exitAlternateScreen = "\(csi)?1049l"
}

// MARK: - Internal API

extension ANSIRenderer {
    /// Renders text with the specified style.
    ///
    /// - Parameters:
    ///   - text: The text to render.
    ///   - style: The TextStyle to apply.
    /// - Returns: The formatted string with ANSI codes.
    static func render(_ text: String, with style: TextStyle) -> String {
        guard let sequence = styleSequence(for: style) else { return text }
        return "\(sequence)\(text)\(reset)"
    }

    /// The SGR introducer ``render(_:with:)`` would emit for `style`, or `nil`
    /// when the style is empty — the case where `render` returns its text
    /// untouched.
    ///
    /// Exposed so a caller styling **many** strings the same way can build the
    /// sequence once and wrap each of them as `sequence + text + reset`, which
    /// is byte-for-byte what `render` produces. Every `render` call otherwise
    /// rebuilds the identical `TextStyle`, re-derives its codes and re-joins
    /// them: a `Table` row colours every cell with the same foreground, so a
    /// 6-column table did that six times per row, per frame.
    static func styleSequence(for style: TextStyle) -> String? {
        let codes = buildStyleCodes(style)
        if codes.isEmpty { return nil }
        return "\(csi)\(codes.joined(separator: ";"))m"
    }

    /// Generates the ANSI escape sequence for a background color.
    ///
    /// Use this to set only the background color without other styles.
    ///
    /// - Parameter color: The background color.
    /// - Returns: The ANSI escape sequence.
    static func backgroundCode(for color: Color) -> String {
        color.backgroundEscape()
    }

    /// Applies foreground color to a string using `TextStyle` + `render()`.
    ///
    /// This is the centralized replacement for the many per-file
    /// `colorize` / `colorizeBorder` / `colorizeWithForeground` helpers.
    ///
    /// - Parameters:
    ///   - string: The text to colorize.
    ///   - foreground: Optional foreground color.
    ///   - background: Optional background color.
    ///   - bold: Whether to apply bold.
    ///   - underline: Whether to apply underline.
    /// - Returns: The ANSI-formatted string.
    static func colorize(
        _ string: String,
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool = false,
        underline: Bool = false
    ) -> String {
        var style = TextStyle()
        style.foregroundColor = foreground
        style.backgroundColor = background
        style.isBold = bold
        style.isUnderlined = underline
        return render(string, with: style)
    }

    /// Wraps a string in a background color that persists across ANSI resets.
    ///
    /// Every occurrence of the reset code inside `string` — the collapsed
    /// spelling `ESC[0;…m` included, see ``splittingCollapsedResets(_:)`` —
    /// is replaced with `reset + bgCode`, so the background "survives"
    /// foreground-color resets.
    /// This is necessary for container backgrounds where inner content contains
    /// its own ANSI reset sequences.
    ///
    /// - Parameters:
    ///   - string: The text to wrap.
    ///   - color: The background color.
    /// - Returns: The string with persistent background applied.
    static func applyPersistentBackground(_ string: String, color: Color) -> String {
        let bgCode = backgroundCode(for: color)
        return bgCode + restating(bgCode, afterResetsIn: string)
    }

    /// Wraps a string in faint (SGR 2) that persists across ANSI resets.
    ///
    /// The dim twin of ``applyPersistentBackground(_:color:)``, and needed for
    /// the same reason: a styled line already contains a reset per run, and a
    /// bare `dim … reset` wrapper dies at the first of them. A Table row begins
    /// with a one-cell selection indicator, so the naive wrapper cancelled
    /// itself before a single character of text and the row drew at full
    /// intensity — the "`.dimmed` does not dim" bug.
    ///
    /// - Parameter string: The text to draw faint.
    /// - Returns: The string with persistent dim applied.
    static func applyPersistentDim(_ string: String) -> String {
        dim + restating(dim, afterResetsIn: string) + reset
    }

    /// Wraps a string in reverse video (SGR 7) over a stated pair, restated after
    /// every reset, and closes it with a reset.
    ///
    /// The reverse twin of ``applyPersistentDim(_:)``, with one difference that is
    /// the point of it: the ink and the field are restated along with the 7, as
    /// `ESC[7;<ink>;<field>m`. A bare 7 exchanges the colours in force, and after a
    /// reset those are the TERMINAL's defaults, not the palette's. A row's padding
    /// is plain spaces after its content's last reset, so restating only the 7
    /// would fill those cells with the terminal's own foreground on a page the
    /// palette paints, and the bar would come out in two colours. With the pair
    /// restated, the 7 exchanges exactly `ink` and `field`, and a 39 or 49 is
    /// emitted only where one of them is the terminal's own colour. What each host
    /// paints for SGR 7 is recorded under "Reverse video (SGR 7)" in
    /// `Documentation/Terminal-compatibility.md`.
    ///
    /// A child that states its own colours still reverses its own pair: the
    /// restatement comes before whatever follows the reset.
    ///
    /// - Parameters:
    ///   - string: The text to draw reversed.
    ///   - ink: The colour the text would be drawn in, which reverse video paints
    ///     as the cell.
    ///   - field: The colour the cell would be filled with, which reverse video
    ///     draws the glyph in.
    /// - Returns: The string with persistent reverse video applied.
    static func applyPersistentReverse(_ string: String, ink: Color, field: Color) -> String {
        var style = TextStyle()
        style.isInverted = true
        style.foregroundColor = ink
        style.backgroundColor = field
        // Never nil: the 7 alone is a code, whatever the depth makes of the colours.
        let opening = styleSequence(for: style) ?? "\(csi)\(StyleCode.inverse)m"
        return opening + restating(opening, afterResetsIn: string) + reset
    }

    /// `ESC[0;<params>m` spelled as `ESC[0m ESC[<params>m`, so that a
    /// re-injection keyed on the literal reset sees every reset.
    ///
    /// `collapsingAdjacentSGR` nets a reset and the styling after it into one
    /// escape, and opacity resolution collapses the rows it rebuilds — so a
    /// row that has been through a fade begins its faded span with the fused
    /// spelling. The persistent-style wrappers above re-state their style
    /// after each `ESC[0m`; keyed on the literal alone they missed the fused
    /// one, and a dimmed row un-dimmed from the fade onward. One splitter,
    /// used by both wrappers and by the replay's background restoration.
    static func splittingCollapsedResets(_ string: String) -> String {
        string.replacing("\u{1B}[0;", with: reset + "\u{1B}[")
    }

    /// `string` with `restore` re-stated after every reset it contains, a
    /// collapsed `ESC[0;…m` counting as a reset followed by the rest — what
    /// `splittingCollapsedResets(string).replacing(reset, with: reset +
    /// restore)` produces, byte for byte, in one pass over the bytes instead
    /// of two generic searches, since it runs once per rebuilt row and once
    /// per animated run patched on every tick (8% of a live frame between
    /// them).
    ///
    /// The two-step form's exact behaviour is kept, including its edges: a
    /// split that the first step creates (`ESC[0;0;31m` → `ESC[0m ESC[0;31m`)
    /// is not split again, but an `ESC[0m` the split forms (`ESC[0;0m` →
    /// `ESC[0m ESC[0m`) is a reset the second step sees and restores after.
    /// `RestatingAfterResetsTests` pins the two equal on randomised input.
    ///
    /// - Parameters:
    ///   - string: A styled line or fragment.
    ///   - restore: The sequence to re-state after each reset (a background,
    ///     a dim) — appended verbatim.
    static func restating(_ restore: String, afterResetsIn string: String) -> String {
        guard !restore.isEmpty else { return string }
        // A line with no `ESC [ 0` in it has nothing to restore after, and is
        // most styled lines: found without copying the bytes first.
        let hasResetIntroducer =
            string.utf8.withContiguousStorageIfAvailable { buffer -> Bool in
                var index = 0
                while index + 2 < buffer.count {
                    if buffer[index] == 0x1B, buffer[index + 1] == 0x5B, buffer[index + 2] == 0x30 {
                        return true
                    }
                    index += 1
                }
                return false
            } ?? true
        guard hasResetIntroducer else { return string }
        let bytes = Array(string.utf8)
        let restoreBytes = Array(restore.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + restoreBytes.count * 4)
        let resetBytes: [UInt8] = [0x1B, 0x5B, 0x30, 0x6D]  // ESC [ 0 m
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x1B, index + 3 < bytes.count, bytes[index + 1] == 0x5B, bytes[index + 2] == 0x30 {
                if bytes[index + 3] == 0x6D {  // ESC[0m — a reset: restore after it
                    out.append(contentsOf: resetBytes)
                    out.append(contentsOf: restoreBytes)
                    index += 4
                    continue
                }
                if bytes[index + 3] == 0x3B {  // ESC[0; — split into a reset and the rest
                    out.append(contentsOf: resetBytes)
                    out.append(contentsOf: restoreBytes)
                    out.append(0x1B)
                    out.append(0x5B)
                    index += 4
                    // The `ESC[` just written plus a following `0m` is an
                    // `ESC[0m` the second step would have matched; a following
                    // `0;` is a split the first step would NOT have (it does not
                    // re-scan what it wrote).
                    if index + 1 < bytes.count, bytes[index] == 0x30, bytes[index + 1] == 0x6D {
                        out.append(0x30)
                        out.append(0x6D)
                        out.append(contentsOf: restoreBytes)
                        index += 2
                    }
                    continue
                }
            }
            out.append(bytes[index])
            index += 1
        }
        // The bytes are the input's own UTF-8 plus ASCII escapes, so the
        // decode cannot fail; the lint rule is about `Data`, and there is none.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: out, as: UTF8.self)
    }

    /// Moves the cursor to the specified position.
    ///
    /// - Parameters:
    ///   - row: The row (1-based).
    ///   - column: The column (1-based).
    /// - Returns: The ANSI escape sequence.
    static func moveCursor(toRow row: Int, column: Int) -> String {
        "\(csi)\(row);\(column)H"
    }
}

// MARK: - Private Helpers

extension ANSIRenderer {
    /// Builds the ANSI codes for a TextStyle.
    ///
    /// - Parameter style: The TextStyle to convert.
    /// - Returns: An array of ANSI code strings.
    fileprivate static func buildStyleCodes(_ style: TextStyle) -> [String] {
        var codes: [String] = []

        // Text attributes
        if style.isBold == true {
            codes.append(StyleCode.bold)
        }
        if style.isDim == true {
            codes.append(StyleCode.dim)
        }
        if style.isItalic == true {
            codes.append(StyleCode.italic)
        }
        if style.isUnderlined == true {
            codes.append(StyleCode.underline)
        }
        if style.isBlink {
            codes.append(StyleCode.blink)
        }
        if style.isInverted {
            codes.append(StyleCode.inverse)
        }
        if style.isStrikethrough == true {
            codes.append(StyleCode.strikethrough)
        }

        // Foreground color
        if let fgColor = style.foregroundColor {
            codes.append(contentsOf: fgColor.foregroundCodes())
        }

        // Background color
        if let bgColor = style.backgroundColor {
            codes.append(contentsOf: bgColor.backgroundCodes())
        }

        return codes
    }
}
