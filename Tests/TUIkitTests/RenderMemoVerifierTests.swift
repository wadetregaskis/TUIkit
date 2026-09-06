//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderMemoVerifierTests.swift
//
//  `TUIKIT_VERIFY_RENDER_MEMO` re-renders every served buffer and reports what
//  disagrees. It exists because a served buffer can be wrong in a way nothing
//  else notices: the memo's claim is that an equal view value at the same size
//  draws the same cells, and that quietly depends on everything ELSE the subtree
//  read while drawing. A value applied through a modifier is compared; one
//  ASSIGNED directly to `context.environment` is not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Draws an environment value that nothing tracks, so a stale serve is visible.
private struct InsetReader: View, Renderable {
    var body: Never { fatalError("InsetReader renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: ["inset=\(context.environment.menuRowInset)"])
    }
}

private struct Tagged: View, @preconcurrency Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { true }
    var body: some View { InsetReader() }
}

@MainActor
@Suite("The render-memo verifier", .serialized)
struct RenderMemoVerifierTests {
    private func render(inset: Int, tui: TUIContext) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        // Assigned directly, exactly as `MenuPopover` and friends do — the one
        // path `noteAppliedEnvironment` cannot see.
        environment.menuRowInset = inset
        let context = RenderContext(
            availableWidth: 40, availableHeight: 2, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(EquatableView(content: Tagged()), context: context)
        tui.stateStorage.endRenderPass()
        return buffer
    }

    @Test("it names a buffer served across an untracked environment change")
    func catchesStaleServe() {
        let was = RenderCache.verifiesRenderMemo
        RenderCache.verifiesRenderMemo = true
        defer { RenderCache.verifiesRenderMemo = was }

        let tui = TUIContext()
        _ = render(inset: 0, tui: tui)
        _ = render(inset: 7, tui: tui)

        #expect(!tui.renderCache.renderMemoMismatches.isEmpty)
        #expect(tui.renderCache.renderMemoMismatches.first?.contains("inset=") == true)
    }

    @Test("it stays quiet when the memo is right")
    func quietWhenCorrect() {
        let was = RenderCache.verifiesRenderMemo
        RenderCache.verifiesRenderMemo = true
        defer { RenderCache.verifiesRenderMemo = was }

        let tui = TUIContext()
        _ = render(inset: 3, tui: tui)
        _ = render(inset: 3, tui: tui)

        #expect(tui.renderCache.renderMemoMismatches.isEmpty)
    }

    @Test("it is off unless asked for")
    func offByDefault() {
        // It re-renders what the memo just saved, so it costs more than the memo
        // saves and must never be on in an app. Asserted against the variable
        // rather than against `false`, because the whole suite is also run WITH
        // the mode on — where the honest expectation is the opposite.
        let asked = ProcessInfo.processInfo.environment["TUIKIT_VERIFY_RENDER_MEMO"] != nil
        #expect(RenderCache.verifiesRenderMemo == asked)
    }
}
