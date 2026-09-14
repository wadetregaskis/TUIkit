//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewFocusRecoveryTests.swift
//
//  Hiding the column that holds the keyboard — by writing `columnVisibility`
//  from outside the split, or with a chord — must leave the keyboard in the
//  split. The hidden column's sections are simply not registered any more, and
//  `endRenderPass` sent the focus to the first section on the page.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Hiding the focused column keeps the keyboard in the split")
struct NavigationSplitViewFocusRecoveryTests {

    private func splitContext(width: Int = 90, height: Int = 9) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: TUIContext())
    }

    /// One frame through the per-frame passes, as the run loop drives them.
    private func frame(_ view: some View, _ context: RenderContext) {
        let stateStorage = context.environment.stateStorage!
        let focusManager = context.environment.focusManager!
        stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        stateStorage.endRenderPass()
    }

    private final class Box {
        var visibility: NavigationSplitViewVisibility
        init(_ visibility: NavigationSplitViewVisibility) { self.visibility = visibility }
        var binding: Binding<NavigationSplitViewVisibility> {
            Binding(get: { self.visibility }, set: { self.visibility = $0 })
        }
    }

    /// A toggle above a three-column split. The sidebar's toggle sits in a
    /// `.focusSection()` of its own, so the section that holds the keyboard is
    /// not the column's.
    private func page(_ box: Box) -> some View {
        VStack(spacing: 0) {
            Toggle("above", isOn: .constant(false)).focusID("above")
            NavigationSplitView(columnVisibility: box.binding) {
                Toggle("side", isOn: .constant(false)).focusID("side").focusSection()
            } content: {
                Toggle("list", isOn: .constant(false)).focusID("list")
            } detail: {
                Toggle("detail", isOn: .constant(false)).focusID("detail")
            }
        }
    }

    private func twoColumnPage(_ box: Box) -> some View {
        VStack(spacing: 0) {
            Toggle("above", isOn: .constant(false)).focusID("above")
            NavigationSplitView(columnVisibility: box.binding) {
                Toggle("side", isOn: .constant(false)).focusID("side")
            } detail: {
                Toggle("detail", isOn: .constant(false)).focusID("detail")
            }
        }
    }

    @Test("Hiding the sidebar while a section inside it holds the keyboard moves it to the content column")
    func nestedSectionInHiddenSidebar() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = page(box)
        frame(view, context)
        focusManager.focus(id: "side")
        frame(view, context)
        #expect(focusManager.currentFocusedID == "side", "sanity")

        box.visibility = .doubleColumn
        frame(view, context)
        #expect(focusManager.activeSectionIdentifier?.hasPrefix("nav-split-content") == true)
        #expect(focusManager.currentFocusedID == "list")
    }

    @Test("Hiding a two-column split's focused sidebar moves the keyboard to the detail column")
    func twoColumnSidebar() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = twoColumnPage(box)
        frame(view, context)
        focusManager.focus(id: "side")
        frame(view, context)

        box.visibility = .detailOnly
        frame(view, context)
        #expect(focusManager.currentFocusedID == "detail")
    }

    @Test("Hiding the sidebar while its divider holds the keyboard moves it into the split, not above it")
    func focusedDividerOfHiddenSidebar() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = twoColumnPage(box)
        frame(view, context)
        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        frame(view, context)

        box.visibility = .detailOnly
        frame(view, context)
        #expect(focusManager.currentFocusedID == "detail")
    }

    @Test("A column that stays visible keeps the keyboard")
    func visibleColumnKeepsFocus() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = page(box)
        frame(view, context)
        focusManager.focus(id: "list")
        frame(view, context)

        box.visibility = .doubleColumn
        frame(view, context)
        #expect(focusManager.currentFocusedID == "list")
    }

    @Test("Focus outside the split stays where it is when a column hides")
    func focusOutsideTheSplitStays() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = page(box)
        frame(view, context)
        focusManager.focus(id: "above")
        frame(view, context)

        box.visibility = .detailOnly
        frame(view, context)
        #expect(focusManager.currentFocusedID == "above")
    }
}
