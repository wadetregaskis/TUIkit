//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerRecovery.swift
//
//  Where focus goes when the focused control can no longer hold it, and the one
//  walk of the focus ring that answer shares with Tab. Beside `Focus.swift`, which
//  is at its file-length limit, and needing nothing private to it.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// The first focusable element strictly `direction` of `anchor` in `ring`, wrapping
    /// round once when `wrap` is set — the one walk behind both Tab and recovery, so
    /// "the next control" cannot mean two different things.
    ///
    /// Over the UNFILTERED ring, so an anchor that has itself stopped being focusable
    /// still has a position to walk from.
    static func nearestFocusable(
        in ring: [Focusable], from anchor: Int, _ direction: FocusDirection, wrap: Bool
    ) -> Focusable? {
        guard !ring.isEmpty, ring.indices.contains(anchor) else { return nil }
        let step = direction == .forward ? 1 : -1
        var index = anchor
        for _ in 1..<max(2, ring.count) {
            index += step
            if !ring.indices.contains(index) {
                guard wrap else { return nil }
                index = (index + ring.count) % ring.count
            }
            if index == anchor { return nil }
            if ring[index].canBeFocused { return ring[index] }
        }
        return nil
    }

    /// Where focus goes when the element `droppedID` can no longer hold it: the next
    /// focusable in the active section's ring, else the previous — never round the
    /// end, which would send a control at the bottom of a dialog to its top.
    ///
    /// A control still registered this pass (a disabled `Button`) walks from where it
    /// stands. One that has LEFT this pass's ring (removed, `.hidden()`, or a disabled
    /// `.focusable()`, which does not register at all) walks from where it stood in
    /// last frame's ring, carried into this one by ``departedPosition(of:in:)``. Without
    /// that it had nowhere to walk from and went to the section's first focusable, so
    /// the two ways of being disabled sent the keyboard to different places.
    ///
    /// `nil` when the control is in neither ring, or nothing in the section can take
    /// the focus; the caller then falls back to the section's first focusable.
    func recoveryTarget(after droppedID: String) -> Focusable? {
        guard let ring = activeSection?.focusables else { return nil }
        if let anchor = ring.firstIndex(where: { $0.focusID == droppedID }) {
            return Self.nearestFocusable(in: ring, from: anchor, .forward, wrap: false)
                ?? Self.nearestFocusable(in: ring, from: anchor, .backward, wrap: false)
        }
        // The same rule as the walk above, from a position BETWEEN two elements rather
        // than on one: the first focusable at or after it, else the last one before it.
        guard let position = departedPosition(of: droppedID, in: ring) else { return nil }
        return ring[position...].first(where: \.canBeFocused)
            ?? ring[..<position].last(where: \.canBeFocused)
    }

    /// Where a control that has left `ring` would stand in it: just after the nearest
    /// control that stood BEFORE it in last frame's ring and is still here, or at the
    /// top when none is.
    ///
    /// Anchored on what came before rather than after, so a control that an `if`/`else`
    /// swapped for another (which has a focus id of its own) lands on its replacement:
    /// the replacement sits between the same two neighbours. `nil` when last frame's
    /// ring for the active section did not hold the control either.
    private func departedPosition(of droppedID: String, in ring: [Focusable]) -> Int? {
        guard let lastRing = previousSections.first(where: { $0.id == activeSectionIdentifier })?.focusables,
            let lastAnchor = lastRing.firstIndex(where: { $0.focusID == droppedID })
        else { return nil }
        // One pass over this ring rather than a search per survivor: a windowed list
        // can register a long ring, and this runs on every focus loss in one.
        var positions: [String: Int] = [:]
        for (index, element) in ring.enumerated() where positions[element.focusID] == nil {
            positions[element.focusID] = index
        }
        let survivor = lastRing[..<lastAnchor].reversed().lazy.compactMap { positions[$0.focusID] }.first
        return survivor.map { $0 + 1 } ?? 0
    }
}
