//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuHighlight.swift
//
//  Which row of an open menu is highlighted, and every gesture that moves it.
//
//  TUIkit has four surfaces that put a column of choices on screen and let the
//  keyboard walk it: a pop-up `Menu`, a `.contextMenu`, a `Picker`'s drop-down
//  and a text field's suggestions menu. They differ in what they are made of —
//  two are columns of real `Button` views, two are pre-rendered strings — but
//  the walk itself is the same walk, and it was written out three times.
//
//  Three copies means three chances to disagree, and they did: the jump keys
//  reached one of them years before the others, and each edge rule was decided
//  where it was implemented rather than on purpose. So the walk lives here, and
//  the two places the surfaces genuinely SHOULD differ — what an arrow does at
//  the end of the list, and which keys may enter the list from nothing — are
//  configuration rather than code.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The highlighted row of an open menu, and the keyboard gestures that move it.
///
/// The highlight is an ORDINAL — the index of a choosable row among the
/// choosable rows — not a focus id and not a screen position. Dividers and
/// disabled rows are not things you can pick, so they are not things you can be
/// on; ``adopt(selectable:)`` is how a menu says which ordinals exist this
/// frame.
///
/// Deliberately NOT actor-isolated: it sits beside `ScrollAxis` on a
/// `Focusable` handler, which the focus system owns and which is not isolated
/// either. Every path that touches it is already on the main actor.
final class MenuHighlight {
    /// What a plain Up or Down does at the end of the list.
    enum Edge {
        /// Stop there. A pop-up `Menu`, a `.contextMenu` and a combo box's
        /// suggestions all clamp: each of them has somewhere else the keyboard
        /// can be (the page behind, the field above), so a wrap would read as a
        /// jump rather than as a wrap.
        case clamp

        /// Come round the other side. Only a `Picker`'s drop-down, whose list
        /// is the entire interaction while it is up — nothing else is reachable
        /// to be jumped away from.
        case wrap
    }

    /// Which keys may take the highlight from "nothing" into the list.
    enum Entry {
        /// Any of them. A jump key names an end, so it goes to that end — which
        /// is what makes Home and End work in a menu the pointer opened, where
        /// nothing is highlighted to jump *from*.
        case anyKey

        /// Only a plain Up or Down. The combo box's caret is still in the FIELD
        /// while nothing is highlighted, so Home/End must move the caret and
        /// Shift+arrow must extend the selection; only an arrow means "into the
        /// menu".
        case arrowsOnly
    }

    /// What an arrow does at the ends.
    let edge: Edge

    /// Which keys enter the list from nothing.
    let entry: Entry

    /// The highlighted ordinal, or `nil` for none.
    ///
    /// `nil` is a real state, not an absence of one: it is how a pointer-opened
    /// menu looks (the pointer has chosen nothing yet, and a pre-selected row
    /// invites a mis-click) and how a combo box looks while the caret is still
    /// in the field.
    private(set) var ordinal: Int?

    /// The ordinals that can be highlighted, in display order.
    private(set) var selectable: [Int] = []

    /// Whether the next render should scroll the list to keep the highlight
    /// visible. Set by every move the keyboard makes and cleared by the render
    /// that acts on it, so wheel and scrollbar movement — which move the window
    /// without moving the highlight — leave the window where the user put it,
    /// as a desktop drop-down does.
    private(set) var followPending = false

    private init(edge: Edge, entry: Entry) {
        self.edge = edge
        self.entry = entry
    }

    // MARK: - The configurations that ship

    /// How a pop-up ``Menu`` and a `.contextMenu` walk.
    ///
    /// Clamped, because the page is still there behind the menu and wrapping
    /// off one end into the other would read as a jump; and any key may enter
    /// from nothing, which is what makes Home and End work in a menu the
    /// pointer opened, where there is no highlight to jump *from*.
    static func popUpMenu() -> MenuHighlight {
        MenuHighlight(edge: .clamp, entry: .anyKey)
    }

    /// How a ``Picker``'s drop-down walks.
    ///
    /// The one place a wrap is right: the list is the entire interaction while
    /// it is up, so there is nothing else the keyboard could be jumped away to.
    static func pickerDropDown() -> MenuHighlight {
        MenuHighlight(edge: .wrap, entry: .anyKey)
    }

