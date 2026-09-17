//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerSubtreeJump.swift
//
//  Moving the focus among the stops of ONE subtree — a menu's own rows — rather
//  than the whole section: where such a jump can land, which stops belong to the
//  subtree, and the move itself.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {

    /// Where a jump within one subtree's own focus stops lands.
    enum SubtreeFocusJump: Equatable {
        /// The subtree's first stop (`Home`).
        case first
        /// Its last (`End`).
        case last
        /// A screenful further on, clamped at the end (`Page Down`).
        case forward(Int)
        /// A screenful back, clamped at the start (`Page Up`).
        case backward(Int)
    }

    /// Whether a focus ID (default form: `"<prefix>-<identity path>"`)
    /// addresses a control at or below the given identity path.
    ///
    /// Path-boundary-safe: the character after the matched path must be a
    /// component boundary (`/` for a child type, `#` for a conditional
    /// branch) or the end of the ID, so `…#7` never matches `…#70` and a
    /// keyed sibling (`…Row[7]`) never matches its unkeyed prefix. Explicit
    /// `.focusID("…")` strings embed no path and never match — routing to
    /// those without rendering is the identity tax the design doc records
    /// (§12): there is nothing to route by.
    static func focusID(_ id: String, addressesSubtreeAt path: String) -> Bool {
        guard !path.isEmpty, let range = id.range(of: path) else { return false }
        if range.upperBound == id.endIndex { return true }
        let next = id[range.upperBound]
        return next == "/" || next == "#"
    }

    /// Moves the focus among the stops of ONE subtree — a menu's own rows —
    /// rather than the whole section.
    ///
    /// A menu is a list, and a list's paging keys move its cursor. The focus
    /// ring's own answer to Page Up/Down and Home/End is to scroll the
    /// enclosing container and deliberately leave the focus where it was
    /// (`dispatchKeyEvent`), which is right for a page of prose with a button
    /// on it and wrong for a column that is nothing but stops: the highlight
    /// scrolled out of sight and the next arrow key snapped the view back to
    /// wherever it had been left.
    ///
    /// Subtree membership is by identity path, so this moves within the menu
    /// that asked and not into whatever else shares its section. Rows given an
    /// explicit `.focusID("…")` embed no path and so cannot be routed to — the
    /// identity tax `focusID(_:addressesSubtreeAt:)` documents.
    ///
    /// - Returns: whether the focus moved.
    @discardableResult
    func moveFocus(inSubtreeAt path: String, jump: SubtreeFocusJump) -> Bool {
        guard let section = activeSection else { return false }
        let stops = section.focusables.filter {
            // The container that HOLDS the rows is a focus stop too when its
            // content overflows, and it is registered last — so "the end" was
            // landing on the scroll view rather than on the last row: no
            // highlight, nothing to activate, and the viewport left where it
            // was. A menu pages among its rows.
            $0.canBeFocused && !($0 is ScrollViewHandler)
                && Self.focusID($0.focusID, addressesSubtreeAt: path)
        }
        guard !stops.isEmpty else { return false }
        // Only while the cursor is actually IN this subtree. The handler that
        // calls this is registered per section, not per control, so a menu
        // sharing a page with other controls would otherwise answer a Page Down
        // aimed at the page itself — moving its own cursor instead of scrolling
        // what the user was looking at.
        guard let current = currentFocusedID.flatMap({ id in stops.firstIndex { $0.focusID == id } })
        else { return false }
        let target: Int
        switch jump {
        case .first: target = 0
        case .last: target = stops.count - 1
        case .forward(let by): target = min(stops.count - 1, current + max(1, by))
        case .backward(let by): target = max(0, current - max(1, by))
        }
        let moved = target != current
        if moved {
            focus(stops[target])
            // The cursor moved on purpose, so the viewport must follow it — the
            // same bump `dispatchKeyEvent` makes when a focused control consumes
            // a key. Without it `End` moved the focus to the last row and left
            // the view showing the first.
            focusedInteractionGeneration &+= 1
        }

        // An end-to-end jump keeps travelling while the rows it is headed for
        // are still being laid out. Reaching the last row LAID OUT is not
        // reaching the last row, and the reveal will not scroll past a cursor
        // that is already visible — so the container is sent to that end too,
        // and the jump resumes in `endRenderPass` against the rows that
        // scrolling reveals. A page jump needs none of this: a screenful is a
        // screenful, and the reveal covers it.
        switch jump {
        case .first, .last:
            // Re-armed only while this pass made progress — the cursor moved,
            // or the container did. Re-arming unconditionally left the latch
            // set forever: every later pass re-ran the jump, so the next Up
            // after an End was undone at the end of its own render and the
            // arrow key read as dead.
            let scrolled = scrollActiveSection(for: jump == .first ? .home : .end)
            let progressed = moved || scrolled
            pendingSubtreeJump = progressed ? (path, jump) : nil
            return progressed
        case .forward, .backward:
            pendingSubtreeJump = nil
            return moved
        }
    }
}
