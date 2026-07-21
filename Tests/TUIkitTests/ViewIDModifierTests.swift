//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewIDModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  `.id(_:)` splices a keyed step into the structural identity, so changing the
//  id gives the subtree a fresh identity — resetting @State, re-firing lifecycle,
//  and missing the render cache. @State's default only applies on the FIRST bind
//  at a given identity, so seeding the default from an init parameter lets a test
//  observe whether an identity is fresh (default applied) or reused (default
//  ignored).

import Testing

@testable import TUIkit

/// Seeds its @State default from `seed`, so the rendered text reveals whether
/// the @State was freshly bound (shows the new seed) or reused (shows the old).
private struct SeededState: View {
    let seed: String
    @State private var text: String

    init(seed: String) {
        self.seed = seed
        self._text = State(initialValue: seed)
    }

    var body: some View { Text("t=\(text)") }
}

@MainActor
@Suite(".id(_:)")
struct ViewIDModifierTests {
    private func plain(_ buffer: FrameBuffer) -> String {
        buffer.lines.joined(separator: "\n")
    }

    /// Renders one frame: a real begin/end render pass around the render, the way
    /// the render loop drives every frame (so stale identities are pruned).
    private func frame(_ view: some View, _ context: RenderContext) -> String {
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return plain(renderToBuffer(view, context: context))
    }

    @Test("The same .id keeps @State; a new .id resets it; returning to an id is fresh")
    func idControlsStateIdentity() {
        let context = makeRenderContext()

        #expect(frame(SeededState(seed: "X").id(1), context).contains("t=X"))
        #expect(
            frame(SeededState(seed: "Y").id(1), context).contains("t=X"),
            "the same .id reuses the existing @State — the new default is ignored")
        #expect(
            frame(SeededState(seed: "Z").id(2), context).contains("t=Z"),
            "a new .id is a fresh identity — the new default applies")
        #expect(
            frame(SeededState(seed: "W").id(1), context).contains("t=W"),
            "id 1 left the tree while id 2 rendered, so returning to it is a fresh view")
    }

    @Test("Two views under the same .id at different positions stay independent")
    func distinctPositionsAreIndependent() {
        // `.id` re-keys, it doesn't globally alias: two separately-positioned
        // `.id(1)` subtrees are still distinct identities (position + key), so
        // each keeps its own @State default.
        let context = makeRenderContext()
        let out = frame(
            VStack {
                SeededState(seed: "top").id(1)
                SeededState(seed: "bottom").id(1)
            }, context)
        #expect(out.contains("t=top") && out.contains("t=bottom"))
    }
}
