//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewSectionNamespaceTests.swift
//
//  Two split views in one frame, side by side or one inside another's detail
//  column, each keep their own column focus sections. Named by the column
//  alone, both splits' sidebars were ONE section: Down walked from one split's
//  sidebar into the other's, and Right from the second split's sidebar landed in
//  the first split's detail column.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Two split views on one screen keep their column focus sections apart")
struct NavigationSplitViewSectionNamespaceTests {

    private func context(width: Int = 120, height: Int = 12) -> RenderContext {
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

    /// A two-column split whose columns each hold one toggle, focus ids
    /// `<name>-sidebar` and `<name>-detail`.
    private func split(_ name: String) -> some View {
        NavigationSplitView {
            Toggle(name, isOn: .constant(false)).focusID("\(name)-sidebar")
        } detail: {
            Toggle(name, isOn: .constant(false)).focusID("\(name)-detail")
        }
    }

    private var sideBySide: some View {
        HStack(spacing: 0) {
            split("a")
            split("b")
        }
    }

    private var nested: some View {
        NavigationSplitView {
            Toggle("outer", isOn: .constant(false)).focusID("outer-sidebar")
        } detail: {
            split("inner")
        }
    }

    @Test("Right from the second split's sidebar reaches its own detail column")
    func rightStaysInItsOwnSplit() {
        let context = context()
        let focusManager = context.environment.focusManager!
        frame(sideBySide, context)
        focusManager.focus(id: "b-sidebar")
        #expect(focusManager.currentFocusedID == "b-sidebar", "sanity")

        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .right)))
        frame(sideBySide, context)
        #expect(focusManager.currentFocusedID == "b-detail")
    }

    @Test("Down in one split's sidebar does not walk into the other split's sidebar")
    func downStaysInItsOwnColumn() {
        let context = context()
        let focusManager = context.environment.focusManager!
        frame(sideBySide, context)
        focusManager.focus(id: "a-sidebar")

        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        frame(sideBySide, context)
        #expect(focusManager.currentFocusedID == "a-sidebar")
    }

    @Test("Only the focused split's sidebar is the active section")
    func oneActiveSidebar() {
        let context = context()
        let focusManager = context.environment.focusManager!
        frame(sideBySide, context)
        focusManager.focus(id: "a-sidebar")
        frame(sideBySide, context)

        let sidebars = focusManager.sectionIDs.filter { $0.hasPrefix("nav-split-sidebar") }
        #expect(sidebars.count == 2, "one sidebar section per split: \(sidebars)")
        #expect(sidebars.filter { focusManager.isActiveSection($0) }.count == 1)
    }

    @Test("Down in a nested split's sidebar does not walk into the outer split's sidebar")
    func nestedSidebarsStayApart() {
        let context = context()
        let focusManager = context.environment.focusManager!
        frame(nested, context)
        focusManager.focus(id: "outer-sidebar")

        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        frame(nested, context)
        #expect(focusManager.currentFocusedID == "outer-sidebar")

        focusManager.focus(id: "inner-sidebar")
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .right)))
        frame(nested, context)
        #expect(focusManager.currentFocusedID == "inner-detail")
    }

    /// The outer split's detail column holds no control of its own, only the
    /// inner split, whose columns are sections of their own. Right into it must
    /// land on the inner split's first column, not on a section with nothing to
    /// focus. Named by the column alone the sections were shared, so this worked
    /// by accident; namespaced, the outer detail section is empty.
    @Test("Right from the outer sidebar enters the nested split's first column")
    func rightEntersNestedSplit() {
        let context = context()
        let focusManager = context.environment.focusManager!
        frame(nested, context)
        focusManager.focus(id: "outer-sidebar")

        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .right)))
        frame(nested, context)
        #expect(focusManager.currentFocusedID == "inner-sidebar")
    }
}
