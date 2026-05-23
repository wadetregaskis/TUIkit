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
    ///   - forceEllipsis: When `true`, append an ellipsis even if the
    ///     string already fits — used to signal that content continues
    ///     past a hard boundary (e.g. a row clipped by its container).
    /// - Returns: A string no wider than `max(0, width)` cells.
    func truncatedToWidth(
        _ width: Int,
        mode: TruncationMode = .tail,
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
            return ansiAwarePrefix(visibleCount: keep) + ellipsis
        case .head:
            return ellipsis + ansiAwareSuffix(droppingVisible: max(0, visible - keep))
        case .middle:
            let leftKeep = keep / 2
            let rightKeep = keep - leftKeep
            return ansiAwarePrefix(visibleCount: leftKeep)
                + ellipsis
                + ansiAwareSuffix(droppingVisible: max(0, visible - rightKeep))
        }
    }
}
