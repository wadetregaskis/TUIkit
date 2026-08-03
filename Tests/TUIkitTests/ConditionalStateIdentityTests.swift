//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ConditionalStateIdentityTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Two views swapped by a conditional (if-else / switch) must not share @State.
//  @State binds to the *view's own render identity* (in renderToBuffer /
//  measureChild, via `bindStateProperties`), and a conditional branch carries a
//  distinct identity (`#true` / `#false`) — so each branch's @State lives in its
//  own slot. This holds whether the branches are constructed directly in the
//  body or deferred through a wrapper; both are guarded below.

import Testing

@testable import TUIkit

private struct StatefulA: View {
    @State var text: String = "A"
    var body: some View { Text("A=\(text)") }
}

private struct StatefulB: View {
    @State var text: String = "B"
    var body: some View { Text("B=\(text)") }
}

/// Defers construction of its content to render time (its own body scope).
private struct TestLazy<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

/// Swaps two stateful views directly in the body.
private struct DirectHost: View {
    let showA: Bool
    var body: some View {
        if showA { StatefulA() } else { StatefulB() }
    }
}

/// Swaps them through a deferring wrapper.
private struct LazyHost: View {
    let showA: Bool
    var body: some View {
        if showA {
            TestLazy { StatefulA() }
        } else {
            TestLazy { StatefulB() }
        }
    }
}

@MainActor
@Suite("Conditional @State identity")
struct ConditionalStateIdentityTests {

    private func text(_ buffer: FrameBuffer) -> String {
        buffer.lines.joined(separator: "\n")
    }

    @Test("Directly-swapped conditional branches keep independent @State")
    func directConstructionIsolatesState() {
        // Reuse ONE context (and its StateStorage) across both renders, the way a
        // page switch persists state between frames. Render branch A (creates A's
        // slot = "A"), then switch to B: B must read its OWN default, not A's slot.
        let ctx = makeRenderContext()
        let a = text(renderToBuffer(DirectHost(showA: true), context: ctx))
        #expect(a.contains("A=A"))
        let b = text(renderToBuffer(DirectHost(showA: false), context: ctx))
        #expect(b.contains("B=B"), "B's @State must be independent of A's (render-identity keyed)")
    }

    @Test("Deferred construction also keeps independent @State")
    func deferredConstructionIsolatesState() {
        let ctx = makeRenderContext()
        let a = text(renderToBuffer(LazyHost(showA: true), context: ctx))
        #expect(a.contains("A=A"))
        let b = text(renderToBuffer(LazyHost(showA: false), context: ctx))
        #expect(b.contains("B=B"), "deferral via a wrapper is equally isolated")
    }

    /// A conditional invalidates the branch it left — but only when a frame is
    /// actually DRAWN. Doing it while measuring deletes live `@State` that no
    /// frame has replaced, and measures are not rare: every
    /// `measureFixedByRendering` view (`Button` among them) measures by
    /// rendering, so a conditional inside a button's label was sweeping the
    /// state store on every measure of every frame.
    @Test("Measuring a conditional does not delete the other branch's @State")
    func measuringDoesNotInvalidateTheInactiveBranch() {
        let ctx = makeRenderContext()
        let storage = ctx.environment.stateStorage!

        // Draw the false branch so its three slots exist and are live.
        _ = renderToBuffer(ButtonHost(showA: false), context: ctx)
        let live = storage.count
        #expect(live >= 3, "the false branch's three stateful rows must be stored")

        // MEASURE the other branch. The button measures by rendering, so this
        // reaches the conditional with `isMeasuring` set. It may add the true
        // branch's own slot; it must not take the false branch's away.
        _ = measureChild(
            ButtonHost(showA: true), proposal: ProposedSize(width: 40, height: 10), context: ctx)

        #expect(
            storage.count > live,
            "a measure must only ever add state, never drop the branch it did not draw")
    }
}

/// A conditional inside a `Button`'s label — the shape that made this cost real.
/// `_ButtonCore` measures by rendering, so measuring this measures *through* the
/// conditional. The branches are deliberately lopsided (three stateful rows
/// against one) so a wrongly-invalidated false branch shows up as a DROP in the
/// stored-state count rather than cancelling out against the true branch's slot.
private struct ButtonHost: View {
    let showA: Bool

    var body: some View {
        Button {
        } label: {
            if showA {
                StatefulA()
            } else {
                VStack {
                    StatefulB()
                    StatefulB()
                    StatefulB()
                }
            }
        }
    }
}
