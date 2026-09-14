//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewResizeColumnTests.swift
//
//  A resized width belongs to a COLUMN, not to a position on screen.
//  `columnVisibility` changes which column comes first: `.doubleColumn` hides
//  the sidebar and puts the content column where it was. Widths, pins and
//  divider handlers stored by position handed the content column the sidebar's
//  width, and let the first divider go on resizing the hidden sidebar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("NavigationSplitView keeps each column's width when columns hide")
struct NavigationSplitViewResizeColumnTests {

    private func resizeContext(width: Int = 100, height: Int = 12) -> RenderContext {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
    }

    /// One frame through the per-frame render passes, including the
    /// `StateStorage` GC, so what is asserted is what persists between frames.
    private func frame(_ view: some View, _ context: RenderContext) -> FrameBuffer {
        let stateStorage = context.environment.stateStorage!
        let focusManager = context.environment.focusManager!
        stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        stateStorage.endRenderPass()
        return buffer
    }

    /// The column of every divider grip (a `◦` dot) on the centre row, left to
    /// right. The first is the leading visible column's width.
    private func gripXs(_ buffer: FrameBuffer) -> [Int] {
        guard buffer.height > 0 else { return [] }
        let mid = Array(buffer.lines[buffer.height / 2].stripped)
        return mid.indices.filter { mid[$0] == "◦" }
    }

    private func threeColumns(_ visibility: Binding<NavigationSplitViewVisibility>) -> some View {
        NavigationSplitView(columnVisibility: visibility) {
            Text("SIDEBAR")
        } content: {
            Text("CONTENT")
        } detail: {
            Text("DETAIL")
        }
    }

    @Test("A width pinned on the sidebar does not follow the content column into .doubleColumn")
    func sidebarPinStaysWithTheSidebar() {
        var visibility = NavigationSplitViewVisibility.doubleColumn
        let binding = Binding(get: { visibility }, set: { visibility = $0 })
        let view = threeColumns(binding)

        // The yardstick: the content column under .doubleColumn in a split
        // nobody has resized.
        let untouched = gripXs(frame(view, resizeContext())).first

        let context = resizeContext()
        let focusManager = context.environment.focusManager!
        visibility = .all
        guard let sidebar = gripXs(frame(view, context)).first else {
            Issue.record("expected a divider grip"); return
        }
        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .home))
        let pinned = gripXs(frame(view, context)).first
        #expect(pinned != sidebar, "Home narrows the sidebar")
        #expect(pinned != untouched, "the pin must differ from the yardstick to prove anything")

        visibility = .doubleColumn
        let content = gripXs(frame(view, context)).first
        #expect(
            content == untouched,
            """
            the content column keeps its own width: \(String(describing: content)), \
            untouched \(String(describing: untouched)), sidebar pinned at \(String(describing: pinned))
            """)

        visibility = .all
        #expect(gripXs(frame(view, context)).first == pinned, "and the sidebar comes back pinned")
    }

    @Test("An arrow key on .doubleColumn's divider resizes the content column, not the hidden sidebar")
    func doubleColumnDividerResizesContent() {
        var visibility = NavigationSplitViewVisibility.all
        let binding = Binding(get: { visibility }, set: { visibility = $0 })
        let view = threeColumns(binding)
        let context = resizeContext()
        let focusManager = context.environment.focusManager!

        // .all first, so the first divider's handler is built for the sidebar.
        guard let sidebar = gripXs(frame(view, context)).first else {
            Issue.record("expected a divider grip"); return
        }
        visibility = .doubleColumn
        guard let content = gripXs(frame(view, context)).first else {
            Issue.record("expected a divider grip"); return
        }

        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .right))
        let widened = gripXs(frame(view, context)).first
        #expect(
            widened == content + 1,
            "→ widens the content column: was \(content), now \(String(describing: widened))")

        visibility = .all
        let sidebarAfter = gripXs(frame(view, context)).first
        #expect(
            sidebarAfter == sidebar,
            "the hidden sidebar's width is untouched: was \(sidebar), now \(String(describing: sidebarAfter))")
    }

    @Test("After .doubleColumn, the second divider in .all is its own Tab stop and resizes the content column")
    func dividerIdsFollowTheirColumn() {
        var visibility = NavigationSplitViewVisibility.doubleColumn
        let binding = Binding(get: { visibility }, set: { visibility = $0 })
        let view = threeColumns(binding)
        let context = resizeContext()
        let focusManager = context.environment.focusManager!

        // .doubleColumn first: the content column's handler is built as the
        // FIRST divider. In .all it is the second, beside a new sidebar handler.
        _ = frame(view, context)
        visibility = .all
        let before = gripXs(frame(view, context))
        guard before.count == 2 else {
            Issue.record("expected two divider grips, got \(before)"); return
        }

        let secondSection = dividerSectionID(in: focusManager, index: 1)
        focusManager.activateSection(id: secondSection ?? "")
        #expect(
            focusManager.currentFocusedID == secondSection,
            "the focused divider answers to its own section's id, not the first divider's")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .right))
        let buffer = frame(view, context)
        let after = gripXs(buffer)
        #expect(
            after == [before[0], before[1] + 1],
            "→ on the second divider widens only the content column: \(before) → \(after)")

        // The ids stamped on the dividers' hit regions, which scrolling a
        // focused control into view looks up, name each divider once.
        let dividerIDs = buffer.hitTestRegions.compactMap(\.focusID)
            .filter { $0.hasPrefix("nav-split-divider-") }
        #expect(dividerIDs.count == 2 && Set(dividerIDs).count == 2, "distinct divider ids: \(dividerIDs)")
    }

    /// A divider belongs to the column on its left. Named by its position, the
    /// content column's divider was `…-divider-1-…` in `.all` and `…-divider-0-…`
    /// in `.doubleColumn`, so hiding the sidebar while it held the focus removed
    /// its section, and the focus fell back to the first section on the page.
    @Test("A focused divider keeps the focus when the sidebar to its left hides")
    func focusedDividerSurvivesHidingTheSidebar() {
        var visibility = NavigationSplitViewVisibility.all
        let binding = Binding(get: { visibility }, set: { visibility = $0 })
        let view = VStack(spacing: 0) {
            Toggle("above", isOn: .constant(false)).focusID("above")
            threeColumns(binding)
        }
        let context = resizeContext()
        let focusManager = context.environment.focusManager!

        _ = frame(view, context)
        guard let contentDivider = dividerSectionID(in: focusManager, index: 1) else {
            Issue.record("expected two divider sections"); return
        }
        focusManager.activateSection(id: contentDivider)
        _ = frame(view, context)
        #expect(focusManager.currentFocusedID == contentDivider, "sanity")

        visibility = .doubleColumn
        _ = frame(view, context)
        #expect(focusManager.activeSectionIdentifier == contentDivider)
        #expect(focusManager.currentFocusedID == contentDivider)
    }
}
