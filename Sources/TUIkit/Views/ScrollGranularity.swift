//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollGranularity.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ScrollGranularity

/// How finely a ``List`` or ``Table`` scrolls when its rows span multiple
/// lines. (TUI-specific: SwiftUI scrolls by pixels, so the question doesn't
/// arise there.)
///
/// - ``line``: the viewport moves one terminal *line* at a time — a tall row
///   scrolls into view gradually, and can be partially clipped at the top of
///   the viewport, exactly like a GUI list mid-scroll. The default.
/// - ``row``: the viewport moves one whole *row* at a time — the top visible
///   row is always fully shown (the classic TUI behaviour).
///
/// Selection and the keyboard focus cursor are row-based in both modes; the
/// granularity affects only how the viewport moves (wheel, scrollbar arrows)
/// and where it may rest. With single-line rows the two are identical.
public enum ScrollGranularity: Sendable, Equatable {
    /// Scroll by terminal lines; a tall top row may be partially clipped.
    case line

    /// Scroll by whole rows; the top row is always fully visible.
    case row
}

// MARK: - Environment

private struct ScrollGranularityKey: EnvironmentKey {
    static let defaultValue: ScrollGranularity = .line
}

extension EnvironmentValues {
    /// The scroll granularity for ``List`` / ``Table`` content —
    /// see ``ScrollGranularity``. Defaults to ``ScrollGranularity/line``.
    public var scrollGranularity: ScrollGranularity {
        get { self[ScrollGranularityKey.self] }
        set { self[ScrollGranularityKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// Sets how finely ``List`` and ``Table`` content in this subtree scrolls
    /// when rows span multiple lines — by terminal ``ScrollGranularity/line``
    /// (the default: tall rows scroll into view gradually and may be
    /// partially clipped at the top edge) or by whole
    /// ``ScrollGranularity/row`` (the classic TUI behaviour: the top row is
    /// always fully visible).
    public func scrollGranularity(_ granularity: ScrollGranularity) -> some View {
        environment(\.scrollGranularity, granularity)
    }
}
