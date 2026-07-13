//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragAndDropTests.swift
//
//  `.draggable` / `.dropDestination`: press-drag-release delivers the
//  payload to the targeted destination, `isTargeted` tracks hover, type
//  mismatches are ignored, drops in the void cancel, modifiers ride along in
//  DropInfo, and the floating preview composites at the cursor during the
//  drag.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Drag and drop", .serialized)
struct DragAndDropTests {

    private final class DropLog {
        var dropped: [String] = []
        var info: DropInfo?
        var targetedChanges: [Bool] = []
    }

    /// A chip on row 0 and a drop zone on row 4, in a fixed frame so the
    /// geometry is deterministic.
    private func makeTree(_ log: DropLog, accept: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("apple")
            Text("").frame(height: 3)
            Text("ZONE========")
                .dropDestination(for: String.self) { items, info in
                    log.dropped.append(contentsOf: items)
                    log.info = info
                    return accept
                } isTargeted: { targeted in
                    log.targetedChanges.append(targeted)
                }
        }
    }

    private func makeContext() -> (RenderContext, TUIContext) {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: env, tuiContext: tui)
        return (context, tui)
    }

    @Test("Press-drag-release delivers the payload and tracks targeting")
    func dragAndDropDelivers() {
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        let buffer = renderToBuffer(makeTree(log), context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        // Press on the chip (row 0), drag onto the zone (row 4), release
        // while holding ctrl — the modifiers must arrive in DropInfo.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
        #expect(tui.dragAndDropSession.active != nil, "the first movement begins the drag")
        #expect(log.targetedChanges.isEmpty, "not over the zone yet")

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        #expect(log.targetedChanges == [true], "entering the zone targets it")

        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 3, y: 4, ctrl: true))
        #expect(log.dropped == ["apple"])
        #expect(log.targetedChanges == [true, false], "the drop untargets the zone")
        #expect(log.info?.ctrl == true, "modifiers held at release ride along")
        #expect(log.info?.x == 3 && log.info?.y == 0, "drop point is zone-local")
        #expect(tui.dragAndDropSession.active == nil, "the session ends after the drop")
    }

    @Test("A drop outside any destination cancels")
    func dropInVoidCancels() {
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        let buffer = renderToBuffer(makeTree(log), context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 20, y: 2))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 20, y: 2))

        #expect(log.dropped.isEmpty)
        #expect(log.targetedChanges.isEmpty)
        #expect(tui.dragAndDropSession.active == nil)
    }

    @Test("A destination for a different payload type is never targeted")
    func typeMismatchIgnored() {
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        // An Int payload over a String destination.
        let tree = VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable(42)
            Text("").frame(height: 3)
            Text("ZONE========")
                .dropDestination(for: String.self) { items, _ in
                    log.dropped.append(contentsOf: items)
                    return true
                } isTargeted: { log.targetedChanges.append($0) }
        }
        let buffer = renderToBuffer(tree, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 4))

        #expect(log.dropped.isEmpty)
        #expect(log.targetedChanges.isEmpty, "an incompatible zone is never targeted")
    }

    @Test("A draggable inside a drop zone can still start its drag")
    func draggableInsideZoneStillDrags() {
        // The zone's inert region must not eat presses over its content —
        // the dispatcher stops at the innermost matching region even when
        // the handler declines, so the zone region fronts the list instead.
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        // The chip lives INSIDE a zone (a shelf); a second zone below takes
        // the drop.
        let shelved = VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("apple")
                Text("").frame(width: 4, height: 1)
            }
            .dropDestination(for: Int.self) { _, _ in true }
            Text("").frame(height: 2)
            Text("ZONE========")
                .dropDestination(for: String.self) { items, info in
                    log.dropped.append(contentsOf: items)
                    log.info = info
                    return true
                } isTargeted: { log.targetedChanges.append($0) }
        }
        let buffer = renderToBuffer(shelved, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        #expect(
            tui.dragAndDropSession.active != nil,
            "the chip's press starts a drag despite the enclosing zone")
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 4))
        #expect(log.dropped == ["apple"], "and the drop lands on the inner zone")
    }

    @Test("A drop still lands after a re-render that shifts handler ids mid-drag")
    func dropSurvivesMidDragRerender() {
        // Handler ids reset to 0 every render pass and are only stable while
        // the tree SHAPE is stable. A re-render between the last drag
        // movement and the release is routine (the consumed drag requests
        // one), and `isTargeted` highlighting or async state can change the
        // shape — inserting a region before the zone shifts every later id.
        // The session must not resolve the drop through a stale id: the
        // payload must land on the zone under the cursor, and the zone's
        // `isTargeted` must close out (no permanently-highlighted zone).
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        @MainActor
        @ViewBuilder func tree(_ extraRow: Bool) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("apple")
                if extraRow {
                    Text("XTRA").draggable(99)  // registers BEFORE the zone → ids shift
                } else {
                    Text("").frame(height: 1)
                }
                Text("").frame(height: 2)
                Text("ZONE========")
                    .dropDestination(for: String.self) { items, info in
                        log.dropped.append(contentsOf: items)
                        log.info = info
                        return true
                    } isTargeted: { log.targetedChanges.append($0) }
            }
        }

        func render(_ extraRow: Bool) {
            dispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let buffer = renderToBuffer(tree(extraRow), context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
        }

        render(false)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        #expect(log.targetedChanges == [true], "over the zone before the re-render")

        // The consumed drag triggers a re-render; this one also changes the
        // tree shape, so the zone re-registers under a DIFFERENT handler id.
        render(true)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 4))
        #expect(log.dropped == ["apple"], "the drop must resolve against the CURRENT frame")
        #expect(log.info?.y == 0, "zone-local coordinates from the current registration")
        #expect(
            log.targetedChanges.last == false,
            "the zone must untarget when the drag ends: \(log.targetedChanges)")
        #expect(tui.dragAndDropSession.active == nil)
    }

    @Test("A zone that disappears mid-drag untargets and the drop cancels")
    func removedZoneUntargetsAndCancels() {
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        func render(zonePresent: Bool) {
            dispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let tree = VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("apple")
                Text("").frame(height: 3)
                if zonePresent {
                    Text("ZONE========")
                        .dropDestination(for: String.self) { items, _ in
                            log.dropped.append(contentsOf: items)
                            return true
                        } isTargeted: { log.targetedChanges.append($0) }
                }
            }
            let buffer = renderToBuffer(tree, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
        }

        render(zonePresent: true)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        #expect(log.targetedChanges == [true])

        // The zone vanishes from the tree (async data change) mid-drag.
        render(zonePresent: false)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 4))
        #expect(log.dropped.isEmpty, "no zone under the cursor anymore — the drop cancels")
        #expect(
            log.targetedChanges == [true, false],
            "the removed zone's isTargeted must still close out: \(log.targetedChanges)")
        #expect(tui.dragAndDropSession.active == nil)
    }

    @Test("The floating preview keeps the grabbed cell under the cursor")
    func previewFollowsCursor() {
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        let tree = makeTree(log)
        let buffer = renderToBuffer(tree, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        // Grab the chip one cell in from its left edge; the drag anchors
        // there (.grabPoint default): preview origin = cursor − grab.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 8, y: 2))

        let frame = tui.dragAndDropSession.previewFrame()
        #expect(frame?.x == 7 && frame?.y == 2, "cursor (8,2) − grab (1,0): \(String(describing: frame))")

        let scene = WindowGroup { self.makeTree(log) }
        let composited = scene.renderScene(context: context)
            .compositingOverlays(maxWidth: 30, maxHeight: 8, palette: context.environment.palette)
        let lines = composited.lines.map(\.stripped)
        #expect(
            lines.indices.contains(2) && lines[2].contains("CHIP"),
            "the preview rides so the grabbed cell stays under the cursor: \(lines)")

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 8, y: 2))
        #expect(tui.dragAndDropSession.active == nil)
    }

    @Test("dragPreviewAnchor(.offset) trails the cursor; DropInfo reports the frame")
    func offsetAnchorAndDropInfoFrame() {
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        // The pre-anchor behaviour, opted back in per-subtree.
        let tree = VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("apple").dragPreviewAnchor(.offset(x: 1, y: 1))
            Text("").frame(height: 3)
            Text("ZONE========")
                .dropDestination(for: String.self) { items, info in
                    log.dropped.append(contentsOf: items)
                    log.info = info
                    return true
                }
        }
        let buffer = renderToBuffer(tree, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        let frame = tui.dragAndDropSession.previewFrame()
        #expect(frame?.x == 4 && frame?.y == 5, "cursor (3,4) + offset (1,1): \(String(describing: frame))")

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: 4))
        #expect(log.dropped == ["apple"])
        // The zone starts at y=4, so its local space subtracts 4 rows; the
        // preview frame arrives in that same space, sized like the chip.
        #expect(log.info?.previewX == 4 && log.info?.previewY == 1, "\(String(describing: log.info))")
        #expect(log.info?.previewWidth == 4 && log.info?.previewHeight == 1)
    }

    @Test("A press released without movement clicks the interactive child")
    func clickFallsThroughToChildren() {
        // The draggable's region is innermost and claims every press as a
        // potential drag — but a press + release with no movement is a
        // CLICK, and must reach a Button inside (SwiftUI behaviour). A
        // genuine drag must NOT click.
        final class Counter { var clicks = 0 }
        let counter = Counter()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        let tree = Button("GO") { counter.clicks += 1 }.draggable("apple")
        let buffer = renderToBuffer(tree, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        // Click: press + release on the same cell.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        #expect(counter.clicks == 1, "the click reaches the button inside the draggable")

        // Drag: press, move, release — the button must NOT fire.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 8, y: 2))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 8, y: 2))
        #expect(counter.clicks == 1, "a genuine drag is not a click")
        #expect(tui.dragAndDropSession.active == nil)
    }

    @Test("Hover transitions ride through to the interactive child")
    func hoverForwardsToChildren() {
        // The draggable's innermost region receives the synthetic
        // .entered / .exited transitions; they must forward to the content
        // so a hoverable child keeps its affordance.
        final class HoverLog { var changes: [Bool] = [] }
        let log = HoverLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)  // hover needs motion
        tui.dragAndDropSession.beginFrame()

        let tree = Text("CHIP")
            .onHover { log.changes.append($0) }
            .draggable("apple")
        let buffer = renderToBuffer(tree, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 1, y: 0))
        #expect(log.changes == [true], "entering the chip hovers the child")
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 20, y: 5))
        #expect(log.changes == [true, false], "leaving un-hovers it")
    }
}
