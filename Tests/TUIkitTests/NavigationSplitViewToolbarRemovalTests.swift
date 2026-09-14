//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewToolbarRemovalTests.swift
//
//  `.toolbar(removing: .sidebarToggle)` takes away the split view's toggle
//  handles — the ◀ on the leftmost divider and the ▶ edge column — wherever the
//  modifier sits: on the split, above it, or inside one of its columns.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("toolbar(removing: .sidebarToggle) removes the split view's toggle handles")
struct NavigationSplitViewToolbarRemovalTests {

    private func splitContext(width: Int = 60, height: Int = 9) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: TUIContext())
    }

    /// One frame through the per-frame passes, as the run loop drives them.
    private func frame(_ view: some View, _ context: RenderContext) -> FrameBuffer {
        let stateStorage = context.environment.stateStorage!
        let focusManager = context.environment.focusManager!
        context.environment.preferenceStorage?.beginRenderPass()
        stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        stateStorage.endRenderPass()
        return buffer
    }

    private final class Box {
        var visibility: NavigationSplitViewVisibility
        init(_ visibility: NavigationSplitViewVisibility) { self.visibility = visibility }
        var binding: Binding<NavigationSplitViewVisibility> {
            Binding(get: { self.visibility }, set: { self.visibility = $0 })
        }
    }

    private func has(_ glyph: Character, _ buffer: FrameBuffer) -> Bool {
        buffer.lines.contains { $0.stripped.contains(glyph) }
    }

    private func edgeSection(_ focusManager: FocusManager) -> String? {
        focusManager.section(withPrefix: "nav-split-edge")?.id
    }

    @Test("Removed on the split: no ◀, Return on the divider does nothing, and no edge column")
    func onTheSplit() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = NavigationSplitView(columnVisibility: box.binding) {
            Text("S")
        } detail: {
            Text("D")
        }
        .toolbar(removing: .sidebarToggle)

        let all = frame(view, context)
        #expect(!has("◀", all))
        #expect(all.lines.reduce(0) { $0 + $1.stripped.filter { $0 == "◦" }.count } == 3, "the grip is whole")
        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        #expect(!focusManager.dispatchKeyEvent(KeyEvent(key: .enter)))
        #expect(box.visibility == .all)

        box.visibility = .detailOnly
        let hidden = frame(view, context)
        #expect(!has("▶", hidden))
        #expect(edgeSection(focusManager) == nil)
        #expect(Array(hidden.lines[0].stripped).first == "D", "the detail takes the edge's cell")
    }

    @Test("Removed above the split")
    func aboveTheSplit() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = VStack {
            NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
                Text("S")
            } detail: {
                Text("D")
            }
        }
        .toolbar(removing: .sidebarToggle)
        let buffer = frame(view, context)
        #expect(!has("▶", buffer))
        #expect(edgeSection(focusManager) == nil)
    }

    @Test("Removed inside the sidebar, and still removed once the sidebar is hidden")
    func insideTheSidebar() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = NavigationSplitView(columnVisibility: box.binding) {
            Text("S").toolbar(removing: .sidebarToggle)
        } detail: {
            Text("D")
        }
        #expect(!has("◀", frame(view, context)))

        box.visibility = .detailOnly
        let hidden = frame(view, context)
        #expect(!has("▶", hidden))
        #expect(edgeSection(focusManager) == nil)
        #expect(!has("▶", frame(view, context)), "on the frame after too")
    }

    @Test("Removed inside the detail column of a split that starts hidden, from its first frame")
    func insideTheDetailOfAHiddenSplit() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
            Text("S")
        } detail: {
            Text("D").toolbar(removing: .sidebarToggle)
        }
        let first = frame(view, context)
        #expect(!has("▶", first))
        #expect(edgeSection(focusManager) == nil)
    }

    @Test("Removed on a split that cannot resize: no divider section at all")
    func fixedSplit() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = NavigationSplitView { Text("S") } detail: { Text("D") }
            .navigationSplitViewResizable(false)
            .toolbar(removing: .sidebarToggle)
        let buffer = frame(view, context)
        #expect(!has("◀", buffer))
        #expect(dividerSectionID(in: focusManager) == nil)
    }

    @Test("nil removes nothing, and does not bring back a toggle removed above it")
    func nilRemovesNothing() {
        let kept = frame(
            NavigationSplitView { Text("S") } detail: { Text("D") }.toolbar(removing: nil),
            splitContext())
        #expect(has("◀", kept))

        let stillRemoved = frame(
            VStack {
                NavigationSplitView { Text("S") } detail: { Text("D") }.toolbar(removing: nil)
            }
            .toolbar(removing: .sidebarToggle),
            splitContext())
        #expect(!has("◀", stillRemoved))
    }

    @Test("A column that stops removing the toggle gets it back")
    func removalWithdrawn() {
        let context = splitContext()
        var removes = true
        func view() -> some View {
            NavigationSplitView {
                Text("S").toolbar(removing: removes ? .sidebarToggle : nil)
            } detail: {
                Text("D")
            }
        }
        #expect(!has("◀", frame(view(), context)))
        removes = false
        _ = frame(view(), context)
        #expect(has("◀", frame(view(), context)))
    }
}
