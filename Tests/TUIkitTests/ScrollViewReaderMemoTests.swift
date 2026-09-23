//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewReaderMemoTests.swift
//
//  A `ScrollViewReader` publishes its registry to its content. The registry was
//  not `Equatable`, and an environment value that cannot be compared turns off
//  every memo below it — so everything inside a reader was drawn from scratch
//  every frame. Found by the first `Stress` session: an editor following its
//  caret with `proxy.scrollTo` spent 61% of each keystroke walking every row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Whether the environment a render reached this leaf with could be compared.
@MainActor
private final class ComparabilityLog {
    var sawUncomparable: Bool?
}

/// A leaf that records the environment's comparability where it is drawn.
private struct ComparabilitySpy: View, Renderable {
    let log: ComparabilityLog

    var body: Never { fatalError("ComparabilitySpy renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        log.sawUncomparable = context.environment.hasUncomparableEnvironmentValue
        return FrameBuffer(text: "spy")
    }
}

@MainActor
@Suite("Memos inside a ScrollViewReader or a bound scroll position")
struct ScrollViewReaderMemoTests {
    @Test("A reader's content sees an environment the memos can compare")
    func theReaderLeavesTheEnvironmentComparable() {
        let log = ComparabilityLog()
        let tuiContext = TUIContext()
        let context = RenderContext(availableWidth: 40, availableHeight: 10, tuiContext: tuiContext)
        _ = renderToBuffer(
            ScrollViewReader { _ in
                ScrollView { ComparabilitySpy(log: log) }
            },
            context: context)
        #expect(log.sawUncomparable == false, "the reader's registry made the environment uncomparable")
    }

    /// The same for a scroll view bound with `.scrollPosition`, whose box is
    /// built afresh by every body evaluation: compared by its anchor, the one
    /// thing the content reads of it, it leaves the environment comparable.
    @Test("A bound scroll position leaves its content's environment comparable")
    func aBoundPositionLeavesTheEnvironmentComparable() {
        let log = ComparabilityLog()
        var position = ScrollPosition()
        _ = renderToBuffer(
            ScrollView { ComparabilitySpy(log: log) }
                .scrollPosition(Binding(get: { position }, set: { position = $0 })),
            context: RenderContext(availableWidth: 40, availableHeight: 10, tuiContext: TUIContext()))
        #expect(log.sawUncomparable == false, "the position box made the environment uncomparable")
    }

    @Test("A row inside a reader is served from the row memo on an unchanged frame")
    func rowsInsideAReaderAreServed() {
        let tuiContext = TUIContext()
        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tuiContext)
            environment.installVolatileReadTracker(VolatileReadTracker())
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            let buffer = renderToBuffer(
                ScrollViewReader { _ in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<20, id: \.self) { index in Text("row \(index)") }
                        }
                    }
                },
                context: RenderContext(
                    availableWidth: 40, availableHeight: 10,
                    environment: environment, tuiContext: tuiContext))
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }
        _ = frame()
        let before = tuiContext.renderCache.stats.hits
        _ = frame()
        #expect(tuiContext.renderCache.stats.hits > before, "no memo served anything inside the reader")
    }
}
