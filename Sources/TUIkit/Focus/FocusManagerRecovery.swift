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

    /// A control that focus recovery chose, and the section it is registered in, which
    /// is not the active one when a handoff names a control elsewhere.
    struct RecoveryTarget {
        let element: Focusable
        let sectionID: String
    }

    /// Where focus goes when the element `droppedID` can no longer hold it.
    ///
    /// Its handoff first (`.focusHandoff(_:_:)`, followed along a chain: see
    /// ``handoffTarget(from:)``), then its neighbour in the active section's ring
    /// (``neighbourTarget(after:)``). `nil` when neither gives anything; the caller
    /// then falls back to the section's first focusable. `.defaultFocus` is resolved
    /// by the caller, ahead of whatever this returns.
    func recoveryTarget(after droppedID: String) -> RecoveryTarget? {
        if let handoff = handoffTarget(from: droppedID) { return handoff }
        guard let section = activeSection, let neighbour = neighbourTarget(after: droppedID) else { return nil }
        return RecoveryTarget(element: neighbour, sectionID: section.id)
    }

    /// The neighbour of `droppedID` in the active section's ring: the next
    /// focusable, else the previous — never round the end, which would send a
    /// control at the bottom of a dialog to its top.
    ///
    /// A control still registered this pass (a disabled `Button`) walks from where it
    /// stands. One that has LEFT this pass's ring (removed, `.hidden()`, or a disabled
    /// `.focusable()`, which does not register at all) walks from where it stood in
    /// last frame's ring, carried into this one by ``departedPosition(of:in:)``. Without
    /// that it had nowhere to walk from and went to the section's first focusable, so
    /// the two ways of being disabled sent the keyboard to different places.
    ///
    /// `nil` when the control is in neither ring, or nothing in the section can take
    /// the focus.
    private func neighbourTarget(after droppedID: String) -> Focusable? {
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

// MARK: - Handoffs

extension FocusManager {
    /// Records that the control `focusID` hands its focus to the control bound to
    /// `value` in the `@FocusState` store `store` when it can no longer hold it.
    ///
    /// Called by `FocusRegistration.register` for a control under
    /// `.focusHandoff(_:_:)`, on the render pass only and only where the control
    /// itself registered, so a control that stops registering stops declaring.
    func registerFocusHandoff(from focusID: String, store: String, value: AnyHashable) {
        focusHandoffs[focusID] = FocusHandoff(store: store, value: value, generation: focusRenderGeneration)
    }

    /// Drops the handoffs this pass did not declare.
    ///
    /// Called at the END of the pass, from `pruneFocusRegistry()`, which runs after
    /// `endRenderPass` has recovered the focus. So a control that stopped rendering
    /// this pass is still recovered by the handoff it declared last frame, and
    /// nothing older than that survives.
    func pruneFocusHandoffs() {
        guard !focusHandoffs.isEmpty else { return }
        focusHandoffs = focusHandoffs.filter { $0.value.generation == focusRenderGeneration }
    }

    /// Where the handoffs send the focus of `droppedID`, following the chain.
    ///
    /// Start from the control that lost the focus and take its target. If that
    /// target cannot take the focus (unfocusable, not registered this pass, or
    /// outside a modal active section), take THAT control's own handoff, and so on.
    /// Stop at the first control that can take the focus, or `nil` at a control with
    /// no handoff, a value bound to nothing, or a control already visited — ◀ and ▶
    /// naming each other while both are disabled is a cycle of two, not a hang.
    ///
    /// The owner chose the chain over one hop: a declaration keeps meaning "go
    /// there" when its target is itself disabled, and the cycle check is what makes
    /// that safe. The neighbour rule the caller falls back to is walked from
    /// `droppedID`, never from the end of the chain.
    ///
    /// Never calls `focus(id:)`, so an absent target never becomes a pending intent
    /// that would snatch the focus back when it next renders.
    private func handoffTarget(from droppedID: String) -> RecoveryTarget? {
        var visited: Set<String> = [droppedID]
        var sourceID = droppedID
        while let handoff = standingHandoff(from: sourceID),
            let targetID = focusBindings[handoff.store]?[handoff.value]?.focusID,
            visited.insert(targetID).inserted
        {
            if let target = handoffLanding(targetID) { return target }
            sourceID = targetID
        }
        return nil
    }

    /// The handoff `focusID` stands by during this pass.
    ///
    /// A control registered this pass stands by what it declared this pass, and by
    /// nothing if it stopped declaring: last frame's entry is still on the manager
    /// until the pass is pruned, and must not outlive its withdrawal. A control that
    /// is not registered stands by whatever it declared last, which after pruning can
    /// only be its last rendered frame.
    private func standingHandoff(from focusID: String) -> FocusHandoff? {
        guard let handoff = focusHandoffs[focusID] else { return nil }
        if handoff.generation == focusRenderGeneration { return handoff }
        let isRegistered = sections.contains { $0.focusables.contains { $0.focusID == focusID } }
        return isRegistered ? nil : handoff
    }

    /// `focusID` as a place a handoff may land: registered this pass, focusable, and
    /// not outside the active section while that section is modal.
    ///
    /// The modal rule rarely bites, because the page under a modal renders into a
    /// throwaway manager and is not in this ring at all. It covers the sections this
    /// manager does hold beside a modal one.
    private func handoffLanding(_ focusID: String) -> RecoveryTarget? {
        for section in sections {
            guard let element = section.focusables.first(where: { $0.focusID == focusID }) else { continue }
            let crossesModal = section.id != activeSectionIdentifier && activeSectionIsModal
            return element.canBeFocused && !crossesModal
                ? RecoveryTarget(element: element, sectionID: section.id) : nil
        }
        return nil
    }
}
