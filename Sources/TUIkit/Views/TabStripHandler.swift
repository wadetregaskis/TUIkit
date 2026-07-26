//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabStripHandler.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Focus handler

/// Switches the active tab with the arrow keys when the strip is focused:
/// left/right step through the tabs in order; up/down move between rows of a
/// wrapped strip, to the tab nearest above/below the current one's centre.
final class TabStripHandler: Focusable {
    let focusID: String
    var canBeFocused: Bool
    var selection: Binding<AnyHashable>
    var values: [AnyHashable]

    /// The visual rows (tab indices, top-to-bottom) and each tab's horizontal
    /// centre, refreshed each render so up/down navigation matches the layout.
    var rows: [[Int]] = []
    var centers: [Int: Int] = [:]

    init(focusID: String, selection: Binding<AnyHashable>, values: [AnyHashable], canBeFocused: Bool = true) {
        self.focusID = focusID
        self.selection = selection
        self.values = values
        self.canBeFocused = canBeFocused
    }

    private func move(by delta: Int) {
        guard !values.isEmpty else { return }
        let current = values.firstIndex(of: selection.wrappedValue) ?? 0
        let next = max(0, min(values.count - 1, current + delta))
        selection.wrappedValue = values[next]
    }

    /// Moves to the tab nearest (by centre) in the row `delta` rows away, or
    /// returns `false` when the strip is a single row — so the key bubbles up and
    /// focus can leave the strip (e.g. to the control above/below the TabView).
    ///
    /// The step wraps, because `rows` is the *rendered* geometry and the render
    /// floats the active row to the bottom (it abuts the content). The current
    /// row is therefore always the last one, so `row + 1` is always out of
    /// bounds — taking it literally made Down impossible and the strip a one-way
    /// trip upwards. The strip is a ring: the row after the bottom one is the
    /// top one, and stepping either way rotates it back to the bottom, so up and
    /// down are inverses of each other.
    private func moveVertically(_ delta: Int) -> Bool {
        guard rows.count > 1 else { return false }
        let current = values.firstIndex(of: selection.wrappedValue) ?? 0
        guard let row = rows.firstIndex(where: { $0.contains(current) }) else { return false }
        let target = (row + delta % rows.count + rows.count) % rows.count
        let cx = centers[current] ?? 0
        guard let nearest = rows[target].min(by: {
            abs((centers[$0] ?? 0) - cx) < abs((centers[$1] ?? 0) - cx)
        }) else { return false }
        selection.wrappedValue = values[nearest]
        return true
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .left: move(by: -1); return true
        case .right: move(by: 1); return true
        case .up: return moveVertically(-1)
        case .down: return moveVertically(1)
        default: return false
        }
    }
}
