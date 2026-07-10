//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModalTabViewInteractionTests.swift
//
//  A TabView hosted inside a `.modal` dialog (the ColorPicker's layout) must
//  stay interactive: clicking a tab header switches tabs, and arrow keys on
//  the focused tab strip do too. Regression probe for "the colour-picker
//  dialog's tabs are dead".
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("TabView inside a modal dialog")
struct ModalTabViewInteractionTests {

    private final class SelectionBox {
        var value = 0
        var binding: Binding<Int> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    private func makeEnvironment(tui: TUIContext, focus: FocusManager) -> EnvironmentValues {
        var env = EnvironmentValues()
        env.focusManager = focus
        env.stateStorage = tui.stateStorage
        env.lifecycle = tui.lifecycle
        env.keyEventDispatcher = tui.keyEventDispatcher
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        env.renderCache = tui.renderCache
        env.preferenceStorage = tui.preferences
        env.terminalWidth = 60
        env.terminalHeight = 20
        return env
    }

    @Test("Clicking a tab header inside a modal switches tabs")
    func clickSwitchesTabs() {
        let tui = TUIContext()
        let focus = FocusManager()
        let env = makeEnvironment(tui: tui, focus: focus)
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        let selection = SelectionBox()

        let view = Text("Page")
            .modal(isPresented: .constant(true)) {
                TabView(selection: selection.binding) {
                    Tab("First", value: 0) { Text("FIRST BODY") }
                    Tab("Second", value: 1) { Text("SECOND BODY") }
                }
            }

        func renderComposited() -> FrameBuffer {
            let context = RenderContext(
                availableWidth: 60, availableHeight: 20, environment: env, tuiContext: tui)
            focus.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focus.endRenderPass()
            return buffer.compositingOverlays(maxWidth: 60, maxHeight: 20, palette: env.palette)
        }

        let composited = renderComposited()
        let screen = composited.lines.map(\.stripped).joined(separator: "\n")
        #expect(screen.contains("FIRST BODY"), "the dialog's first tab shows: \(screen)")

        // Find the "Second" tab header on screen and click it.
        guard let (row, column) = locate("Second", in: composited) else {
            Issue.record("could not find the Second tab header on screen:\n\(screen)")
            return
        }
        dispatcher.setRegions(composited.hitTestRegions)
        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: column, y: row))
        #expect(consumed, "the tab-header click lands on a hit region")
        #expect(selection.value == 1, "clicking the Second header selects it")

        let after = renderComposited().lines.map(\.stripped).joined(separator: "\n")
        #expect(after.contains("SECOND BODY"), "the second tab renders after the click: \(after)")
    }

    /// The (y, x) of `needle`'s first character in the buffer, or nil.
    private func locate(_ needle: String, in buffer: FrameBuffer) -> (row: Int, column: Int)? {
        for (row, line) in buffer.lines.enumerated() {
            let stripped = line.stripped
            if let range = stripped.range(of: needle) {
                return (row, stripped.distance(from: stripped.startIndex, to: range.lowerBound))
            }
        }
        return nil
    }

    @Test("Clicking a ColorPickerPanel tab header switches editors")
    func colorPickerPanelTabs() {
        let tui = TUIContext()
        let focus = FocusManager()
        var env = makeEnvironment(tui: tui, focus: focus)
        env.terminalWidth = 100
        env.terminalHeight = 34
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        final class ColourBox {
            var colour = Color.rgb(200, 60, 60)
            var presented = true
        }
        let box = ColourBox()
        let view = Text("Page")
            .modal(isPresented: Binding(get: { box.presented }, set: { box.presented = $0 })) {
                ColorPickerPanel(
                    "Accent",
                    selection: Binding(get: { box.colour }, set: { box.colour = $0 }),
                    isPresented: Binding(get: { box.presented }, set: { box.presented = $0 }))
            }

        func renderComposited() -> FrameBuffer {
            let context = RenderContext(
                availableWidth: 100, availableHeight: 34, environment: env, tuiContext: tui)
            focus.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focus.endRenderPass()
            return buffer.compositingOverlays(maxWidth: 100, maxHeight: 34, palette: env.palette)
        }

        let composited = renderComposited()
        let screen = composited.lines.map(\.stripped).joined(separator: "\n")
        guard let (row, column) = locate("HSL", in: composited) else {
            Issue.record("could not find the HSL tab header:\n\(screen)")
            return
        }
        dispatcher.setRegions(composited.hitTestRegions)
        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: column + 1, y: row))
        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: column + 1, y: row))
        #expect(consumed, "the HSL tab-header click lands on a hit region")

        let after = renderComposited().lines.map(\.stripped).joined(separator: "\n")
        // The HSL editor's channel rows are labelled H/S/L with a degree
        // read-out for hue — markers the RGB editor lacks.
        #expect(after.contains("H ◀"), "the HSL editor renders after clicking its tab: \(after)")
        #expect(!after.contains("R ◀"), "the RGB editor is gone: \(after)")
    }

    /// A minimal in-modal @State probe: a counter button inside the dialog.
    private struct CounterDialog: View {
        @State private var count = 0
        var body: some View {
            VStack {
                Text("COUNT \(count)")
                Button("Increment") { count += 1 }
            }
        }
    }

    @Test("@State inside modal content persists across frames")
    func modalStatePersists() {
        let tui = TUIContext()
        let focus = FocusManager()
        let env = makeEnvironment(tui: tui, focus: focus)
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        let view = Text("Page")
            .modal(isPresented: .constant(true)) { CounterDialog() }

        func renderComposited() -> FrameBuffer {
            let context = RenderContext(
                availableWidth: 60, availableHeight: 20, environment: env, tuiContext: tui)
            focus.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focus.endRenderPass()
            return buffer.compositingOverlays(maxWidth: 60, maxHeight: 20, palette: env.palette)
        }

        let first = renderComposited()
        guard let (row, column) = locate("Increment", in: first) else {
            Issue.record("no Increment button on screen")
            return
        }
        dispatcher.setRegions(first.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: column, y: row))

        let after = renderComposited().lines.map(\.stripped).joined(separator: "\n")
        #expect(after.contains("COUNT 1"), "the in-modal counter advanced: \(after)")
    }
}
