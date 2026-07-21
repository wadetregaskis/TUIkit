//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollFollowMargin.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ScrollFollowMargin

/// How eagerly a scrolling view follows its selection or focus.
///
/// When the selection (a ``List``/``Table`` cursor, a ``Menu`` or drop-down
/// highlight, or the focused control an enclosing ``ScrollView`` reveals)
/// moves toward a viewport edge, the margin says how much context to keep
/// visible beyond it:
///
/// - ``none``: scrolling starts only when the selection reaches the edge —
///   the classic terminal behaviour, and the default everywhere.
/// - ``lines(_:)`` / ``rows(_:)``: scrolling starts once fewer than that many
///   lines (terminal rows) / rows (logical items — a multi-line row counts
///   once) remain visible beyond the selection. For single-line items the two
///   are identical.
/// - ``fraction(_:)``: the margin is that fraction of the viewport height,
///   so it scales with the window.
/// - ``centered``: keep the selection centred while scrolling — exactly
///   ``fraction(_:)`` of `0.5`.
///
/// Whatever the value, a selection near the very start or end of the content
/// still rests against the edge — the margin only affects when the window
/// starts moving in between. Margins larger than the viewport allows are
/// clamped (a half-viewport margin behaves like ``centered``).
///
/// Set it for a subtree with ``View/scrollFollowMargin(_:)``.
public struct ScrollFollowMargin: Sendable, Hashable {
    enum Value: Sendable, Hashable {
        case lines(Int)
        case rows(Int)
        case fraction(Double)
        case centered(RowAnchor)
    }

    /// Which LINE of a (possibly multi-line) row is the one held at the centre
    /// under ``ScrollFollowMargin/centered(anchor:)``. Single-line rows ignore
    /// this — every choice resolves to the row's only line.
    public enum RowAnchor: Sendable, Hashable {
        /// The row's first line sits at the centre — the row grows downward
        /// from the middle.
        case top
        /// The row's middle line sits at the centre — the row straddles the
        /// midline evenly (the default).
        case center
        /// A specific line index within the row sits at the centre (clamped to
        /// the row's height).
        case line(Int)
    }

    let value: Value

    /// No margin: scrolling starts only when the selection reaches the
    /// viewport edge. The default.
    public static let none = Self(value: .lines(0))

    /// Keep the selection centred while scrolling, holding the row's middle
    /// line at the viewport centre (``RowAnchor/center``).
    public static let centered = Self(value: .centered(.center))

    /// Keep the selection centred while scrolling, holding `anchor`'s line of a
    /// multi-line row at the viewport centre.
    ///
    /// Row-margin centring counts whole rows above and below, so on a list of
    /// variable-height rows the focused row's vertical position drifts as its
    /// neighbours' heights change. This instead centres a specific LINE of the
    /// focused row with sub-row precision, so a tall row sits stably — pick
    /// ``RowAnchor/top`` to pin its first line to the middle, ``RowAnchor/center``
    /// its middle, or ``RowAnchor/line(_:)`` an exact line.
    public static func centered(anchor: RowAnchor) -> Self {
        Self(value: .centered(anchor))
    }

    /// Keep `count` terminal lines visible beyond the selection.
    public static func lines(_ count: Int) -> Self {
        Self(value: .lines(max(0, count)))
    }

    /// Keep `count` rows visible beyond the selection. A multi-line row
    /// counts once; with single-line rows this is the same as ``lines(_:)``.
    public static func rows(_ count: Int) -> Self {
        Self(value: .rows(max(0, count)))
    }

    /// A margin that is `fraction` of the viewport height (clamped to
    /// `0...0.5`; `0.5` keeps the selection centred).
    public static func fraction(_ fraction: Double) -> Self {
        Self(value: .fraction(min(max(fraction, 0), 0.5)))
    }

    /// The margin in terminal lines for a viewport of `viewportLines` lines,
    /// clamped so a selection can always rest strictly inside the window
    /// (at most `(viewportLines - 1) / 2` — a full-half margin pins the
    /// selection to the centre). Line-space consumers (Menu, drop-downs,
    /// ScrollView reveal) use this directly; row-space consumers treat
    /// ``rows(_:)`` natively and convert the rest via their row heights.
    func resolvedLines(viewportLines: Int) -> Int {
        let raw: Int
        switch value {
        case .lines(let count), .rows(let count):
            raw = count
        case .fraction(let fraction):
            raw = Int((Double(viewportLines) * fraction).rounded())
        case .centered:
            // Half the viewport, so line-space consumers (single-line lists,
            // menus, drop-downs, ScrollView reveal) still centre the selection.
            // Row-space consumers with multi-line rows instead use the anchor
            // (see ``centeredAnchor``) for sub-row-precise centring.
            raw = Int((Double(viewportLines) * 0.5).rounded())
        }
        return min(max(0, raw), max(0, (viewportLines - 1) / 2))
    }

    /// The row anchor when this margin is ``centered(anchor:)`` — the signal a
    /// multi-line row list uses to centre with sub-row precision instead of the
    /// whole-row margin approximation. `nil` for every other margin.
    var centeredAnchor: RowAnchor? {
        if case .centered(let anchor) = value { return anchor }
        return nil
    }
}

// MARK: - Environment

private struct ScrollFollowMarginKey: EnvironmentKey {
    static let defaultValue: ScrollFollowMargin = .none
}

extension EnvironmentValues {
    /// How eagerly scrolling views follow their selection — see
    /// ``ScrollFollowMargin``. Defaults to ``ScrollFollowMargin/none``.
    public var scrollFollowMargin: ScrollFollowMargin {
        get { self[ScrollFollowMarginKey.self] }
        set { self[ScrollFollowMarginKey.self] = newValue }
    }
}

extension View {
    /// Sets how eagerly scrolling views in this subtree follow their
    /// selection or focus — see ``ScrollFollowMargin``.
    ///
    /// ```swift
    /// List(items, selection: $selection) { Text($0.name) }
    ///     .scrollFollowMargin(.lines(2))   // scroll 2 lines early
    ///
    /// Menu(items: entries, selection: $choice)
    ///     .scrollFollowMargin(.centered)   // keep the selection centred
    /// ```
    public func scrollFollowMargin(_ margin: ScrollFollowMargin) -> some View {
        environment(\.scrollFollowMargin, margin)
    }
}
