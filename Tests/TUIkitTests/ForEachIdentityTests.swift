//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ForEachIdentityTests.swift
//
//  Regression tests for GitHub-class bug: ForEach row identity must follow
//  the element's `id`, not its position (SwiftUI's ForEach contract). Row
//  identity used to be the positional index, so reordering the data handed
//  every row its neighbour's @State ("b:a", "a:b"), inserting at the head
//  gave the new element the first row's state, and the shifted-out element's
//  state was lost entirely.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A row that stamps its @State with its label on first appearance — so the
/// rendered "label:stamp" pair reveals whose state each row is wearing.
private struct StampRow: View {
    let label: String
    @State private var stamp = "?"

    var body: some View {
        Text("\(label):\(stamp)")
            .onAppear { stamp = label }
    }
}

@MainActor
@Suite("ForEach identity follows the element id")
struct ForEachIdentityTests {
    private let tuiContext = TUIContext()

    /// One live-loop-shaped frame over `items`; returns the stripped rows.
    private func frame(_ items: [String]) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)
        tuiContext.lifecycle.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let view = VStack {
            ForEach(items, id: \.self) { StampRow(label: $0) }
        }
        // Two renders per frame so an onAppear-stamped @State is visible
        // within the frame that stamped it.
        _ = renderToBuffer(view, context: context)
        let buffer = renderToBuffer(view, context: context)
        tuiContext.lifecycle.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped }
    }

    @Test("Reordering the data moves each row's @State with its element")
    func reorderMovesState() {
        // The onAppear stamp lands a frame after it fires; settle first.
        _ = frame(["a", "b"])
        let settled = frame(["a", "b"])
        print("SETTLED:", settled)
        #expect(settled == ["a:a", "b:b"])
        let reordered = frame(["b", "a"])
        print("REORDERED:", reordered)
        #expect(reordered == ["b:b", "a:a"], "state follows the id, not the position")
    }

    @Test("Inserting at the head neither steals nor resets existing state")
    func insertionPreservesState() {
        _ = frame(["a", "b"])
        _ = frame(["x", "a", "b"])       // x appears and stamps this frame…
        let rows = frame(["x", "a", "b"])  // …and is visible from the next.
        print("INSERTED:", rows)
        #expect(rows[1] == "a:a" && rows[2] == "b:b", "existing rows keep their state: \(rows)")
        #expect(rows[0] == "x:x", "the new row starts fresh and stamps itself: \(rows)")
    }

    @Test("Removing an element drops only its own state")
    func removalDropsOnlyOwnState() {
        _ = frame(["a", "b", "c"])
        let rows = frame(["a", "c"])
        print("REMOVED:", rows)
        #expect(rows == ["a:a", "c:c"], "surviving rows keep their own state: \(rows)")
    }

    @Test("List rows follow their id across a data shift too")
    func listRowsFollowID() {
        func listFrame(_ items: [String]) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 10,
                environment: environment, tuiContext: tuiContext)
            tuiContext.lifecycle.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            let view = List("T", selection: .constant(String?.none)) {
                ForEach(items, id: \.self) { StampRow(label: $0) }
            }
            _ = renderToBuffer(view, context: context)
            let buffer = renderToBuffer(view, context: context)
            tuiContext.lifecycle.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped }.filter { $0.contains(":") }
        }

        _ = listFrame(["a", "b"])
        _ = listFrame(["a", "b"])
        let rows = listFrame(["b", "a"])
        #expect(rows.contains { $0.contains("b:b") } && rows.contains { $0.contains("a:a") },
                "List rows carry their own state after reorder: \(rows)")
    }
}
