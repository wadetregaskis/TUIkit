//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservableInvalidationScopeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// An `@Observable` change used to clear the WHOLE render cache. A model that
/// changes every frame — a clock, a progress counter — then made every frame
/// a cold render of the entire tree, and nothing the memo held was ever
/// served. The body that read the property was evaluated under observation
/// tracking at its own identity, so the change now invalidates that identity
/// alone: the reader re-renders with the new value, and a sibling that never
/// read the model keeps its buffer.
@MainActor
@Suite("An observable change invalidates the view that read it, not the whole cache", .serialized)
struct ObservableInvalidationScopeTests {

    @Observable
    final class Model {
        var count = 0
    }

    /// A leaf that counts its renders, so a test can say which rows drew.
    private struct CountingText: View, Renderable {
        let text: String
        let slot: Int
        var body: Never { fatalError("CountingText renders via Renderable") }
        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            Renders.count[slot] += 1
            return FrameBuffer(text: text)
        }
    }

    private enum Renders {
        nonisolated(unsafe) static var count = [0, 0]
        static func reset() { count = [0, 0] }
    }

    private struct Reader: View {
        let model: Model
        var body: some View { CountingText(text: "count \(model.count)", slot: 0) }
    }

    private struct EnvironmentReader: View {
        @Environment(Model.self) private var model
        var body: some View { CountingText(text: "count \(model.count)", slot: 0) }
    }

    private struct Sibling: View {
        var body: some View { CountingText(text: "sibling", slot: 1) }
    }

    private static func frame<V: View>(_ view: V, tui: TUIContext, width: Int = 40) -> FrameBuffer {
        let context = RenderContext(availableWidth: width, availableHeight: 10, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.renderCache.removeInactive()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    @Test("The reader re-renders with the new value and its sibling row is served from the cache")
    func readerInvalidatedSiblingKept() {
        let model = Model()
        let tui = TUIContext()
        let view = VStack {
            _MemoizedRow(element: 1, content: Reader(model: model))
            _MemoizedRow(element: 2, content: Sibling())
        }
        _ = Self.frame(view, tui: tui)
        Renders.reset()
        let warm = Self.frame(view, tui: tui)
        #expect(warm.lines.first?.stripped.contains("count 0") == true)
        #expect(Renders.count == [0, 0], "both rows are memoised by the second frame: \(Renders.count)")
        let before = tui.renderCache.stats

        model.count = 7
        let changed = Self.frame(view, tui: tui)
        let delta = tui.renderCache.stats.delta(since: before)
        #expect(changed.lines.first?.stripped.contains("count 7") == true, "the reader shows the new value")
        // At least once, not exactly once: a memoised row that missed measures
        // its content by rendering it (the leaf is not `Layoutable`) and then
        // renders it, so a miss is two draws. The pin is the sibling's zero.
        #expect(Renders.count[0] >= 1, "the reader re-rendered: \(Renders.count)")
        #expect(Renders.count[1] == 0, "the sibling was served from the cache: \(Renders.count)")
        #expect(delta.clears == 0, "nothing cleared the whole cache: \(delta)")
    }

    @Test("A model reached through the environment invalidates only the row whose body read it")
    func environmentReaderScoped() {
        let model = Model()
        let tui = TUIContext()
        let view = VStack {
            _MemoizedRow(element: 1, content: EnvironmentReader())
            _MemoizedRow(element: 2, content: Sibling())
        }
        .environment(model)
        _ = Self.frame(view, tui: tui)
        _ = Self.frame(view, tui: tui)
        let before = tui.renderCache.stats
        Renders.reset()

        model.count = 3
        let changed = Self.frame(view, tui: tui)
        let delta = tui.renderCache.stats.delta(since: before)
        #expect(changed.lines.first?.stripped.contains("count 3") == true)
        #expect(Renders.count[0] >= 1 && Renders.count[1] == 0, "\(Renders.count)")
        #expect(delta.clears == 0, "\(delta)")
    }

    @Test("The change still requests a frame")
    func changeRequestsRender() {
        let model = Model()
        let tui = TUIContext()
        let view = _MemoizedRow(element: 1, content: Reader(model: model))
        _ = Self.frame(view, tui: tui)
        AppState.shared.didRender()
        model.count = 1
        #expect(AppState.shared.needsRender)
    }
}
