//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StateWindowRetentionTests.swift
//
//  §5h of "Locating things without drawing them": a row that leaves a
//  windowing container's visible WINDOW has not left the TREE — its @State
//  must survive until the row leaves the data or the container itself dies.
//  Before the fix, `StateStorage.endRenderPass` pruned every identity not
//  hydrated on the render path that frame, so a lazy row's Toggle silently
//  reset one frame after scrolling out (measured; see the design doc).
//
//  The end-to-end pins drive the real LazyVStack windowed path. List/Table
//  window through the same `retainSubtree` declaration; their behaviour is
//  pinned at the StateStorage unit level here because their scroll state
//  lives in a persisted handler that tests cannot reach non-intrusively.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Deliberately NOT Equatable: keeps `ForEach` off the row-memo path so the
/// rows re-render (and re-read their @State) every frame they are visible.
private struct RetentionItem {
    let index: Int
}

private struct StampedRow: View {
    let item: RetentionItem
    @State private var stamp = 0

    var body: some View {
        Text("row \(item.index) stamp \(stamp)")
            .onAppear { stamp = 99 }
    }
}

@MainActor
@Suite("windowed-out row @State retention")
struct StateWindowRetentionTests {
    private func makeView() -> some View {
        let items = (0..<20).map(RetentionItem.init)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.index) { StampedRow(item: $0) }
        }
    }

    /// One live-loop-shaped frame; returns the trimmed row lines.
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, windowOffset: Int?
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        if let windowOffset {
            environment.scrollContentWindow = ScrollContentWindow(
                offset: windowOffset, viewportHeight: 4)
        }
        let context = RenderContext(
            availableWidth: 40, availableHeight: 200,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("A row keeps its @State while scrolled out of the window")
    func stateSurvivesLeavingTheWindow() {
        let tuiContext = TUIContext()
        let view = makeView()

        renderFrame(view, tuiContext: tuiContext, windowOffset: 0)  // rows 0-3; onAppear stamps
        let stamped = renderFrame(view, tuiContext: tuiContext, windowOffset: 0)
        #expect(stamped[1] == "row 1 stamp 99", "sanity: the stamp landed while visible")

        renderFrame(view, tuiContext: tuiContext, windowOffset: 10)  // rows 0-3 leave the window
        renderFrame(view, tuiContext: tuiContext, windowOffset: 10)  // ...and stay out a frame

        let returned = renderFrame(view, tuiContext: tuiContext, windowOffset: 0)
        #expect(
            returned[1] == "row 1 stamp 99",
            "leaving the window must not reset a row's @State (got: \(returned[1]))")
    }

    @Test("State is still pruned when the windowing container itself leaves the tree")
    func containerDeathStillPrunes() {
        let tuiContext = TUIContext()
        let view = makeView()

        renderFrame(view, tuiContext: tuiContext, windowOffset: 0)
        let stamped = renderFrame(view, tuiContext: tuiContext, windowOffset: 0)
        #expect(stamped[1] == "row 1 stamp 99")

        // The stack is gone for a frame — a different tree renders. Its
        // retention declaration lapses, so the whole subtree prunes.
        renderFrame(Text("interloper"), tuiContext: tuiContext, windowOffset: nil)

        let returned = renderFrame(view, tuiContext: tuiContext, windowOffset: 0)
        #expect(
            returned[1] == "row 1 stamp 0",
            "a container that left the tree must not keep its rows' state alive")
    }
}

@MainActor
@Suite("StateStorage.retainSubtree")
struct RetainSubtreeTests {
    private final class Marker {}

    @Test("A retained root keeps unmarked descendants through the prune")
    func retainedDescendantsSurvive() {
        let storage = StateStorage()
        let root = ViewIdentity(rootType: Marker.self)
        let row = root.child(type: Marker.self, index: 7)
        let key = StateStorage.StateKey(identity: row, propertyIndex: 0)
        _ = storage.storage(for: key, default: 1)

        storage.beginRenderPass()
        storage.retainSubtree(root)  // the container renders; the row does not
        storage.endRenderPass()

        let survived: StateBox<Int>? = storage.storage(for: key, default: 2)
        #expect(survived?.value == 1, "the windowed-out descendant's state must survive")
    }

    @Test("Non-descendants still prune normally")
    func unrelatedKeysStillPrune() {
        let storage = StateStorage()
        let root = ViewIdentity(rootType: Marker.self)
        let elsewhere = ViewIdentity(rootType: Int.self).child(type: Marker.self, index: 1)
        let key = StateStorage.StateKey(identity: elsewhere, propertyIndex: 0)
        _ = storage.storage(for: key, default: 1)

        storage.beginRenderPass()
        storage.retainSubtree(root)
        storage.endRenderPass()

        let box: StateBox<Int> = storage.storage(for: key, default: 2)
        #expect(box.value == 2, "retention must be scoped to the declared subtree")
    }

    @Test("A root that stops being declared stops protecting")
    func lapsedRootPrunes() {
        let storage = StateStorage()
        let root = ViewIdentity(rootType: Marker.self)
        let row = root.child(type: Marker.self, index: 3)
        let key = StateStorage.StateKey(identity: row, propertyIndex: 0)
        _ = storage.storage(for: key, default: 1)

        storage.beginRenderPass()
        storage.retainSubtree(root)
        storage.endRenderPass()

        storage.beginRenderPass()  // this pass, the container never declares
        storage.endRenderPass()

        let box: StateBox<Int> = storage.storage(for: key, default: 2)
        #expect(box.value == 2, "retention is per-pass; a dead container's subtree prunes")
    }

    @Test("Tracked (onChange) values follow the same retention")
    func trackedValuesRetained() {
        let storage = StateStorage()
        let root = ViewIdentity(rootType: Marker.self)
        let row = root.child(type: Marker.self, index: 5)
        let key = StateStorage.StateKey(identity: row, propertyIndex: 0)
        storage.setTrackedValue("baseline", for: key)

        storage.beginRenderPass()
        storage.retainSubtree(root)
        storage.endRenderPass()

        #expect(
            storage.trackedValue(for: key) == "baseline",
            "an off-window row's onChange baseline must not reset")
    }
}
