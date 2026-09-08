//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+FrameInputs.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Per-frame environment capture

extension ItemListHandler {

    /// Captures into the handler everything a row viewport's EVENTS will need
    /// from the environment, which is nowhere near where they run.
    ///
    /// A wheel tick, an arrow key, a drag motion — all of them arrive long after
    /// the render that created their context, when `EnvironmentValues` is out of
    /// reach. So the render is the only place these can be read, and every row
    /// viewport has to read all of them.
    ///
    /// There are three such viewports and, until this existed, three hand-copied
    /// blocks of about a dozen assignments: `_ListCore.resolvePopulatedHandler`,
    /// `_TableCore.resolveHandler` for single-line rows, and the inline block in
    /// `_TableCore.buildMultiLineContent` for multi-line ones. A capture added to
    /// one and not the others is silently dead on the paths that missed it, and
    /// nothing fails — which is a bug class this project has shipped four times:
    /// `017683fa` found EVERY anchor behaviour missing from Table while its twin
    /// List had them all; `.scrollDisabled` reached only the multi-line Table
    /// path when it shipped; the chaining delay reached three of four viewports;
    /// and a stale `keyboardMoveIsLive` survived a Table's switch between its own
    /// two paths.
    ///
    /// The three values that legitimately differ per viewport are **required
    /// arguments**, not defaults. That is the point of the signature: a new
    /// viewport cannot compile without stating its own answer to each, so the
    /// thing that stops the next omission is the compiler rather than a reviewer
    /// noticing an absence. A plain `applyEnvironment(_:)` would have left
    /// exactly the three that caused the bugs outside the shared call.
    ///
    /// Call it once per pass, AFTER ``dropSlotAddsRow`` is settled: that flag's
    /// readers (``reorderSlotNeedsALine`` through `effectiveReorderFeedback`)
    /// consult ``reorderFeedback``, ``keyboardMoveIsLive`` and
    /// ``canFloatDraggedRow``, and they are meant to see the values from the
    /// frame the slot was opened in.
    ///
    /// `syncReturningRows(with:)` is deliberately NOT here even though all three
    /// sites call it with the same argument: it belongs to the drag block beside
    /// `dropSlotAddsRow`, and folding it in would move it after
    /// `carryReorderTargetThroughAutoScroll()` at every site.
    ///
    /// - Parameters:
    ///   - environment: The render pass's environment.
    ///   - reorderFeedback: How a row move previews itself. The app's choice on
    ///     every path but one: a multi-line Table forces `.live`, because its
    ///     composer draws no drop slot for a `.dimmed` preview to occupy — and
    ///     stating that here is what keeps the two Table paths from disagreeing
    ///     when a table's columns start or stop reporting `lineLimit > 1`.
    ///   - keyboardMoveIsLive: Whether Ctrl-R moves the row itself rather than
    ///     previewing at a slot. `true` only for the multi-line Table, for the
    ///     same reason. Set on every path, never merely left alone: the handler
    ///     persists across frames at one identity, so a table arriving from its
    ///     other path brings the other path's answer with it.
    ///   - rowHeight: A row's height in lines, or `nil` for uniform single-line
    ///     rows, where the scroll arithmetic can count rows instead. Answered
    ///     lazily and per index, so only a viewport's worth is ever asked for.
    ///     Assigned before any clamp, so this frame's clamp uses this frame's
    ///     rows.
    func syncFrameInputs(
        environment: EnvironmentValues,
        reorderFeedback: RowReorderFeedback,
        keyboardMoveIsLive: Bool,
        rowHeight: ((Int) -> Int)?
    ) {
        // Shift+arrow accelerates the focus cursor, at event time.
        shiftStepMultiplier = environment.shiftStepMultiplier
        // The app-customisable key bindings, resolved once here rather than per
        // keystroke (see `RowShortcuts.lookup`).
        shortcuts = environment.rowShortcuts.lookup(commandKey: environment.commandKey)
        // `.cursor` feedback needs a session to float the row above the frame,
        // so whether it can is whether there is one.
        canFloatDraggedRow = environment.dragAndDropSession != nil
        // Held so a cancel can take the floating preview down itself, and so the
        // mid-drag navigators reach the view under the POINTER rather than this
        // one. Weak: the session outlives no frame that does not have one.
        dragSession = environment.dragAndDropSession
        isScrollEnabled = environment.isScrollEnabled
        // The nested-scroll grace period. `.scrollChainingDelay(_:)` documents
        // itself as reaching "List, Table, ScrollView, both axes" — and without
        // being captured here a single-line Table was the one scroller in that
        // list that kept the 500 ms default whatever the app asked for.
        wheelEdgeHold.delayNanos = environment.scrollChainingDelay.clampedNanoseconds
        // Wheel events arrive when the environment is out of reach; line
        // granularity is what steps by lines through tall rows.
        scrollGranularity = environment.scrollGranularity
        // The reveal runs on key events, for the same reason.
        followMargin = environment.scrollFollowMargin
        // §1.1: a USER wheel scroll releases a bound anchor to `.window` at
        // event time, and the anchor hold reads the declared mode.
        anchorPositionBinding = environment.anchorPosition
        (declaredAnchorMode, declaredOpeningAnchorMode) = environment.declaredAnchorModes
        self.reorderFeedback = reorderFeedback
        self.keyboardMoveIsLive = keyboardMoveIsLive
        self.rowHeight = rowHeight
    }
}
