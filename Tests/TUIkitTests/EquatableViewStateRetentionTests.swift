//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EquatableViewStateRetentionTests.swift
//
//  A cache hit skips rendering the subtree — but the subtree's `@State` must
//  survive the frame as if it HAD rendered. StateStorage prunes any identity
//  not marked active at the end of a pass, and a hit only ever visited the
//  wrapper's own identity: everything below it was one hit frame away from
//  being reset to its defaults.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("EquatableView keeps its subtree's state alive on cache hits")
struct EquatableViewStateRetentionTests {

    /// Hands its `@State` binding out so the test can mutate it.
    private final class BindingBox {
        var set: ((Int) -> Void)?
    }

    /// The stateful leaf, nested INSIDE a stack so its `@State` binds at a
    /// deeper identity than the wrapper's own — the identities a cache hit
    /// never visits. (A direct child can share the wrapper's identity, which
    /// the wrapper's own `markActive` covers incidentally.)
    private struct StatefulLeaf: View {
        let box: BindingBox
        @State private var count = 0

        var body: some View {
            box.set = { count = $0 }
            return Text("count=\(count)")
        }
    }

    /// Equatable by `tag` alone: the state inside is invisible to `==`, which
    /// is the ordinary shape — a row memoised by its data, holding incidental
    /// internal state.
    private struct StatefulRow: View, @MainActor Equatable {
        let tag: Int
        let box: BindingBox

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.tag == rhs.tag }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("row \(tag)")
                StatefulLeaf(box: box)
            }
        }
    }

    @Test("@State below a cache hit survives the hit frame")
    func stateSurvivesHitFrame() {
        let tui = TUIContext()
        let box = BindingBox()

        func render(tag: Int) -> [String] {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 4, environment: environment,
                tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let lines = renderToBuffer(
                EquatableView(content: StatefulRow(tag: tag, box: box)), context: context
            ).lines.map(\.stripped)
            tui.stateStorage.endRenderPass()
            return lines
        }

        // Frame 1: a miss — renders, stores, hands the binding out.
        #expect(render(tag: 1).contains { $0.contains("count=0") })

        // Mutate the state (which also invalidates the cached buffer), so
        // frame 2 re-renders with the new value and re-stores it.
        box.set?(42)
        #expect(render(tag: 1).contains { $0.contains("count=42") })

        // Frame 3: nothing changed — a genuine cache HIT (asserted, or this
        // test proves nothing). The subtree is not visited; its state must
        // still be marked as alive.
        let hitsBefore = tui.renderCache.stats.hits
        #expect(render(tag: 1).contains { $0.contains("count=42") })
        #expect(tui.renderCache.stats.hits > hitsBefore, "frame 3 was served from the cache")

        // Frame 4: change the VALUE (`==` now fails), forcing a real
        // re-render that reads the @State box. Pre-fix, frame 3's prune
        // deleted it and this shows the default again.
        #expect(
            render(tag: 2).contains { $0.contains("count=42") },
            "the subtree's state survived the hit frame")
    }
}
