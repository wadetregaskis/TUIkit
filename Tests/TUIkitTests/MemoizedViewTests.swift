//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MemoizedViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A view whose text is NOT part of its memo token, so a served entry is
/// observable: if the old rendering is reused the old text is what appears.
private struct TokenLabel: View {
    let text: String

    var body: some View {
        Text(text)
    }
}

/// Hands its `@State` binding out so the test can mutate it.
private final class BindingBox {
    var set: ((Int) -> Void)?
}

/// A stateful leaf nested one level down, so its `@State` binds at an identity
/// below the wrapper's own.
private struct StatefulLeaf: View {
    let box: BindingBox
    @State private var count = 0

    var body: some View {
        box.set = { count = $0 }
        return Text("count=\(count)")
    }
}

private struct StatefulHolder: View {
    let box: BindingBox

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("holder")
            StatefulLeaf(box: box)
        }
    }
}

/// A view holding a closure — the shape that cannot reasonably be `Equatable`,
/// and the reason `memoized(id:)` exists alongside `equatable()`.
private struct ClosureHolder: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Text(text)
    }
}

@MainActor
@Suite("memoized(id:)", .serialized)
struct MemoizedViewTests {
    private func testContext(
        width: Int = 40,
        height: Int = 8,
        identity: ViewIdentity = ViewIdentity(path: "Root")
    ) -> RenderContext {
        let tuiContext = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        env.renderCache = RenderCache()
        env.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: env, identity: identity)
    }

    @Test("An unchanged token reuses the previous rendering")
    func unchangedTokenReuses() {
        let context = testContext()
        _ = renderToBuffer(TokenLabel(text: "first").memoized(id: 1), context: context)
        // Same token, DIFFERENT content: the whole point of the promise is that
        // the framework takes the caller's word, so what comes back is "first".
        let second = renderToBuffer(TokenLabel(text: "second").memoized(id: 1), context: context)

        #expect(second.lines.first?.contains("first") == true)
        #expect(second.lines.first?.contains("second") == false)
    }

    @Test("A changed token renders afresh")
    func changedTokenRerenders() {
        let context = testContext()
        _ = renderToBuffer(TokenLabel(text: "first").memoized(id: 1), context: context)
        let second = renderToBuffer(TokenLabel(text: "second").memoized(id: 2), context: context)

        #expect(second.lines.first?.contains("second") == true)
    }

    @Test("A view holding a closure can be memoized")
    func closureHoldingViewMemoizes() {
        let context = testContext()
        _ = renderToBuffer(
            ClosureHolder(text: "first", action: {}).memoized(id: "k"), context: context)
        let second = renderToBuffer(
            ClosureHolder(text: "second", action: {}).memoized(id: "k"), context: context)

        #expect(second.lines.first?.contains("first") == true)
    }

    @Test("Wrapping adds no level to the render identity")
    func addsNoIdentityLevel() {
        // Proven the way EquatableViewStateRetentionTests proves it: `@State`
        // below the wrapper keeps its value. A wrapper with a real `body` would
        // append its body type to the identity, re-keying every slot beneath —
        // so adding `.memoized(id:)` to speed a view up would reset it.
        let tui = TUIContext()
        let box = BindingBox()

        func render(token: Int) -> [String] {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 4, environment: environment,
                tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let lines = renderToBuffer(
                StatefulHolder(box: box).memoized(id: token), context: context
            ).lines.map(\.stripped)
            tui.stateStorage.endRenderPass()
            return lines
        }

        #expect(render(token: 1).contains { $0.contains("count=0") })
        box.set?(7)
        // A new token forces a real re-render, so what comes back is the state
        // as it now stands — 7, not the default, if the identity held.
        #expect(render(token: 2).contains { $0.contains("count=7") })
    }

    @Test("A different offered width renders afresh")
    func widthChangeRerenders() {
        // The offered size is part of the entry, not the token: a subtree laid
        // out for 40 columns must not be served into 10.
        let tui = TUIContext()

        func render(width: Int, text: String) -> [String] {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: width, availableHeight: 4, environment: environment,
                tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            let lines = renderToBuffer(
                TokenLabel(text: text).memoized(id: 1), context: context
            ).lines.map(\.stripped)
            tui.stateStorage.endRenderPass()
            return lines
        }

        _ = render(width: 40, text: "first")
        // Same token, so only the width differs — and the width is enough.
        #expect(render(width: 10, text: "second").contains { $0.contains("second") })
    }
}
