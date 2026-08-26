//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BodyMutationDiagnosticTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Why these exist
//
// The specimen is real: `_ImageCore` recorded its source on every render pass,
// which asked for another frame every frame and held an otherwise-idle screen
// at 2% CPU while writing nothing (fixed in `75a732fa`). Finding it needed a
// purpose-built PTY probe *and* a guess about where to look.
//
// This diagnostic answers the same question by construction, so the next one
// costs a run rather than an investigation. These tests pin what it reports,
// what it does NOT report, and that it stays silent when nobody asked for it.

/// A view that writes its own `@State` during the walk — the defect shape.
private struct MutatingProbe: View, Renderable {
    var body: Never { fatalError("MutatingProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let storage = context.environment.stateStorage!
        let box: StateBox<Int> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: 0)
        box.value += 1  // the mutation under test
        return FrameBuffer(lines: ["mutating"])
    }
}

/// The control: identical, but reads without writing.
private struct WellBehavedProbe: View, Renderable {
    var body: Never { fatalError("WellBehavedProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let storage = context.environment.stateStorage!
        let box: StateBox<Int> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: 0)
        return FrameBuffer(lines: ["read \(box.value)"])
    }
}

@MainActor
@Suite("Body-mutation diagnostic")
struct BodyMutationDiagnosticTests {

    /// The diagnostic is opt-in via the environment, so a test has to install
    /// one explicitly rather than rely on the process it happens to run in.
    private func contextWithDiagnostic() -> (RenderContext, BodyMutationDiagnostic) {
        let diagnostic = BodyMutationDiagnostic()
        let context = RenderContext(
            availableWidth: 20,
            availableHeight: 4,
            environment: EnvironmentValues(),
            tuiContext: TUIContext()
        ).isolatingRenderCache()
        context.renderCache!.bodyMutationDiagnostic = diagnostic
        // `isolatingRenderCache()` swaps the CONTEXT's cache; the state boxes
        // take their invalidation sink from `StateStorage.renderCache`, which
        // still points at the TUIContext's original. Point it at the isolated
        // one too, or every write in these tests would route past the
        // diagnostic and each assertion would pass vacuously.
        context.environment.stateStorage?.renderCache = context.renderCache
        return (context, diagnostic)
    }

    @Test("A write during the walk is reported, with the subtree that did it")
    func writeDuringWalkIsReported() {
        let (context, diagnostic) = contextWithDiagnostic()

        diagnostic.beginTraversal()
        _ = renderToBuffer(MutatingProbe(), context: context)
        diagnostic.endTraversal()

        #expect(diagnostic.reports.count == 1, "saw \(diagnostic.reports)")
        #expect(
            diagnostic.reports.first?.identity.isEmpty == false,
            "the report must name the subtree, or it cannot be acted on")
    }

    @Test("A view that only reads is not reported")
    func readOnlyViewIsSilent() {
        let (context, diagnostic) = contextWithDiagnostic()

        diagnostic.beginTraversal()
        _ = renderToBuffer(WellBehavedProbe(), context: context)
        diagnostic.endTraversal()

        #expect(diagnostic.reports.isEmpty, "saw \(diagnostic.reports)")
    }

    /// The distinction that matters. A write at startup is a one-off; a write on
    /// every frame is the bug that never lets the loop idle. Reporting once per
    /// frame is what makes the two tellable apart in a log.
    @Test("A per-frame mutation is reported once per frame, not once ever")
    func perFrameMutationRepeatsPerFrame() {
        let (context, diagnostic) = contextWithDiagnostic()
        let cache = context.renderCache!

        for _ in 0..<3 {
            cache.beginRenderPass()
            diagnostic.beginTraversal()
            _ = renderToBuffer(MutatingProbe(), context: context)
            diagnostic.endTraversal()
        }

        #expect(diagnostic.reports.count == 3, "saw \(diagnostic.reports)")
        #expect(
            Set(diagnostic.reports.map(\.frame)).count == 3,
            "each report belongs to its own frame: \(diagnostic.reports.map(\.frame))")
    }

    /// Two walks of one frame — which happens on the first frame and on a
    /// header-height correction — must not read as two separate offences.
    @Test("Two walks of one frame report once")
    func repeatedWalksWithinAFrameReportOnce() {
        let (context, diagnostic) = contextWithDiagnostic()

        context.renderCache!.beginRenderPass()
        for _ in 0..<2 {
            diagnostic.beginTraversal()
            _ = renderToBuffer(MutatingProbe(), context: context)
            diagnostic.endTraversal()
        }

        #expect(diagnostic.reports.count == 1, "saw \(diagnostic.reports)")
    }

    /// The window is the whole point: a write outside a walk is ordinary — it is
    /// what every event handler does — and must never be reported.
    @Test("A write outside any walk is not a body mutation")
    func writeOutsideWalkIsSilent() {
        let (context, diagnostic) = contextWithDiagnostic()

        // Render once inside a window so the box exists and is wired to the
        // cache, then write again with the window closed, as a key handler would.
        diagnostic.beginTraversal()
        _ = renderToBuffer(WellBehavedProbe(), context: context)
        diagnostic.endTraversal()

        let storage = context.environment.stateStorage!
        let box: StateBox<Int> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: 0)
        box.value = 99

        #expect(diagnostic.reports.isEmpty, "saw \(diagnostic.reports)")
    }

    /// A write from another thread is somebody's `.task` finishing, not a body
    /// mutation — even if it lands while the main thread happens to be walking.
    @Test("A write from another thread is not reported")
    func writeFromAnotherThreadIsSilent() async {
        let (context, diagnostic) = contextWithDiagnostic()

        diagnostic.beginTraversal()
        _ = renderToBuffer(WellBehavedProbe(), context: context)

        let storage = context.environment.stateStorage!
        let box: StateBox<Int> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: 0)

        // `Thread.detachNewThread` rather than a `Task`: a task can be scheduled
        // onto the very thread doing the walking, which would make this test
        // assert the opposite of what it means to.
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                box.value = 42
                continuation.resume()
            }
        }
        diagnostic.endTraversal()

        #expect(diagnostic.reports.isEmpty, "saw \(diagnostic.reports)")
    }

    @Test("Nobody pays for it unless they asked")
    func disabledByDefault() {
        // The env var is not set in the test process, so a stock cache has none.
        let context = RenderContext(
            availableWidth: 20, availableHeight: 4,
            environment: EnvironmentValues(), tuiContext: TUIContext()
        ).isolatingRenderCache()

        #expect(BodyMutationDiagnostic.isEnabled == false)
        #expect(context.renderCache?.bodyMutationDiagnostic == nil)
    }
}
