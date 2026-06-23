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
    /// returns `false` when there is no such row — so the key bubbles up and
    /// focus can leave the strip (e.g. to the control above/below the TabView).
    private func moveVertically(_ delta: Int) -> Bool {
        let current = values.firstIndex(of: selection.wrappedValue) ?? 0
        guard let row = rows.firstIndex(where: { $0.contains(current) }) else { return false }
        let target = row + delta
        guard rows.indices.contains(target) else { return false }
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
