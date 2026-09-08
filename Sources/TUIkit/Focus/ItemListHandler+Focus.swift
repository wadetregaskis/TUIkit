//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+Focus.swift
//
//  How a `List` or `Table` joins the focus system, and what its holding the
//  focus publishes — the Escape claim on the status bar, and the engagement
//  flag the Bottom follow reads.
//
//  Split from `ItemListHandler.swift` when consolidating the six copies of the
//  registration prologue pushed it past the file-length guideline; the file was
//  already at it, and this is the seam its own MARK had drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension ItemListHandler {
    /// Publishes this frame's Escape claim when the focused multi-selection
    /// list would act on it (exit extend mode / clear a non-empty selection).
    ///
    /// Status-bar items and page `onKeyPress` handlers see keys BEFORE the
    /// focused element, so without a claim a page-level "esc back" would
    /// steal the key and navigate away instead of clearing the selection.
    /// The claim (the same mechanism an open Picker drop-down uses) routes
    /// ESC to the focus chain first for this frame AND relabels the status
    /// bar's escape entry, so what ESC currently does is always visible.
    /// Registers with the focus system and publishes everything the answer
    /// feeds, returning whether this control now holds the focus.
    ///
    /// Four statements whose ORDER is the point — register before asking, ask
    /// before publishing, publish before anything reads it — and which appeared
    /// six times: four in `Table` (its two single-line paths, its multi-line
    /// path and its empty path) and twice in `_ListCore`. Six copies of a
    /// sequence is six chances to leave one statement out, and each twin had
    /// already left out a different one: the Table's empty path was the only
    /// one not setting ``isFocusEngaged``, so an emptied table kept whatever
    /// its last populated frame left, while `_ListCore`'s empty path was the
    /// only one not clearing its bands.
    ///
    /// - Parameters:
    ///   - context: The render context. Render passes only — `publishEscapeClaim`
    ///     says why.
    ///   - focusID: This control's persisted focus identity.
    /// - Returns: Whether the control holds the keyboard focus this frame.
    @discardableResult
    func engageFocus(context: RenderContext, focusID: String) -> Bool {
        FocusRegistration.register(context: context, handler: self, focusID: focusID)
        let hasFocus = FocusRegistration.isFocused(context: context, focusID: focusID)
        publishEscapeClaim(context: context, isFocused: hasFocus)
        // What Return does to the focused row: run the row's action where the
        // list has one, and otherwise settle the selection on it.
        FocusRegistration.publishActivationLabel(
            primaryAction != nil
                ? LocalizationService.shared.string(for: LocalizationKey.StatusBar.open)
                : LocalizationService.shared.string(for: LocalizationKey.StatusBar.select),
            context: context, isFocused: hasFocus)
        // The Bottom follow carries the cursor only for the control that owns it.
        isFocusEngaged = hasFocus
        return hasFocus
    }

    /// When Escape has nothing to do here, no claim is published and page
    /// navigation is completely untouched — the list never blocks it.
    /// Unlike a modal surface's claim, this one does not suppress the
    /// global app-chrome shortcuts (`grabsInput` false): a selection is
    /// ordinary control state, not a transient surface the user must leave.
    ///
    /// Called by the owning view during its render pass, after focus
    /// registration (never on measure passes).
    func publishEscapeClaim(context: RenderContext, isFocused: Bool) {
        guard isFocused, !context.isMeasuring else { return }

        // A row in hand owns Escape — it puts the row back — and has to SAY so:
        // `InputHandler` routes a claimed Escape through the focus system first,
        // and without the claim a page-level "⎋ back" navigates out from under
        // the move instead. (Found by driving the real app; the handler-level
        // tests never see the app's Escape.) It also advertises the mode, which
        // is what makes it discoverable at all.
        // A MOUSE drag claims nothing: Escape keeps meaning what it means on
        // the page, so a row can be picked up here, carried to another subpage,
        // and dropped there. (See ``cancelMouseDragReorder()``.)
        if isKeyboardMove {
            context.environment.statusBar?.escapeLabelOverride =
                LocalizationService.shared.string(for: LocalizationKey.StatusBar.cancelMove)
            context.environment.statusBar?.escapeClaimGrabsInput = false
            return
        }

        guard selectionMode == .multi else { return }
        if isExtendingSelection {
            context.environment.statusBar?.escapeLabelOverride =
                LocalizationService.shared.string(
                    for: LocalizationKey.StatusBar.stopExtendingSelection)
            context.environment.statusBar?.escapeClaimGrabsInput = false
        } else if let selection = multiSelection?.wrappedValue, !selection.isEmpty {
            context.environment.statusBar?.escapeLabelOverride =
                LocalizationService.shared.string(
                    for: LocalizationKey.StatusBar.clearSelection)
            context.environment.statusBar?.escapeClaimGrabsInput = false
        }
    }
}
