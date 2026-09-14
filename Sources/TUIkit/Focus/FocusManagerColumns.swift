//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerColumns.swift
//
//  Sections laid out side by side as one row of columns — a split view's — and the
//  Left and Right keys that move between them. Beside `Focus.swift`, which is at its
//  file-length limit.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One row of column sections, as ``FocusManager/registerSectionGroup(_:)``
/// declared it.
struct SectionGroup {
    /// The columns' section ids, left to right.
    let ids: [String]

    /// How many sections were registered when the group was declared, which is
    /// after every column rendered. With the first column's position it bounds
    /// the sections registered while the columns rendered, a nested split's
    /// among them.
    let end: Int
}

extension FocusManager {
    /// Declares `ids` — sections already registered this frame — as one row of
    /// columns, in left-to-right order, so Left and Right move focus between them.
    /// Call it after the columns have rendered: the sections registered since
    /// then are what a column with no control of its own hands the focus to.
    func registerSectionGroup(_ ids: [String]) {
        guard ids.count > 1 else { return }
        let group = SectionGroup(ids: ids, end: sections.count)
        for id in ids { sectionGroups[id] = group }
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
            let group = sectionGroups[active], let index = group.ids.firstIndex(of: active)
        else { return nil }
        let target = index + (event.key == .right ? 1 : -1)
        guard group.ids.indices.contains(target) else { return false }
        // The section's remembered focus, as a click on that column restores it.
        activateSection(id: entrySection(ofColumn: target, in: group))
        return true
    }

    /// The section Left or Right enters for column `column` of `group`: the
    /// column's own, unless nothing in it can take the focus and a section
    /// registered while it rendered can — a split view nested in a detail
    /// column, whose own columns are sections of their own. Entering the empty
    /// column's section left nothing focused.
    private func entrySection(ofColumn column: Int, in group: SectionGroup) -> String {
        let id = group.ids[column]
        guard let start = sections.firstIndex(where: { $0.id == id }),
            !sections[start].focusables.contains(where: { $0.canBeFocused })
        else { return id }
        // The column's sections run up to the next column's, or for the last
        // column to the end of the group.
        let next = group.ids.indices.contains(column + 1)
            ? sections.firstIndex { $0.id == group.ids[column + 1] } : nil
        let end = min(next ?? group.end, sections.count)
        guard start + 1 < end else { return id }
        return sections[(start + 1)..<end]
            .first { $0.focusables.contains(where: { $0.canBeFocused }) }?.id ?? id
    }
}
