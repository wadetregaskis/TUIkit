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
}
