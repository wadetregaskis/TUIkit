//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ConditionalStateIdentityTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Two views swapped by a conditional (if-else / switch) must not share @State.
//  @State self-hydrates at *construction* against the active hydration scope
//  (the enclosing body) plus a sequential counter — so two branches constructed
//  in the same parent body, at the same counter origin, collide on their state
//  keys. Deferring a branch's construction into its own view body (a LazyView)
//  gives it the branch-distinguished render identity, isolating its @State.
//  This guards the pattern the example app uses to host swappable pages.

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

/// Swaps two stateful views directly in the body (shared construction scope).
private struct DirectHost: View {
    let showA: Bool
    var body: some View {
        if showA { StatefulA() } else { StatefulB() }
    }
}

/// Swaps them via deferred construction (each branch gets its own scope).
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

    @Test("Deferred construction isolates @State across a conditional swap")
    func lazyDeferralIsolatesState() {
        // Reuse ONE context (and its StateStorage) across both renders, the way
        // a page switch persists state between frames.
        let ctx = makeRenderContext()
        // Render branch A: creates A's @State slot with its default ("A").
        let a = text(renderToBuffer(LazyHost(showA: true), context: ctx))
        #expect(a.contains("A=A"))
        // Switch to branch B: B must read its OWN default, not A's slot.
        let b = text(renderToBuffer(LazyHost(showA: false), context: ctx))
        #expect(b.contains("B=B"), "B's @State must be independent of A's")
    }

    @Test("Direct construction shares one @State scope (the limitation LazyView avoids)")
    func directConstructionCollides() {
        // Characterization of the construction-scope behavior: without deferral,
        // both branches hydrate at the same (parent-body identity, counter 0),
        // so B reads the slot A created — it shows A's stored value, not "B".
        // (If this ever flips to "B=B", @State became branch-identity-aware and
        // the LazyView page wrapper in the example is no longer required.)
        let ctx = makeRenderContext()
        _ = renderToBuffer(DirectHost(showA: true), context: ctx)
        let b = text(renderToBuffer(DirectHost(showA: false), context: ctx))
        #expect(b.contains("B=A"), "documents the shared-scope collision")
    }
}
