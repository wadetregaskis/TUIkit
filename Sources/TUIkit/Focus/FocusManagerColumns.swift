//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerColumns.swift
//
//  Sections laid out side by side as one row of columns — a split view's — and the
//  Left and Right keys that move between them. Beside `Focus.swift`, which is at its
//  file-length limit.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Declares `ids` — sections already registered this frame — as one row of
    /// columns, in left-to-right order, so Left and Right move focus between them.
    func registerSectionGroup(_ ids: [String]) {
        guard ids.count > 1 else { return }
        for id in ids { sectionGroups[id] = ids }
    }

    /// Left or Right, moved to the neighbouring column when the active section is one
    /// of a row of columns.
    ///
    /// A split view's lists are separate sections side by side, and a flat `List`
    /// declines Left and Right — it has nothing to do with them — so they fell to the
    /// arrow fallback and stepped up and down inside the column instead, which is what
    /// Up and Down already do. Content that DOES use them (an outline's disclosure, a
    /// slider, a text field) had the key first and keeps it.
    ///
    /// - Returns: `true` when focus moved; `false` at the first or last column, so the
    ///   key is not handled and an enclosing handler can still take it; `nil` when the
    ///   key is not Left or Right or the active section is not a column, so the
    ///   ordinary arrow fallback runs.
    func moveBetweenColumns(for event: KeyEvent) -> Bool? {
        guard event.key == .left || event.key == .right, let active = activeSectionIdentifier,
            let group = sectionGroups[active], let index = group.firstIndex(of: active)
        else { return nil }
        let target = index + (event.key == .right ? 1 : -1)
        guard group.indices.contains(target) else { return false }
        // The section's remembered focus, as a click on that column restores it.
        activateSection(id: group[target])
        return true
    }
}
