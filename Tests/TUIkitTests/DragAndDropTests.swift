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

    @Test("The floating preview composites at the cursor during a drag")
    func previewFollowsCursor() {
        let log = DropLog()
        let (context, tui) = makeContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        tui.dragAndDropSession.beginFrame()

        let tree = makeTree(log)
        let buffer = renderToBuffer(tree, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 8, y: 2))

        // The root scene render draws the preview overlay at cursor+1.
        let scene = WindowGroup { self.makeTree(log) }
        let composited = scene.renderScene(context: context)
            .compositingOverlays(maxWidth: 30, maxHeight: 8, palette: context.environment.palette)
        let lines = composited.lines.map(\.stripped)
        #expect(
            lines.indices.contains(3) && lines[3].contains("CHIP"),
            "the preview (the chip's own rendering) floats at cursor+1: \(lines)")

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 8, y: 2))
        #expect(tui.dragAndDropSession.active == nil)
    }
}
