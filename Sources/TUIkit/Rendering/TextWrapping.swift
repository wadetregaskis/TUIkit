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
    /// Splits `text` on explicit line breaks (`\n`, `\r\n`, `\r`) and soft-wraps
    /// each paragraph on word boundaries so every returned line fits `width`
    /// terminal cells. Never empty. A single word longer than `width` is placed on
    /// its own line (the caller truncates it). `width <= 0` returns the paragraphs
    /// unwrapped.
    static func wrap(_ text: String, width: Int) -> [String] {
        let paragraphs = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
        )
        guard width > 0 else {
            return paragraphs.isEmpty ? [""] : paragraphs.map(String.init)
        }
        var lines: [String] = []
        for paragraph in paragraphs {
            lines.append(contentsOf: wrapParagraph(String(paragraph), width: width))
        }
        return lines.isEmpty ? [""] : lines
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
        var lines = wrap(text, width: width)
        if let maxLines, maxLines >= 1, lines.count > maxLines {
            let keptCount = max(0, maxLines - 1)
            var kept = Array(lines.prefix(keptCount))
            let remainder = lines[keptCount...].joined(separator: " ")
            kept.append(
                remainder.truncatedToWidth(
                    width, mode: mode, atWordBoundary: atWordBoundary, forceEllipsis: true))
            lines = kept
        }
        return lines.map { $0.truncatedToWidth(width, mode: mode, atWordBoundary: atWordBoundary) }
    }

    /// Wraps a single paragraph (no embedded line breaks) on word boundaries so
    /// each returned line fits `width` terminal cells. Never empty.
    private static func wrapParagraph(_ text: String, width: Int) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var lines: [String] = []
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
                currentLine = wordStr
                currentLineWidth = wordWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : lines
    }
}
