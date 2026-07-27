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
/// The highlight itself is a ``MenuHighlight``, shared with the `Picker`
/// drop-down and the combo box — the walk is the same walk everywhere, and only
/// the edge rule differs (a `Menu` clamps; only the `Picker` wraps). What is
/// particular to a view-composed pop-up lives here: the sink its rows report
/// to, and the reveal target that scrolls a tall menu to its highlight.
///
/// One per presented menu, living on the presenter's persisted state, so the
/// highlight survives the frames between key presses.
@MainActor
final class MenuPopupController {
    /// Collects what the rows report as they render.
    let sink = MenuRowSink()

    /// The highlighted row, and every gesture that moves it.
    let highlight = MenuHighlight.popUpMenu()

    /// The highlighted row's ordinal, or `nil` for "nothing chosen yet".
    var highlightedOrdinal: Int? { highlight.ordinal }

    /// Records that the menu has just been opened.
    ///
    /// - Parameter withSelection: Whether to open with a row already
    ///   highlighted. `false` for a pointer-opened menu (macOS behaviour: the
    ///   pointer has chosen nothing yet, so highlighting a row invites a
    ///   mis-click); `true` when the keyboard opened it, since there is nothing
    ///   else to point with. From the unhighlighted state the first Down takes
    ///   the first row and the first Up the last.
    ///
    /// The first row is the first known selectable ordinal when this menu has
    /// been open before and `0` when it has not — and ordinal 0 is the first
    /// BUTTON either way, since only a Button claims one. A leading `Divider`
    /// costs nothing; a leading `.disabled()` row is caught by
    /// ``MenuHighlight/adopt(selectable:)`` as soon as the frame draws.
    func opened(withSelection: Bool) {
        highlight.move(to: withSelection ? (highlight.selectable.first ?? 0) : nil)
    }

    /// Records that the menu has closed.
    func closed() {
        highlight.move(to: nil)
    }

    /// Takes the ordinals the frame just published.
    func adoptRenderedRows() {
        highlight.adopt(selectable: sink.selectableOrdinals)
    }

    /// The row a scrolling menu should keep on screen, named the way the row's
    /// own hit-test region is.
    var revealTargetID: String? {
        highlight.ordinal.map(menuRowRegionID)
    }

    /// Runs the highlighted row, if there is one.
    func activateHighlighted() -> Bool {
        guard let ordinal = highlight.ordinal else { return false }
        sink.activate(ordinal: ordinal)
        return true
    }
}
