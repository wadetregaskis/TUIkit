//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollAnchorMode.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Anchor mode

/// Which policy a scrollable applies to its persisted anchor when the data
/// changes underneath it — the four modes of `Documentation/Scroll-anchoring.md`
/// §1.1, made explicit rather than implied by which render path happens to run.
///
/// | Mode | Meaning |
/// |---|---|
/// | ``top`` | The view stays at the top, whatever rows are added / removed / moved. |
/// | ``bottom`` | The view stays at the bottom (follow-the-log). |
/// | ``row`` | A designated row keeps its place on screen as rows change around it. |
/// | ``window`` | *No* anchor (the default): the position stays where it is in LINE coordinates unless something explicitly moves it. |
///
/// Until this feature's later slices land there is no public designator for
/// ``row`` — per the spec's guardrail #1 it arrives via its own API, as in
/// SwiftUI, rather than by overloading the `UnitPoint` anchor.
enum ScrollAnchorMode: Equatable {
    case top
    case bottom
    case row
    case window

    /// Whether the persisted anchor should be re-bound to its row's stable key
    /// each frame (holding that ROW in place as ordinals shift around it), or
    /// left on its ordinal (holding the position in LINE coordinates, so an
    /// insert above shifts the content down).
    ///
    /// Only ``window`` declines the re-bind. ``top`` / ``bottom`` keep it
    /// because their edge policy lives in the offset/clamp logic, not here —
    /// this is exactly the one branch the spec's §2 resolution calls for, and
    /// keeping the shipped edge behaviour byte-identical is the point.
    var holdsRowIdentity: Bool { self != .window }

    /// The mode a scrollable runs in given its ``EnvironmentValues/defaultScrollAnchor``.
    ///
    /// `nil` — no anchor asked for — is ``window``, the spec's default. A
    /// `UnitPoint` near the top or bottom edge resolves to that edge's mode;
    /// anything mid-content has no edge meaning and stays ``window``. The
    /// 0.75 threshold matches the bottom-affinity test the scroll view
    /// already applies, so the two cannot drift apart.
    static func resolved(defaultScrollAnchor anchor: UnitPoint?) -> Self {
        guard let y = anchor?.y else { return .window }
        if y >= 0.75 { return .bottom }
        if y <= 0.25 { return .top }
        return .window
    }
}
