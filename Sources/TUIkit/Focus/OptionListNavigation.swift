//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OptionListNavigation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Option-list jump navigation

/// Shared keyboard-navigation maths for the *flat option lists* that keep a
/// single highlighted/focused index — a ``RadioButtonGroup``, a ``Picker``
/// drop-down, a ``Menu``, a combo-box popup. It centralises the accelerated and
/// jump gestures that all of them should answer the same way:
///
/// | Key | Destination |
/// |-----|-------------|
/// | Home | first option |
/// | End | last option |
/// | PageUp | back one page (`pageSize`) |
/// | PageDown | forward one page (`pageSize`) |
/// | Shift + on-axis arrow | ±`multiplier` options |
///
/// These are all "go far / go to an end" gestures, so they **clamp** into
/// `0..<count` and never wrap — unlike a plain single-step arrow, whose wrap /
/// edge-escape behaviour differs per control and stays with that control. The
/// caller tries this first; a `nil` result means "not one of these keys — handle
/// your plain movement / edges yourself".
///
/// Controls without a scrolling viewport (a radio group) pass `pageSize == count`
/// so Page collapses onto Home/End — the sensible reading of "page" when the
/// whole list is always on screen.
enum OptionListNavigation {
    /// The clamped destination index for a Home/End/Page/Shift-accelerated key
    /// over a `count`-item option list, or `nil` when `event` is none of those.
    ///
    /// - Parameters:
    ///   - event: The key event.
    ///   - index: The current highlighted/focused index.
    ///   - count: The number of options (returns `nil` when `0`).
    ///   - onAxisForward: The arrow that moves toward the *end* along this
    ///     control's axis (`.down` for a vertical list, `.right` for a horizontal
    ///     one). Shift + this is the accelerated forward move.
    ///   - onAxisBackward: The arrow that moves toward the *start* (`.up` /
    ///     `.left`). Shift + this is the accelerated backward move.
    ///   - multiplier: How many options a Shift-accelerated arrow jumps (≥ 1).
    ///   - pageSize: How many options PageUp/PageDown jump (≥ 1). Pass `count`
    ///     for a control with no viewport so Page == Home/End.
    static func clampedDestination(
        for event: KeyEvent,
        from index: Int,
        count: Int,
        onAxisForward: Key,
        onAxisBackward: Key,
        multiplier: Int,
        pageSize: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        func clamp(_ i: Int) -> Int { max(0, min(count - 1, i)) }

        // Shift + an on-axis arrow: an accelerated move (never wraps — it clamps
        // at the end, matching List/Table's Shift-accelerated cursor).
        if event.shift {
            if event.key == onAxisForward { return clamp(index + max(1, multiplier)) }
            if event.key == onAxisBackward { return clamp(index - max(1, multiplier)) }
        }

        switch event.key {
        case .home:
            return 0
        case .end:
            return count - 1
        case .pageUp:
            return clamp(index - max(1, pageSize))
        case .pageDown:
            return clamp(index + max(1, pageSize))
        default:
            return nil
        }
    }
}