    /// How a text field's suggestions menu — the combo box — walks.
    ///
    /// Clamped, because the field sits above the first row. Arrows-only,
    /// because with nothing highlighted the keyboard is still AT the caret:
    /// Home/End must move the caret and Shift+arrow must extend the selection.
    static func suggestions() -> MenuHighlight {
        MenuHighlight(edge: .clamp, entry: .arrowsOnly)
    }

    // MARK: - What there is to highlight

    /// Declares the ordinals a highlight may rest on this frame, and moves a
    /// highlight whose row is gone down to the nearest survivor.
    func adopt(selectable: [Int]) {
        self.selectable = selectable
        guard let current = ordinal, !selectable.contains(current) else { return }
        ordinal = selectable.first { $0 > current } ?? selectable.last
    }

    /// Declares a dense list of `count` choosable rows — a `Picker`'s options or
    /// a field's completions, where every row can be picked.
    func adopt(count: Int) {
        adopt(selectable: Array(0..<max(0, count)))
    }

    // MARK: - Moving it

    /// Puts the highlight on `ordinal` (or nowhere), and asks the next render to
    /// scroll it into view.
    func move(to ordinal: Int?) {
        self.ordinal = ordinal
        followPending = ordinal != nil
    }

    /// Puts the highlight on `ordinal` WITHOUT asking for a scroll — for the
    /// pointer, which is already looking at the row it is over.
    func point(at ordinal: Int?) {
        self.ordinal = ordinal
    }

    /// Reads and clears ``followPending``.
    func consumeFollowPending() -> Bool {
        defer { followPending = false }
        return followPending
    }

    // MARK: - The walk

    /// Moves the highlight for `event`, or reports that the key was not one of
    /// ours and should go wherever it would have gone.
    ///
    /// - Parameters:
    ///   - event: The key.
    ///   - multiplier: How far a Shift-accelerated arrow jumps
    ///     (``View/shiftStepMultiplier(_:)``).
    ///   - pageSize: How far a Page key jumps — a visible page of the list.
    /// - Returns: Whether the highlight moved (or the key was one the menu
    ///   swallows regardless).
    func handle(_ event: KeyEvent, multiplier: Int, pageSize: Int) -> Bool {
        guard !selectable.isEmpty else { return false }

        guard let position = ordinal.flatMap(selectable.firstIndex(of:)) else {
            return enterFromNothing(event)
        }

        // Home / End / PageUp / PageDown / Shift+arrow, through the same helper
        // a `List`, a `Table` and a `RadioButtonGroup` answer them with — so
        // every list-like control in TUIkit moves the same distance for the same
        // keystroke. Always clamped, even where a plain arrow wraps: a jump key
        // names an end, and an end that overshot into the far end would be
        // indistinguishable from a mis-press.
        if let destination = OptionListNavigation.clampedDestination(
            for: event, from: position, count: selectable.count,
            onAxisForward: .down, onAxisBackward: .up,
            multiplier: multiplier, pageSize: pageSize)
        {
            move(to: selectable[destination])
            return true
        }
        // Anything else shifted is not menu interaction (Shift+Enter in a combo
        // box is the field's, for one) — the plain-arrow step below must not
        // see it.
        guard !event.shift else { return false }

        switch event.key {
        case .down:
            move(to: step(from: position, by: 1))
            return true
        case .up:
            move(to: step(from: position, by: -1))
            return true
        default:
            return false
        }
    }

    /// One plain arrow's worth of movement, honouring ``edge`` at the ends.
    private func step(from position: Int, by delta: Int) -> Int {
        let next = position + delta
        switch edge {
        case .clamp:
            return selectable[min(max(0, next), selectable.count - 1)]
        case .wrap:
            return selectable[(next + selectable.count) % selectable.count]
        }
    }

    /// Takes the highlight into the list from nothing.
    ///
    /// Down enters at the top and Up at the bottom — the list is entered from
    /// whichever end you came at it from, which is the same rule at both ends
    /// and is what NSComboBox and every pop-up menu do.
    private func enterFromNothing(_ event: KeyEvent) -> Bool {
        if entry == .arrowsOnly {
            guard !event.shift, event.key == .down || event.key == .up else { return false }
        }
        switch event.key {
        case .down, .home, .pageDown:
            move(to: selectable.first)
        case .up, .end, .pageUp:
            move(to: selectable.last)
        default:
            return false
        }
        return true
    }
}
