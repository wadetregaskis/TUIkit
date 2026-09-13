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
    func recoveryTarget(after droppedID: String) -> Focusable? {
        guard let ring = activeSection?.focusables,
            let anchor = ring.firstIndex(where: { $0.focusID == droppedID })
        else { return nil }
        return Self.nearestFocusable(in: ring, from: anchor, .forward, wrap: false)
            ?? Self.nearestFocusable(in: ring, from: anchor, .backward, wrap: false)
    }
}
