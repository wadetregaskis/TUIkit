//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StackGuardTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A view nested inside itself to a configurable depth — the same shape as the
/// `deep` stress scenario, minimised. Each level wraps the next in a container
/// (`VStack` + `border` + `padding`), so the measure/render recursion descends
/// through the guarded `measureChild`/`renderChild` funnels once per level. The
/// outermost label is always `L0`; the innermost, if reached, is `leaf`.
private struct DeepNest: View {
    let level: Int
    let maxDepth: Int

    var body: some View {
        if level >= maxDepth {
            Text("leaf")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("L\(level)")
                Self(level: level + 1, maxDepth: maxDepth).padding(1).border()
            }
        }
    }
}

@MainActor
@Suite("Stack guard")
struct StackGuardTests {
    private func render(_ view: some View, cols: Int, rows: Int) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.stateStorage = StateStorage()
        environment.renderCache = RenderCache()
        let context = RenderContext(availableWidth: cols, availableHeight: rows, environment: environment)
        return renderToBuffer(AnyView(view), context: context)
    }

    @Test("A pathologically deep tree truncates instead of overflowing the stack")
    func deepNestingDoesNotOverflow() {
        // Far deeper than any stack can hold: without the guard this SIGSEGVs and
        // takes the whole test process down. The guard stops the descent when the
        // *real* remaining stack runs low, so this returns a bounded frame — the
        // test merely completing is itself the proof that it did not crash.
        let buffer = render(DeepNest(level: 0, maxDepth: 100_000), cols: 120, rows: 40)

        #expect(buffer.width > 0 && buffer.height > 0, "a truncated deep tree still produces a frame")
        #expect(
            buffer.lines.contains { $0.contains("L0") },
            "the outer, in-budget levels render normally")
        #expect(
            !buffer.lines.contains { $0.contains("leaf") },
            "the descent stopped before the (unreachable) innermost level — it was truncated, not completed")
    }

    @Test("Normal nesting depth renders fully (the guard does not trip)")
    func normalNestingRendersFully() {
        // A handful of levels is nowhere near the stack limit: the guard must not
        // trip, so the innermost leaf must render. A generous viewport keeps the
        // per-level border/padding from clipping the content away.
        let buffer = render(DeepNest(level: 0, maxDepth: 4), cols: 400, rows: 400)

        #expect(
            buffer.lines.contains { $0.contains("leaf") },
            "shallow nesting renders all the way to the innermost leaf")
        #expect(
            buffer.lines.contains { $0.contains("L0") },
            "and the outermost level too")
    }

    @Test("hasHeadroom reports plenty of stack at shallow depth")
    func headroomAtShallowDepth() {
        // Called from a shallow stack, the guard must report headroom (either the
        // platform reports bounds and we're far above the floor, or bounds are
        // unavailable and the guard is disabled — both yield `true`).
        #expect(StackGuard.hasHeadroom())
    }
}
