//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuColumn.swift
//
//  The seam between a menu's CONTENT model and its CONTROL model.
//
//  A menu's rows are views — that is what gives `Menu` arbitrary `@ViewBuilder`
//  content, `ButtonRole`, per-row `.disabled()` and key equivalents, and it is
//  not negotiable: `.keyboardShortcut` is an environment modifier claimed during
//  the row's own render, so a static tree walk would silently drop it.
//
//  But a menu's HIGHLIGHT wants to be an index, not a focus id. An index is what
//  gives the `Picker` drop-down its jump keys, its windowed scrolling and its
//  hover-moves-highlight for free, and it is what lets a pop-up stop putting its
//  rows into the page's focus ring — where they never belonged, since a menu
//  grabs the keyboard while it is up.
//
//  This file is how both are true at once: rows still render as views, and each
//  one claims an ORDINAL and reports itself to the column instead of to the
//  focus manager.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The sink

/// Collects what a pop-up menu's rows report about themselves as they render.
///
/// One per presented menu, rebuilt each frame. `_ButtonCore` claims an ordinal
/// from it and publishes its action, its enabled state and its resolved
/// shortcut; the menu's controller then reads back which ordinals exist (so the
/// arrows have somewhere to go) and what to run when one is chosen.
///
/// Claims are keyed by ``ViewIdentity`` and first-wins, because one child can
/// contain two Buttons: the first takes the row, and the second falls back to
/// ordinary focus-ring behaviour rather than silently stealing it. Only a render
/// pass claims — see `_ButtonCore`.
@MainActor
final class MenuRowSink {
    /// What one row told the column about itself.
    struct Row {
        let action: () -> Void
        let isEnabled: Bool
    }

    private var claims: [ViewIdentity: Int] = [:]
    private var rows: [Int: Row] = [:]

    /// This row's ordinal — the same one on every pass of the same frame.
    func claimOrdinal(for identity: ViewIdentity) -> Int {
        if let existing = claims[identity] { return existing }
        let ordinal = claims.count
        claims[identity] = ordinal
        return ordinal
    }

    /// Records what the row at `ordinal` does.
    func publish(ordinal: Int, action: @escaping () -> Void, isEnabled: Bool) {
        rows[ordinal] = Row(action: action, isEnabled: isEnabled)
    }

    /// The ordinals a highlight may rest on, in visual order: rows that
    /// published and are enabled. A `Divider` never publishes; a `.disabled()`
    /// row publishes but declines, exactly as it declines focus on the page.
    var selectableOrdinals: [Int] {
        rows.filter { $0.value.isEnabled }.keys.sorted()
    }

    /// Runs the row at `ordinal`, if it is one that can be chosen.
    func activate(ordinal: Int) {
        guard let row = rows[ordinal], row.isEnabled else { return }
        row.action()
    }

    /// Drops the previous frame's claims. Called once per `renderMenuColumn`, so
    /// the ordinals restart at zero and stay dense frame to frame.
    func beginPass() {
        claims.removeAll(keepingCapacity: true)
        rows.removeAll(keepingCapacity: true)
    }
}

/// The hit-test identity of a pop-up menu's row.
///
/// A menu row is not a focus stop, so this is not a focus id — but the reveal
/// machinery finds a control by matching a region's `focusID`, and windowing a
/// tall menu to its highlighted row is exactly a reveal. Derived from the
/// ordinal alone so the column can name the row it wants revealed BEFORE the
/// rows have drawn.
func menuRowRegionID(_ ordinal: Int) -> String {
    "menu-row-\(ordinal)"
}

// MARK: - Environment

private struct MenuRowSinkKey: EnvironmentKey {
    static let defaultValue: MenuRowSink? = nil
}

private struct MenuHighlightedOrdinalKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The open pop-up menu a row is rendering into, or `nil` on the page.
    ///
    /// Non-nil is what puts a `Button` into menu-row mode: it claims an ordinal
    /// here instead of registering with the focus manager. Deliberately absent
    /// for an inline `Menu`, whose rows ARE page focus stops — see
    /// `Documentation/Unifying the menu implementations.md`.
    var menuRowSink: MenuRowSink? {
        get { self[MenuRowSinkKey.self] }
        set { self[MenuRowSinkKey.self] = newValue }
    }

    /// Which ordinal the open menu is highlighting this frame.
    var menuHighlightedOrdinal: Int? {
        get { self[MenuHighlightedOrdinalKey.self] }
        set { self[MenuHighlightedOrdinalKey.self] = newValue }
    }
}

// MARK: - The controller

