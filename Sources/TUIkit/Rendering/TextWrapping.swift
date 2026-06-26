//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextWrapping.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Pure text-layout helpers shared by ``Text`` and any view that lays plain text
/// into a bounded region — notably a multi-line ``Table`` cell.
///
/// This is the one place that decides how textual content "expands to fit" while
/// staying inside finite bounds, so every view that shows text behaves the same
/// way: an explicit line break starts a new line; a long line soft-wraps on word
/// boundaries; and a line budget keeps the lines that fit, folding the remainder
/// into the last visible line truncated with an ellipsis so the loss is shown
/// rather than silently dropped.
enum TextWrapping {
    /// Wrapped text paired with each line's visible width in terminal cells.
    ///
    /// Word-wrapping already knows each line's width as it builds it, so the
    /// `…Measured` entry points surface it here for free rather than forcing
    /// every downstream consumer (``Text``'s ``FrameBuffer`` construction, a
    /// `VStack` aligning a wrapped column) to re-`strippedLength` the lines every
    /// frame. The widths describe the *plain* `lines`; styling them with ANSI
    /// codes (zero visible cells) leaves the widths unchanged.
    ///
    /// - Invariant: `widths.count == lines.count` and, for every index,
    ///   `widths[i] == lines[i].strippedLength`.
    struct Wrapped {
        /// The wrapped (and possibly truncated/folded) lines.
        let lines: [String]
        /// Each line's visible width in terminal cells.
        let widths: [Int]
    }

    /// Splits `text` on explicit line breaks (`\n`, `\r\n`, `\r`) and soft-wraps
    /// each paragraph on word boundaries so every returned line fits `width`
    /// terminal cells. Never empty. A single word longer than `width` is placed on
    /// its own line (the caller truncates it). `width <= 0` returns the paragraphs
    /// unwrapped.
    static func wrap(_ text: String, width: Int) -> [String] {
        wrapMeasured(text, width: width).lines
    }

    /// Like ``wrap(_:width:)`` but also returns each line's visible width.
    ///
    /// The widths are accumulated while wrapping (each line's width is known the
    /// moment the line is finished), so this costs nothing beyond ``wrap`` — the
    /// per-line `strippedLength` the width already needs. For the `width <= 0`
    /// passthrough the widths are measured once from the (unwrapped) paragraphs.
    static func wrapMeasured(_ text: String, width: Int) -> Wrapped {
        let paragraphs = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
        )
        guard width > 0 else {
            let lines = paragraphs.isEmpty ? [""] : paragraphs.map(String.init)
            return Wrapped(lines: lines, widths: lines.map(\.strippedLength))
        }
        var lines: [String] = []
        var widths: [Int] = []
        for paragraph in paragraphs {
            let wrapped = wrapParagraph(String(paragraph), width: width)
            lines.append(contentsOf: wrapped.lines)
            widths.append(contentsOf: wrapped.widths)
        }
        if lines.isEmpty {
            return Wrapped(lines: [""], widths: [0])
        }
        return Wrapped(lines: lines, widths: widths)
    }

    /// Lays `text` into at most `maxLines` lines of at most `width` cells.
    ///
    /// Wraps (see ``wrap(_:width:)``); then, if the result overflows the budget,
    /// keeps the lines that fit and folds the remainder into the last visible line
    /// truncated with an ellipsis; finally truncates any line still wider than
    /// `width` (a single over-long word). `maxLines == nil` keeps every wrapped
    /// line. Returns plain (unstyled) lines.
    static func fit(
        _ text: String,
        width: Int,
        maxLines: Int?,
        mode: TruncationMode = .tail,
        atWordBoundary: Bool = false
    ) -> [String] {
        fitMeasured(
            text, width: width, maxLines: maxLines, mode: mode, atWordBoundary: atWordBoundary
        ).lines
    }

    /// Like ``fit(_:width:maxLines:mode:atWordBoundary:)`` but also returns each
    /// final line's visible width.
    ///
    /// The maxLines fold and the per-line ``Swift/StringProtocol/truncatedToWidth(_:mode:atWordBoundary:forceEllipsis:)``
    /// pass rewrite line content, so the widths are recomputed from the *final*
    /// lines — a truncated or folded line's width is its post-truncation visible
    /// width (always `<= width`). When neither transform fires (the common case:
    /// the wrapped lines already fit and there's no line-limit overflow) the
    /// returned lines are identical to ``wrapMeasured``'s and reuse its widths
    /// directly, so no re-measure happens at all.
    static func fitMeasured(
        _ text: String,
        width: Int,
        maxLines: Int?,
        mode: TruncationMode = .tail,
        atWordBoundary: Bool = false
    ) -> Wrapped {
        let wrapped = wrapMeasured(text, width: width)
        var lines = wrapped.lines
        var changed = false

        if let maxLines, maxLines >= 1, lines.count > maxLines {
            let keptCount = max(0, maxLines - 1)
            var kept = Array(lines.prefix(keptCount))
            let remainder = lines[keptCount...].joined(separator: " ")
            kept.append(
                remainder.truncatedToWidth(
                    width, mode: mode, atWordBoundary: atWordBoundary, forceEllipsis: true))
            lines = kept
            changed = true
        }

        // Truncate any line still wider than `width` (a single over-long word, or
        // the just-folded last line). `truncatedToWidth` returns its input
        // unchanged when it already fits.
        for index in lines.indices {
            let truncated =
                lines[index].truncatedToWidth(width, mode: mode, atWordBoundary: atWordBoundary)
            if truncated != lines[index] {
                lines[index] = truncated
                changed = true
            }
        }

        // When neither transform rewrote any line, the lines are exactly
        // `wrapMeasured`'s and its widths still describe them — the hot path, with
        // no re-measure. Otherwise recompute the widths from the final lines (a
        // truncated/folded line's width is its post-truncation visible width).
        let widths = changed ? lines.map(\.strippedLength) : wrapped.widths
        return Wrapped(lines: lines, widths: widths)
    }

    /// Wraps a single paragraph (no embedded line breaks) on word boundaries so
    /// each returned line fits `width` terminal cells, returning each line's
    /// visible width alongside (tracked for free while wrapping). Never empty.
    private static func wrapParagraph(_ text: String, width: Int) -> Wrapped {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var lines: [String] = []
        var widths: [Int] = []
        var currentLine = ""
        var currentLineWidth = 0

        for word in words {
            let wordStr = String(word)
            let wordWidth = wordStr.strippedLength
            if currentLine.isEmpty {
                currentLine = wordStr
                currentLineWidth = wordWidth
            } else if currentLineWidth + 1 + wordWidth <= width {
                currentLine += " " + wordStr
                currentLineWidth += 1 + wordWidth
            } else {
                lines.append(currentLine)
                widths.append(currentLineWidth)
                currentLine = wordStr
                currentLineWidth = wordWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
            widths.append(currentLineWidth)
        }

        if lines.isEmpty {
            return Wrapped(lines: [""], widths: [0])
        }
        return Wrapped(lines: lines, widths: widths)
    }
}
