//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HandlerIDInterningTests.swift
//
//  A mouse handler's id used to be its POSITION in the walk: the dispatcher
//  handed out 0, 1, 2 … as controls registered and restarted at 0 for the next
//  walk. So a control's id was not the control's — it was whatever number the
//  registrations ahead of it happened to leave, and one control ahead of it
//  going quiet renumbered everything below. Anything holding an id across a
//  frame (a drop target, a drag zone) then named a different control.
//
//  Ids are interned per (identity, slot) now, so a control keeps its own id for
//  as long as it is on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - The tree

/// A row that registers a mouse handler only when asked to, so a frame can
/// silence the row ABOVE another without changing any type in the tree — an
/// identity has to stay the same across the frames for its id to be worth
/// anything.
private struct MouseRow: View {
    let title: String
    let listens: Bool

    var body: some View {
        if listens {
            Text(title).onMouseEvent { _ in false }
        } else {
            Text(title)
        }
    }
}

/// A leaf that registers TWO handlers at one identity.
///
/// Which is the case a slot a view picked for itself could not be trusted with:
/// a `Renderable` adds no child identity, so two sibling leaves can share one
/// identity too, and the slot is the registration's ordinal at that identity
/// rather than a number anyone writes down.
private struct TwoHandlerLeaf: View, Renderable {
    var body: Never { fatalError("TwoHandlerLeaf renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(Text("xx"), context: context)
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher
        else { return buffer }
        let outer = dispatcher.register(in: context) { _ in false }
        let inner = dispatcher.register(in: context) { _ in false }
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, handlerID: outer))
        buffer.hitTestRegions.append(
            HitTestRegion(offsetX: 0, offsetY: 0, width: 1, height: 1, handlerID: inner))
        return buffer
    }
}

// MARK: - The harness

/// Renders frames the way `RenderLoop` brackets a walk of the scene, and
/// publishes each frame's regions the way the loop does after compositing.
@MainActor
private final class WalkHarness {
    let tuiContext = TUIContext()
    let focusManager = FocusManager()

    var dispatcher: MouseEventDispatcher { tuiContext.mouseEventDispatcher }
    var cache: RenderCache { tuiContext.renderCache }

    /// Renders one walk and returns the composited buffer, whose regions are
    /// already published to the dispatcher.
    @discardableResult
    func frame(_ view: some View, width: Int = 24, height: Int = 6) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext)
        tuiContext.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        dispatcher.beginRenderPass()
        dispatcher.setActiveSupport(.full)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        tuiContext.stateStorage.endRenderPass()
        cache.removeInactive()
        return buffer
    }

    /// Three rows, the first of which can be silenced.
    @MainActor
    static func page(firstListens: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MouseRow(title: "aa", listens: firstListens)
            MouseRow(title: "bb", listens: true)
            MouseRow(title: "cc", listens: true)
        }
    }
}

extension FrameBuffer {
    /// The region of the row drawn at `row`, whichever handler it belongs to.
    fileprivate func region(atRow row: Int) -> HitTestRegion? {
        hitTestRegions.first { $0.offsetY == row }
    }
}

// MARK: - Tests

@MainActor
@Suite("Mouse handler ids are the control's own")
struct HandlerIDInterningTests {

    @Test("A control keeps its handler id when the control above it goes quiet")
    func idSurvivesASilencedSibling() {
        let harness = WalkHarness()

        let first = harness.frame(WalkHarness.page(firstListens: true))
        let bBefore = first.region(atRow: 1)?.handlerID
        #expect(bBefore != nil, "the second row registered nothing at all")

        // The row ABOVE stops registering. Nothing about the second row
        // changed, so nothing about its id should.
        let second = harness.frame(WalkHarness.page(firstListens: false))
        let bAfter = second.region(atRow: 1)?.handlerID
        #expect(
            bAfter == bBefore,
            "the second row's id moved to \(String(describing: bAfter)) when the row above went quiet")
    }

    @Test("An id held across a frame still names the control it was taken from")
    func heldIDStillNamesItsControl() {
        let harness = WalkHarness()

        // A drop target, a drag zone and the auto-scroll driver all do this:
        // take an id on one frame and resolve it to a rectangle on a later one.
        let first = harness.frame(WalkHarness.page(firstListens: true))
        let held = first.region(atRow: 1)?.handlerID
        #expect(held != nil, "the second row registered nothing at all")

        harness.frame(WalkHarness.page(firstListens: false))
        let rect = harness.dispatcher.regionRect(for: held ?? HitTestRegion.HandlerID(0))
        #expect(
            rect?.offsetY == 1,
            "the held id names the control at row \(String(describing: rect?.offsetY)), not row 1")
    }

    @Test("A control keeps its handler id across two unchanged frames")
    func idIsStableAcrossUnchangedFrames() {
        let harness = WalkHarness()
        let first = harness.frame(WalkHarness.page(firstListens: true))
        let second = harness.frame(WalkHarness.page(firstListens: true))
        #expect(first.region(atRow: 2)?.handlerID == second.region(atRow: 2)?.handlerID)
        #expect(first.region(atRow: 1)?.handlerID != first.region(atRow: 2)?.handlerID)
    }

    @Test("Two handlers registered by one view take two slots, and keep them")
    func oneViewTwoSlots() {
        let harness = WalkHarness()

        let first = harness.frame(TwoHandlerLeaf())
        let second = harness.frame(TwoHandlerLeaf())
        #expect(first.hitTestRegions.count == 2, "\(first.hitTestRegions.count) regions")
        #expect(
            first.hitTestRegions.first?.handlerID != first.hitTestRegions.last?.handlerID,
            "one view's two handlers were given one id between them")
        #expect(first.hitTestRegions.first?.handlerID == second.hitTestRegions.first?.handlerID)
        #expect(first.hitTestRegions.last?.handlerID == second.hitTestRegions.last?.handlerID)
    }

    @Test("An id is dropped when its control stops rendering, and its neighbour's is not")
    func anIDIsDroppedWithItsControl() {
        let harness = WalkHarness()

        let first = harness.frame(WalkHarness.page(firstListens: true))
        #expect(harness.dispatcher.handlerIDs.count == 3, "three rows, three ids")

        // The top row goes quiet. Its id has nothing left to name, and nothing
        // cached covers it, so the pass that prunes the cache prunes it too.
        let second = harness.frame(WalkHarness.page(firstListens: false))
        #expect(harness.dispatcher.handlerIDs.count == 2, "the silent row's id was kept")
        #expect(first.region(atRow: 2)?.handlerID == second.region(atRow: 2)?.handlerID)

        // It comes back as a new control, with an id of its own: ids are never
        // handed out twice, so the dropped one names nothing rather than this.
        let third = harness.frame(WalkHarness.page(firstListens: true))
        #expect(harness.dispatcher.handlerIDs.count == 3)
        #expect(third.region(atRow: 0)?.handlerID != first.region(atRow: 0)?.handlerID)
        #expect(third.region(atRow: 2)?.handlerID == first.region(atRow: 2)?.handlerID)
    }
}
