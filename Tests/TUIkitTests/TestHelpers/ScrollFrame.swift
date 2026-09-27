//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollFrame.swift
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// One frame of `view`, 30 columns by `height` lines, as the render loop
/// draws it: each pass fenced (preferences, state, the render cache, focus)
/// and the focus manager and `tui`'s runtime services in the environment, so
/// a scroll view's position, a held row and a focused control carry from one
/// frame to the next.
///
/// Returned as the screen reads, for comparing one layout with another — a
/// lazy stack with the same lines in one eager column, whose seek is exact:
/// each line stripped of styling, without the scroll indicators' column or
/// the padding before it, and any "N more" line read as `<more>`. A windowed
/// stack places the scrollbar's thumb and arrows, and counts the "more"
/// lines, from an estimate by design.
@MainActor
func scrollFrame<V: View>(
    _ view: V, tui: TUIContext, focusManager: FocusManager, height: Int = 8
) -> [String] {
    var environment = EnvironmentValues()
    environment.focusManager = focusManager
    environment.applyRuntimeServices(from: tui)
    let context = RenderContext(
        availableWidth: 30, availableHeight: height, environment: environment, tuiContext: tui)
    tui.preferences.beginRenderPass()
    tui.stateStorage.beginRenderPass()
    tui.renderCache.beginRenderPass()
    focusManager.beginRenderPass()
    let buffer = renderToBuffer(view, context: context)
    focusManager.endRenderPass()
    tui.stateStorage.endRenderPass()
    tui.renderCache.removeInactive()
    return buffer.lines.map { line in
        let text = String(
            line.stripped.reversed().drop { $0 == " " || isScrollbarGlyph($0) }.reversed())
        return text.contains(" more ") ? "<more>" : text
    }
}

private func isScrollbarGlyph(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    return (0x2500...0x259F).contains(scalar.value) || scalar == "▲" || scalar == "▼"
}
