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
    /// **Only ``row`` re-binds** — it is the one *identity* policy. ``top`` and
    /// ``bottom`` are **positional** (see ``ScrollAnchor``'s doc comment: they
    /// name an edge, not a row), so their policy lives entirely in the
    /// offset/clamp logic and they must leave the ordinal alone. Re-binding
    /// under ``top`` was a spec violation with teeth: on the anchored walk a
    /// prepend held the row that happened to be at the top instead of staying
    /// at the top, i.e. Top silently behaved as Row — the very confusion §1.1
    /// separates the modes to avoid.
    var holdsRowIdentity: Bool { self == .row }

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

    /// The mode actually in effect: a **non-nil** bound
    /// ``TUIkit/View/anchorPosition(_:)`` overrides the declared
    /// `defaultScrollAnchor`; `nil` means "no departure from the declaration"
    /// and falls back to it.
    ///
    /// This is what makes writing `nil` restore the declared anchor — the
    /// declaration is re-asserted by the view tree every render, so it is
    /// always recoverable and the framework keeps no hidden shadow state. It is
    /// also why `.window` and `nil` must stay distinct: `.window` is an
    /// explicit release (the user scrolled away), `nil` is "never left".
    static func effective(
        boundAnchor: ErasedScrollAnchor?, defaultScrollAnchor anchor: UnitPoint?
    ) -> Self {
        effective(boundAnchor: boundAnchor, declared: resolved(defaultScrollAnchor: anchor))
    }

    /// The same precedence, for callers that already hold the *resolved*
    /// declaration rather than the raw `UnitPoint` — the scroll handlers, which
    /// capture `declaredAnchorMode` at render so event-time code can read it.
    static func effective(boundAnchor: ErasedScrollAnchor?, declared: Self) -> Self {
        switch boundAnchor {
        case .none: return declared
        case .top: return .top
        case .bottom: return .bottom
        case .row: return .row
        case .window: return .window
        }
    }
}