/// The open pop-up menu's own state: which row is highlighted, and which rows
/// there are to highlight.
///
/// This is the half of the merge that the `Picker` drop-down has always had —
/// the highlight is an index, so every gesture that moves an index (the arrows,
/// Home/End, Page, Shift-accelerated steps) is one shared implementation rather
/// than something each menu re-derives from the focus ring.
///
/// One per presented menu, living on the presenter's persisted state, so the
/// highlight survives the frames between key presses.
@MainActor
final class MenuPopupController {
    /// Collects what the rows report as they render.
    let sink = MenuRowSink()

    /// The highlighted row, or `nil` for "nothing chosen yet" — which is how a
    /// POINTER-opened menu opens, since the pointer has not chosen anything and
    /// a pre-selected row invites a mis-click.
    var highlightedOrdinal: Int?

    /// The rows the last render offered, in visual order. Read back from the
    /// sink after each render, exactly as a `List` republishes its row bands:
    /// the highlight has to persist across frames, but what it may rest ON is
    /// only known once the rows have drawn.
    private(set) var selectableOrdinals: [Int] = []

    /// Records that the menu has just been opened.
    ///
    /// - Parameter withSelection: Whether to open with a row already
    ///   highlighted. `false` for a pointer-opened menu (macOS behaviour: the
    ///   pointer has chosen nothing yet, so highlighting a row invites a
    ///   mis-click); `true` when the keyboard opened it, since there is nothing
    ///   else to point with. From the unhighlighted state the first Down takes
    ///   the first row and the first Up the last.
    ///
    /// The first row is `selectableOrdinals.first` when this menu has been open
    /// before and `0` when it has not — and ordinal 0 is the first BUTTON
    /// either way, since only a Button claims one. A leading `Divider` costs
    /// nothing; a leading `.disabled()` row is caught by ``adoptRenderedRows()``
    /// as soon as the frame draws.
    func opened(withSelection: Bool) {
        highlightedOrdinal = withSelection ? (selectableOrdinals.first ?? 0) : nil
    }

    /// Records that the menu has closed.
    func closed() {
        highlightedOrdinal = nil
    }

    /// Takes the ordinals the frame just published, and moves a highlight whose
    /// row is gone — a menu whose content changed under it, or one that opened
    /// on a row that turned out to be disabled — down to the nearest survivor.
    func adoptRenderedRows() {
        selectableOrdinals = sink.selectableOrdinals
        guard let current = highlightedOrdinal, !selectableOrdinals.contains(current) else {
            return
        }
        highlightedOrdinal = selectableOrdinals.first { $0 > current } ?? selectableOrdinals.last
    }

    /// Moves the highlight for `event`, or reports that the key was not one of
    /// ours. Clamps at both ends: a `Menu` never wraps (only a `Picker` does),
    /// and from nothing the first Down takes the first row and the first Up the
    /// last — the ring is entered at either end and then held.
    func handle(_ event: KeyEvent, multiplier: Int, pageSize: Int) -> Bool {
        guard !selectableOrdinals.isEmpty else { return false }

        // Left/Right would otherwise act as Up/Down on the focus ring, which in
        // a vertical menu is simply wrong; the drop-down has always eaten them.
        if event.key == .left || event.key == .right { return true }

        guard let current = highlightedOrdinal.flatMap(selectableOrdinals.firstIndex(of:)) else {
            switch event.key {
            case .down: highlightedOrdinal = selectableOrdinals.first
            case .up, .end: highlightedOrdinal = selectableOrdinals.last
            case .home, .pageDown: highlightedOrdinal = selectableOrdinals.first
            case .pageUp: highlightedOrdinal = selectableOrdinals.last
            default: return false
            }
            return true
        }

        if let destination = OptionListNavigation.clampedDestination(
            for: event, from: current, count: selectableOrdinals.count,
            onAxisForward: .down, onAxisBackward: .up,
            multiplier: multiplier, pageSize: pageSize)
        {
            highlightedOrdinal = selectableOrdinals[destination]
            return true
        }
        guard !event.shift else { return false }
        switch event.key {
        case .down: highlightedOrdinal = selectableOrdinals[min(current + 1, selectableOrdinals.count - 1)]
        case .up: highlightedOrdinal = selectableOrdinals[max(current - 1, 0)]
        default: return false
        }
        return true
    }

    /// The row a scrolling menu should keep on screen, named the way the row's
    /// own hit-test region is.
    var revealTargetID: String? {
        highlightedOrdinal.map(menuRowRegionID)
    }

    /// Runs the highlighted row, if there is one.
    func activateHighlighted() -> Bool {
        guard let ordinal = highlightedOrdinal else { return false }
        sink.activate(ordinal: ordinal)
        return true
    }
}
