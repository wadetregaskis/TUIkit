//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueMemoBuildTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

/// The value memo builds what it draws: a caller hands it the builder and the
/// draw, and the memo calls the builder at most once per call, only on a path
/// that draws or measures the row. A hit builds nothing — the whole saving of a
/// row memo, since most rows hit — and a miss builds once and draws what it
/// built. Pinned because a check that needs the built value before a serve
/// (compare it, and draw the same value when it differs) relies on there being
/// exactly one build to hand on.
@MainActor
@Suite("The value memo builds a row at most once per call")
struct ValueMemoBuildTests {
    /// How many times a row was built.
    private final class Builds {
        var count = 0
    }

    /// A leaf that draws and measures its text.
    private struct Leaf: View, Renderable, Layoutable {
        let text: String
        var body: Never { fatalError("Leaf renders via Renderable") }
        func renderToBuffer(context: RenderContext) -> FrameBuffer { FrameBuffer(text: text) }
        func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
            ViewSize.fixed(text.count, 1)
        }
    }

    /// A context shaped like the render loop's: a cache, state storage, and
    /// the per-frame tracker the memo's store gate reads.
    private func liveContext() -> RenderContext {
        var environment = EnvironmentValues()
        let cache = RenderCache()
        environment.renderCache = cache
        environment.stateStorage = StateStorage()
        environment.installVolatileReadTracker(VolatileReadTracker())
        cache.beginRenderPass()
        return RenderContext(
            availableWidth: 20, availableHeight: 4, environment: environment, identity: ViewIdentity(path: "Root"))
    }

    /// The row, built by a builder that counts.
    private func row(_ builds: Builds) -> _MemoizedRow<Int, String, Leaf> {
        _MemoizedRow(element: 7, source: "seven") { text in
            builds.count += 1
            return Leaf(text: text)
        }
    }

    /// Builds a verifier adds to a served row: it draws a fresh copy to
    /// compare with what it served.
    private var verifierBuilds: Int { RenderCache.verifiesRenderMemo ? 1 : 0 }
    private var measureVerifierBuilds: Int { RenderCache.verifiesMeasureMemo ? 1 : 0 }

    @Test("A miss builds the row once and draws it; a hit builds nothing")
    func renderBuildsOncePerMiss() {
        let builds = Builds()
        let context = liveContext()
        let drawn = row(builds).renderToBuffer(context: context)
        #expect(drawn.lines.first?.stripped == "seven")
        #expect(builds.count == 1, "the miss built the row once: \(builds.count)")

        context.renderCache?.beginRenderPass()
        let served = row(builds).renderToBuffer(context: context)
        #expect(served.lines.first?.stripped == "seven")
        #expect(builds.count == 1 + verifierBuilds, "the hit built nothing: \(builds.count)")
    }

    @Test("A measure's miss builds the row once; its hit builds nothing")
    func measureBuildsOncePerMiss() {
        let builds = Builds()
        var context = liveContext()
        context.isMeasuring = true
        let measured = row(builds).sizeThatFits(proposal: .unspecified, context: context)
        #expect(measured.width == 5)
        #expect(builds.count == 1, "the miss built the row once: \(builds.count)")

        // A new pass, so the per-pass measure memo is empty and the ask
        // reaches the cross-frame size memo, which serves it.
        context.renderCache?.beginRenderPass()
        let served = row(builds).sizeThatFits(proposal: .unspecified, context: context)
        #expect(served.width == 5)
        #expect(builds.count == 1 + measureVerifierBuilds, "the hit built nothing: \(builds.count)")
    }
}
