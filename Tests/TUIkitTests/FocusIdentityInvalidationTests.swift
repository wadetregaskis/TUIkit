//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusIdentityInvalidationTests.swift
//
//  A focus move has to reach the render cache. The buffer a control drew before
//  the focus arrived draws it without its focus ring, and the buffer it drew
//  while it held the focus draws a ring it no longer has — so a cached buffer at
//  either end of a move is stale the moment the move happens, and nothing in the
//  memo's key (identity, view value, size) can see it.
//
//  Nothing memoized holds such a buffer yet: a focus registration declares a
//  render side effect, so every memo above one declines to store. This is the
//  precondition for the commit that lets an unfocused registration be replayed
//  instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Where a probe rendered, so a test can plant a cached buffer at exactly that
/// identity — the identity a memo above it would key on.
private final class IdentityCapture: @unchecked Sendable {
    var identity: ViewIdentity?
}

/// A focus stop with no chrome of its own: it registers through
/// `FocusRegistration.register`, the single registrar every interactive control
/// in the framework goes through, and records the identity it rendered at.
private struct FocusProbe: View, Renderable {
    let focusID: String
    let capture: IdentityCapture

    var body: Never { fatalError("FocusProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        capture.identity = context.identity
        FocusRegistration.register(
            context: context,
            handler: ActionHandler(focusID: focusID, action: {}),
            focusID: focusID)
        return FrameBuffer(text: focusID)
    }
}

@MainActor
@Suite("Focus moves reach the render cache")
struct FocusIdentityInvalidationTests {

    /// Renders one frame the way `RenderLoop` brackets one: the focus ring and
    /// the cache's pass state begun before the walk and settled after it.
    private func frame(_ view: some View, tui: TUIContext, focus: FocusManager) {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
    }

    /// Three focus stops, rendered once, with a buffer planted in the cache at
    /// each one's identity — standing in for the entry a memo above it will
    /// hold once an unfocused registration can be replayed. Focus lands on `a`,
    /// the first registrant.
    private func plantedFrame() throws -> (
        tui: TUIContext, focus: FocusManager, ids: [String: ViewIdentity]
    ) {
        let tui = TUIContext()
        let focus = FocusManager()
        let captures = ["a": IdentityCapture(), "b": IdentityCapture(), "c": IdentityCapture()]
        frame(
            VStack {
                FocusProbe(focusID: "a", capture: captures["a"]!)
                FocusProbe(focusID: "b", capture: captures["b"]!)
                FocusProbe(focusID: "c", capture: captures["c"]!)
            }, tui: tui, focus: focus)

        var ids: [String: ViewIdentity] = [:]
        for (name, capture) in captures {
            let identity = try #require(capture.identity, "\(name) rendered")
            ids[name] = identity
            tui.renderCache.store(
                identity: identity, view: name, buffer: FrameBuffer(text: name),
                contextWidth: 40, contextHeight: 10)
        }
        #expect(tui.renderCache.count == 3)
        #expect(focus.currentFocusedID == "a", "the first registrant is auto-focused")
        return (tui, focus, ids)
    }

    private func isCached(_ identity: ViewIdentity, _ name: String, in cache: RenderCache) -> Bool {
        cache.lookup(identity: identity, view: name, contextWidth: 40, contextHeight: 10) != nil
    }

    @Test("The control the focus arrives on loses its cached buffer")
    func arrivalDropsTheEntry() throws {
        let planted = try plantedFrame()
        planted.focus.focus(id: "b")
        planted.tui.renderCache.beginRenderPass()
        #expect(!isCached(planted.ids["b"]!, "b", in: planted.tui.renderCache))
    }

    @Test("The control the focus leaves loses its cached buffer")
    func departureDropsTheEntry() throws {
        let planted = try plantedFrame()
        planted.focus.focus(id: "b")
        planted.tui.renderCache.beginRenderPass()
        #expect(!isCached(planted.ids["a"]!, "a", in: planted.tui.renderCache))
    }

    @Test("A control the focus did not touch keeps its cached buffer")
    func unrelatedEntryIsKept() throws {
        let planted = try plantedFrame()
        planted.focus.focus(id: "b")
        planted.tui.renderCache.beginRenderPass()
        #expect(isCached(planted.ids["c"]!, "c", in: planted.tui.renderCache))
    }

    @Test("Moving the focus between two Buttons invalidates both of them")
    func realControlsAreInvalidated() {
        let tui = TUIContext()
        let focus = FocusManager()
        frame(
            VStack {
                Button("One") {}.focusID("one")
                Button("Two") {}.focusID("two")
            }, tui: tui, focus: focus)
        #expect(focus.currentFocusedID == "one")

        // Drain whatever the first frame enqueued — including the auto-focus
        // that landed on "one" — so the delta below is the move and nothing else.
        tui.renderCache.beginRenderPass()
        let before = tui.renderCache.stats
        focus.focus(id: "two")
        tui.renderCache.beginRenderPass()
        #expect(tui.renderCache.stats.delta(since: before).subtreeClears == 2)
    }
}
