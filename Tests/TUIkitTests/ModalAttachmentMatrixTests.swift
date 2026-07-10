//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModalAttachmentMatrixTests.swift
//
//  The `.modal` presentation contract, probed across ATTACHMENT POINTS: a
//  presented modal must dim the whole screen, draw centred, and grab focus
//  no matter where in the view tree the `.modal` modifier sits. The existing
//  modal tests all attach at the root — these probe the compositing paths
//  between an arbitrary attachment and the root (stacks, ScrollView
//  windowing, List rows, TabView, NavigationSplitView), where an emitted
//  OverlayLayer can be dropped or displaced on its way up.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Modal attachment matrix (dim/centre/focus from any attachment)")
struct ModalAttachmentMatrixTests {

    // MARK: - Harness

    private final class BoolBox {
        var v = false
        var binding: Binding<Bool> { Binding(get: { self.v }, set: { self.v = $0 }) }
    }

    private struct RenderResult {
        var root: FrameBuffer
        var composited: FrameBuffer
        var focus: FocusManager
    }

    private static let width = 60
    private static let height = 20

    /// Renders `view` full-screen with live runtime services (focus manager +
    /// per-frame registries) and composites overlays the way `RenderLoop` does.
    private func render(
        _ view: some View, focus: FocusManager = FocusManager(), tui: TUIContext = TUIContext()
    ) -> RenderResult {
        var env = EnvironmentValues()
        env.focusManager = focus
        env.applyRuntimeServices(from: tui)
        env.terminalWidth = Self.width
        env.terminalHeight = Self.height
        let context = RenderContext(
            availableWidth: Self.width, availableHeight: Self.height,
            environment: env, tuiContext: tui)
        focus.beginRenderPass()
        let root = renderToBuffer(view, context: context)
        focus.endRenderPass()
        let composited = root.compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: env.palette)
        return RenderResult(root: root, composited: composited, focus: focus)
    }

    /// Asserts the three-part presentation contract on a rendered result.
    private func expectPresented(
        _ result: RenderResult, label: String, level: OverlayLevel = .modal,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        // 1. The modal overlay reached the root buffer (dim + float happen there).
        let modalLayers = result.root.overlays.filter { $0.level == level }
        #expect(
            !modalLayers.isEmpty,
            "[\(label)] the modal OverlayLayer must reach the root buffer",
            sourceLocation: sourceLocation)
        #expect(
            modalLayers.allSatisfy { $0.dimsBackground },
            "[\(label)] the modal layer dims the background",
            sourceLocation: sourceLocation)

        // 2. It composites centred: a centred layer's offset is a POST-CENTRE
        //    delta (drag), which must still be zero — intermediate containers
        //    must not have folded the attachment's position into it.
        for layer in modalLayers {
            #expect(
                layer.offsetX == 0 && layer.offsetY == 0,
                "[\(label)] undragged modal is centred; offset (\(layer.offsetX), \(layer.offsetY)) would displace it",
                sourceLocation: sourceLocation)
        }

        // 3. The dialog's content is actually on screen.
        let screen = result.composited.lines.joined(separator: "\n").stripped
        #expect(
            screen.contains("MODAL BODY"),
            "[\(label)] the dialog's content draws on screen",
            sourceLocation: sourceLocation)

        // 4. Focus: the modal section grabs input and its control is focused.
        #expect(
            result.focus.activeSectionIsModal,
            "[\(label)] the modal's section is active + input-grabbing",
            sourceLocation: sourceLocation)
        #expect(
            result.focus.currentFocusedID == "modal-ok",
            "[\(label)] the modal's control is focused; got \(result.focus.currentFocusedID ?? "nil")",
            sourceLocation: sourceLocation)
    }

    /// The standard dialog content every probe presents.
    private func dialog() -> some View {
        VStack {
            Text("MODAL BODY")
            Button("OK") {}.focusID("modal-ok")
        }
    }

    // MARK: - Probes

    @Test("Baseline: attached at the root")
    func attachedAtRoot() {
        let view = VStack {
            Text("Page line 1")
            Button("Page") {}.focusID("page-button")
        }
        .modal(isPresented: .constant(true)) { dialog() }
        expectPresented(render(view), label: "root")
    }

    @Test("Attached to a child partway down a VStack")
    func attachedToNestedChild() {
        let view = VStack {
            Text("Row 0")
            Text("Row 1")
            Text("Row 2")
            Text("Trigger")
                .modal(isPresented: .constant(true)) { dialog() }
            Button("Page") {}.focusID("page-button")
        }
        expectPresented(render(view), label: "nested-child")
    }

    @Test("Attached deep in a tall page (large accumulated offset)")
    func attachedDeepInTallPage() {
        let view = VStack(spacing: 0) {
            ForEach(0..<15, id: \.self) { Text("Filler \($0)") }
            Text("Trigger")
                .modal(isPresented: .constant(true)) { dialog() }
        }
        expectPresented(render(view), label: "deep-tall")
    }

    @Test("Attached to the trailing element of an HStack")
    func attachedInHStack() {
        let view = HStack {
            Text("Leading content, fairly wide")
            Text("Trigger")
                .modal(isPresented: .constant(true)) { dialog() }
        }
        expectPresented(render(view), label: "hstack-trailing")
    }

    @Test("Attached inside ScrollView content (unscrolled)")
    func attachedInScrollViewUnscrolled() {
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Trigger")
                    .modal(isPresented: .constant(true)) { dialog() }
                ForEach(0..<30, id: \.self) { Text("Filler \($0)") }
            }
        }
        .frame(height: 10)
        expectPresented(render(view), label: "scrollview-top")
    }

    @Test("Attached inside ScrollView content, scrolled past the attachment")
    func attachedInScrollViewScrolledAway() {
        let presented = BoolBox()
        let focus = FocusManager()
        let tui = TUIContext()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Trigger")
                    .modal(isPresented: presented.binding) { dialog() }
                ForEach(0..<30, id: \.self) { i in
                    Button("Row \(i)") {}.focusID("row-\(i)")
                }
            }
        }
        .frame(height: 8)

        // Scroll the attachment out of the viewport (focus snap), THEN present.
        _ = render(view, focus: focus, tui: tui)
        focus.focus(id: "row-25")
        _ = render(view, focus: focus, tui: tui)
        presented.v = true
        let result = render(view, focus: focus, tui: tui)
        expectPresented(result, label: "scrollview-scrolled")
    }

    @Test("Attached to row content inside a List")
    func attachedInListRow() {
        let view = List(selection: .constant(String?.none)) {
            ForEach(["alpha", "beta", "gamma"], id: \.self) { name in
                if name == "beta" {
                    Text(name)
                        .modal(isPresented: .constant(true)) { dialog() }
                } else {
                    Text(name)
                }
            }
        }
        .frame(height: 8)
        expectPresented(render(view), label: "list-row")
    }

    @Test("Attached inside the active TabView tab")
    func attachedInTabViewTab() {
        let view = TabView(selection: .constant(0)) {
            Tab("First", value: 0) {
                Text("Trigger")
                    .modal(isPresented: .constant(true)) { dialog() }
            }
            Tab("Second", value: 1) {
                Text("Other")
            }
        }
        expectPresented(render(view), label: "tabview-tab")
    }

    @Test("Attached inside NavigationSplitView detail")
    func attachedInSplitViewDetail() {
        let view = NavigationSplitView {
            VStack {
                Text("Sidebar")
                Button("Item") {}.focusID("sidebar-item")
            }
        } detail: {
            Text("Trigger")
                .modal(isPresented: .constant(true)) { dialog() }
        }
        expectPresented(render(view), label: "splitview-detail")
    }

    @Test("Attached inside a bordered container (Box)")
    func attachedInsideBox() {
        let view = Box {
            Text("Trigger")
                .modal(isPresented: .constant(true)) { dialog() }
        }
        expectPresented(render(view), label: "box")
    }

    // MARK: - Alerts (separate modifier, same contract)

    /// `.alert` renders its actions inside the alert layer — reuse the OK
    /// button as the focus probe, and the title as the visibility probe.
    private func alertProbe(on trigger: some View) -> some View {
        trigger.alert("MODAL BODY", isPresented: .constant(true)) {
            Button("OK") {}.focusID("modal-ok")
        } message: {
            Text("Something happened.")
        }
    }

    @Test("Alert attached to a child partway down a VStack")
    func alertAttachedToNestedChild() {
        let view = VStack {
            Text("Row 0")
            Text("Row 1")
            alertProbe(on: Text("Trigger"))
            Button("Page") {}.focusID("page-button")
        }
        expectPresented(render(view), label: "alert-nested", level: .alert)
    }

    @Test("Alert attached to row content inside a List")
    func alertAttachedInListRow() {
        let view = List(selection: .constant(String?.none)) {
            ForEach(["alpha", "beta", "gamma"], id: \.self) { name in
                if name == "beta" {
                    alertProbe(on: Text(name))
                } else {
                    Text(name)
                }
            }
        }
        .frame(height: 8)
        expectPresented(render(view), label: "alert-list-row", level: .alert)
    }
}
