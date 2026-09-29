//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerPresentedSection.swift
//
//  How a presented surface keeps its focus section active from frame to frame
//  without taking the focus back from a surface presented on top of it. The
//  transition itself lives in `Focus.swift`, beside the focus state it moves.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Activates a presented surface's focus section — a sheet's, an alert's, a
    /// popover's, an open menu's — which its presenter asks for on EVERY frame
    /// the surface is up.
    ///
    /// `activateSection(id:focusBoundary:)` is a transition, not an assertion:
    /// it remembers the section it leaves, drops the focus, and restores this
    /// section's memory. Asked for every frame, that is harmless only while this
    /// section is already the active one — true of a single presentation, and
    /// false the moment a second surface is presented from INSIDE the first: an
    /// alert confirming a button in a sheet, a sheet or menu opened in a
    /// popover. The outer presenter renders first. It found the inner surface's
    /// section active from the frame before and transitioned back to itself;
    /// its section had not been re-populated yet this pass, so nothing was
    /// restored and the focus went to nil. The inner presenter then transitioned
    /// back again, and its first control re-registered into that empty focus and
    /// took it. Tab inside the inner surface could never leave its first
    /// control, a text field in it was torn down and restarted every frame,
    /// dismissing it left the outer surface on its FIRST control rather than
    /// the one that opened it, and each transition's `onFocusChange` asked for
    /// another frame, so the loop never idled while both were up.
    ///
    /// Not "activate once, on presentation", which is how `NavigationStack`
    /// answers the same defect on a push. A presenter has no reliable "just
    /// presented": one whose binding turned true while an alert on the same view
    /// was up rendered into that alert's throwaway backdrop focus manager, and
    /// must claim the real one on the frame the alert goes. So everything
    /// holding the active section is still overridden, as before — a presented
    /// surface owns the focus — EXCEPT a surface presented on top of this one,
    /// directly or through a chain of surfaces each presented from inside the
    /// last. That surface hands the focus back down itself when it is dismissed
    /// (`deactivateSection(id:)` reverts to exactly the section it was activated
    /// over), so taking it back here is only ever wrong.
    ///
    /// ## Only through presented surfaces
    ///
    /// The chain is `sectionRevertTarget`, walked down from the active section —
    /// but that table records EVERY activation, not only presentations: Tab
    /// cycling between sections and a `NavigationStack` push write it too.
    /// Followed through those, a Tab that wrapped out of a screen pushed inside a
    /// sheet onto a control beside the sheet's presenter left a chain leading
    /// back to the sheet, the sheet stopped reclaiming its section, and the focus
    /// stayed behind the modal for good. So the walk passes only through sections
    /// that were marked modal, which every presenter does every frame, and stops
    /// at the first that was not.
    ///
    /// Marked on the PREVIOUS frame (``previousModalSectionIDs``): the surface on
    /// top renders later in this pass than its presenter, so its mark for this
    /// frame does not exist yet. One that left the tree without being dismissed
    /// is dropped by `endRenderPass` as a vanished active section, and this
    /// presenter reclaims the section on the next frame if that fallback chose
    /// another.
    ///
    /// NOT fixed by this: a non-modal section activated INSIDE a presented
    /// surface — a push, a split view's column click — is still taken back by
    /// the surface's presenter on the next frame.
    func activatePresentedSection(id: String) {
        if var section = activeSectionIdentifier, section != id {
            // Bounded by the table's size rather than by reaching a root: the
            // table is pruned only on dismissal, and nothing stops it holding a
            // cycle of modal sections an unbounded walk would never leave.
            var remaining = sectionRevertTarget.count
            while remaining > 0, previousModalSectionIDs.contains(section),
                let below = sectionRevertTarget[section]
            {
                if below == id { return }
                section = below
                remaining -= 1
            }
        }
        activateSection(id: id)
    }

    /// Posts how to close the surface presented in section `id` — asked by a
    /// presenter every frame it draws the surface, as it marks the section
    /// modal.
    ///
    /// For the frame after one where it was NOT drawn: its presenter went
    /// undrawn — a row a lazy stack or a list left out of its window, when a
    /// document arrived above it — so its section vanished and
    /// ``endRenderPass()`` handed the focus back to the page. The surface has to
    /// close then, as well. Its open state lives with the presenter, which
    /// nothing drew to close it, so it came back when the row did, taking the
    /// keyboard from wherever it had gone.
    func notePresentation(id: String, dismiss: @escaping () -> Void) {
        presentationDismissals[id] = dismiss
    }

    /// Closes the surface presented in section `id` last frame and not drawn
    /// in this one (see ``notePresentation(id:dismiss:)``). Called by
    /// ``endRenderPass()`` for the active section it finds gone.
    func closeUndrawnPresentation(id: String) {
        guard presentationDismissals[id] == nil, let dismiss = previousPresentationDismissals[id] else { return }
        previousPresentationDismissals[id] = nil
        dismiss()
    }
}
