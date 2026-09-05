//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayClippingTests.swift
//
//  Which containers clip a floating layer, and which do not.
//
//  A layer carrying a piece of a view's own drawing — `.offset`, `.position`,
//  a transition's overshoot — is CONTENT, and a container that clips its
//  content clips it too. SwiftUI says which containers those are: a scroll
//  view clips to its bounds by default (`View.scrollClipDisabled(_:)` is the
//  modifier that turns it off), while a plain stack or a bare `.frame` clips
//  nothing — `View.clipped(antialiased:)` documents that a bounding frame is
//  used only for layout and content beyond it stays visible.
//
//  A layer that is a SURFACE is not content: a drop-down, a menu, a dialog or
//  a toast is a window over the page, and a picker on the last row of a list
//  must not lose its options to the list's edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("Overlay clipping")
struct OverlayClippingTests {

    /// One frame, composited exactly as `RenderLoop` composites it, stripped
    /// to plain text.
    private func composited(_ view: some View, width: Int, height: Int) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .compositingOverlays(maxWidth: width, maxHeight: height, palette: SystemPalette.green)
            .lines.map { $0.stripped }
    }

    // MARK: - Containers that clip

    @Test("An offset row does not paint past a ScrollView's viewport")
    func scrollViewClipsDisplacedDrawing() {
        // The shipped bug: nothing clipped a layer, so the eight cells of
        // "ABCDEFGH" displaced seven columns right of a twelve-wide viewport
        // painted three columns of the page beside it.
        let out = composited(
            ScrollView {
                Text("ABCDEFGH").offset(x: 7)
            }.frame(width: 12, height: 4),
            width: 24, height: 6)
        #expect(out[0].count <= 12 || out[0].dropFirst(12).allSatisfy { $0 == " " },
            "the layer escaped the viewport: \(out)")
        #expect(out[0].hasPrefix("       ABCDE"), "and what fits still draws: \(out)")
    }

    @Test("An offset row does not paint past a List's bounds")
    func listClipsDisplacedDrawing() {
        // The twin: a `List` clips its content in SwiftUI for the same reason
        // a `ScrollView` does, and this one was overwriting its own right
        // border before it reached the page.
        let out = composited(
            List {
                Text("ABCDEFGH").offset(x: 7)
            }.frame(width: 14, height: 5),
            width: 30, height: 8)
        for (row, line) in out.enumerated() {
            #expect(line.count <= 14 || line.dropFirst(14).allSatisfy { $0 == " " },
                "row \(row) escaped the list: \(out)")
        }
    }

    @Test("A layer scrolled off the top loses the rows above the viewport")
    func scrollViewClipsAtTheTopEdge() {
        // The other edge, where the clip has to cut the CONTENT rather than
        // move the layer: a composited buffer cannot be placed at a negative
        // row, so a layer half above the viewport must arrive short.
        // Straddling, not wholly outside: a layer entirely above the viewport
        // is already culled by span, and would pin nothing here.
        let out = composited(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TTTT")
                        Text("UUUU")
                    }.offset(y: -1)
                    Text("AAAA")
                }
            }.frame(width: 8, height: 3),
            width: 8, height: 3)
        #expect(!out.contains { $0.contains("TTTT") },
            "the row above the viewport was drawn inside it: \(out)")
        #expect(out[0].hasPrefix("UUUU"), "and the row that is inside kept its place: \(out)")
    }

    // MARK: - Containers that do not

    @Test("A plain stack does not clip an offset child")
    func plainStackDoesNotClip() {
        // SwiftUI's rule, and the reason the clip above is a property of the
        // container rather than of the layer: `.frame()` sizes, it does not
        // clip, and neither does a `VStack`.
        let out = composited(
            VStack(spacing: 0) {
                Text("ABCDEFGH").offset(x: 7)
            }.frame(width: 12, height: 4),
            width: 24, height: 6)
        #expect(out[0].contains("ABCDEFGH"), "the drawing was cut: \(out)")
        #expect(out[0].hasPrefix("       ABCDEFGH"), "at its displaced place: \(out)")
    }

    // MARK: - What is not content

    @Test("A drop-down inside a ScrollView is not clipped to it")
    func presentationsEscape() {
        // A surface is a window over the page. Clipping this one would be the
        // regression that reads as "the picker on the last row shows nothing".
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10, environment: environment, tuiContext: tui)
        let view = ScrollView {
            Picker("Pick", selection: Binding<Int>.constant(0)) {
                Text("Apple").tag(0)
                Text("Banana").tag(1)
                Text("Cherry").tag(2)
            }
        }.frame(width: 12, height: 2)

        func frame() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyEventDispatcher.clearHandlers()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            environment.focusManager?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            let composited = buffer.compositingOverlays(
                maxWidth: 30, maxHeight: 10, palette: environment.palette)
            tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
            tui.stateStorage.endRenderPass()
            environment.focusManager?.endRenderPass()
            return composited
        }

        _ = frame()
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 6, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 6, y: 0))
        let opened = frame().lines.map { $0.stripped }
        #expect(opened.contains { $0.contains("Cherry") },
            "the drop-down was clipped to the two-row scroller: \(opened)")
    }
}
