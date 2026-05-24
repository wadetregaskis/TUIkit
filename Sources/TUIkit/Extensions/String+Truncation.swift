//  🖥️ TUIKit — Terminal UI Kit for Swift
//  String+Truncation.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Truncation Mode

/// How text is shortened when it cannot fit the space available to it.
///
/// Mirrors SwiftUI's `Text.TruncationMode`. The truncation point is always
/// marked with a single-cell ellipsis (`…`) so a shortened string is
/// visibly distinct from one that simply ends where it does.
public enum TruncationMode: Sendable, Equatable {
    /// Keep the start of the string; drop the end: `"Documentat…"`.
    case tail

    /// Keep the end of the string; drop the start: `"…mentation"`.
    case head

    /// Keep both ends; drop the middle: `"Docu…tion"`.
    case middle
}

// MARK: - Ellipsis Truncation

extension String {
    /// The single-cell character used to mark a truncation point.
    static let truncationEllipsis = "…"

    /// Returns this string shortened to at most `width` terminal cells,
    /// marking the truncation point with an ellipsis.
    ///
    /// Terminal-cell aware: wide characters (CJK, emoji) count as 2 cells
    /// and are never split across the boundary. ANSI escape codes within
    /// the kept region are preserved.
    ///
    /// - Parameters:
    ///   - width: The maximum width in terminal cells. Values below 1
    ///     yield an empty string.
    ///   - mode: Which part of the string to keep (default: `.tail`).
    ///   - atWordBoundary: When `true`, the cut is pulled back to the
    ///     nearest word boundary so a partial word is never left dangling.
    ///     A single word longer than the available width still has to be
    ///     cut mid-word — there is no boundary to honour. Has no effect on
    ///     `.middle`. Defaults to `false` (cut at any position).
    ///   - forceEllipsis: When `true`, append an ellipsis even if the
    ///     string already fits — used to signal that content continues
    ///     past a hard boundary (e.g. a row clipped by its container).
    /// - Returns: A string no wider than `max(0, width)` cells.
    func truncatedToWidth(
        _ width: Int,
        mode: TruncationMode = .tail,
        atWordBoundary: Bool = false,
        forceEllipsis: Bool = false
    ) -> String {
        let visible = strippedLength
        if visible <= width && !forceEllipsis { return self }
        guard width >= 1 else { return "" }

        let ellipsis = String.truncationEllipsis

        // Already fits, but a continuation marker is required: append the
        // ellipsis if there is a spare cell, otherwise fall through and
        // give up one cell of content to make room for it.
        if visible < width && forceEllipsis { return self + ellipsis }
        if width == 1 { return ellipsis }

        let keep = width - 1
        switch mode {
        case .tail:
            let prefix = ansiAwarePrefix(visibleCount: keep)
            if atWordBoundary, let trimmed = Self.keepingLeadingWords(of: prefix) {
                return trimmed + ellipsis
            }
            // Drop a trailing space so the ellipsis never dangles after a gap.
            return Self.droppingTrailingSpaces(prefix) + ellipsis
        case .head:
            let suffix = ansiAwareSuffix(droppingVisible: max(0, visible - keep))
            if atWordBoundary, let trimmed = Self.keepingTrailingWords(of: suffix) {
                return ellipsis + trimmed
            }
            return ellipsis + Self.droppingLeadingSpaces(suffix)
        case .middle:
            // A word-boundary cut in the middle is ill-defined; `.middle`
            // always cuts by character.
            let leftKeep = keep / 2
            let rightKeep = keep - leftKeep
            return ansiAwarePrefix(visibleCount: leftKeep)
                + ellipsis
                + ansiAwareSuffix(droppingVisible: max(0, visible - rightKeep))
        }
    }

    /// Drops a trailing partial word from a tail-truncation prefix.
    ///
    /// Returns the prefix cut back to (and excluding) the final space, with
    /// trailing spaces removed — or `nil` when there is no space to cut at
    /// (a single over-long word), so the caller falls back to a mid-word cut.
    private static func keepingLeadingWords(of prefix: String) -> String? {
        guard let lastSpace = prefix.lastIndex(of: " ") else { return nil }
        var end = lastSpace
        while end > prefix.startIndex {
            let previous = prefix.index(before: end)
            guard prefix[previous] == " " else { break }
            end = previous
        }
        let result = String(prefix[prefix.startIndex..<end])
        return result.isEmpty ? nil : result
    }

    /// Drops a leading partial word from a head-truncation suffix.
    ///
    /// Returns the suffix advanced past the first space — or `nil` when
    /// there is no space to cut at, so the caller falls back to a mid-word
    /// cut.
    private static func keepingTrailingWords(of suffix: String) -> String? {
        guard let firstSpace = suffix.firstIndex(of: " ") else { return nil }
        var start = suffix.index(after: firstSpace)
        while start < suffix.endIndex, suffix[start] == " " {
            start = suffix.index(after: start)
        }
        let result = String(suffix[start..<suffix.endIndex])
        return result.isEmpty ? nil : result
    }

    /// Returns `s` with any trailing spaces removed.
    private static func droppingTrailingSpaces(_ s: String) -> String {
        var end = s.endIndex
        while end > s.startIndex {
            let previous = s.index(before: end)
            guard s[previous] == " " else { break }
            end = previous
        }
        return String(s[s.startIndex..<end])
    }

    /// Returns `s` with any leading spaces removed.
    private static func droppingLeadingSpaces(_ s: String) -> String {
        var start = s.startIndex
        while start < s.endIndex, s[start] == " " {
            start = s.index(after: start)
        }
        return String(s[start..<s.endIndex])
    }
}
