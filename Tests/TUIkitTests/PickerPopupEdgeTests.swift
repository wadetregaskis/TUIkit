//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PickerPopupEdgeTests.swift
//
//  A Picker sitting on the LAST visible row of a ScrollView viewport must
//  still show its drop-down when opened (flipped above / composited over
//  the rows below — wherever the compositor places it, the options must be
//  readable). Reported from live testing; this reproduces the shape.
//
//  TRIAGED PRE-EXISTING (2026-07-18): the identical repro fails at the
//  branch fork point f089ccdf — the control opens (glyph flips to ▴) but
//  the drop-down overlay never reaches the composited screen. Not a
//  windowed-rendering regression; deferred past the branch merge by
//  request. Un-disable the test when fixing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("Picker popup at the viewport edge")
struct PickerPopupEdgeTests {

    @Test(
        "Opening a Picker on the last visible row still shows the drop-down",
        .disabled("pre-existing on main (triaged at fork point f089ccdf); fix post-merge"))
    func popupOnLastVisibleRow() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<7, id: \.self) { i in Text("filler \(i)") }
                Picker("Choose", selection: Binding<Int>.constant(0)) {
                    Text("Apple").tag(0)
                    Text("Banana").tag(1)
                    Text("Cherry").tag(2)
                }
            }
        }
        .frame(height: 8)

        var palette: (any Palette)?
        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            palette = environment.palette
            let context = RenderContext(
                availableWidth: 40, availableHeight: 8,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }

        _ = frame()
        var buffer = frame()
        let lines = buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        // Auto-focus lands on the picker (the only focusable) and the reveal
        // scrolls it into view — bottom-aligned, i.e. ON the last visible row,
        // which is exactly the reported shape.
        #expect(
            lines.last?.contains("Apple") == true,
            "the collapsed picker sits on the last visible row: \(lines)")

        guard
            let pickerID = focusManager.registeredFocusIDsInActiveSection()
                .first(where: { $0.hasPrefix("picker-") })
        else {
            Issue.record(
                "no picker registered: \(focusManager.registeredFocusIDsInActiveSection())")
            return
        }
        focusManager.focus(id: pickerID)
        _ = frame()
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .enter)), "Enter opens the picker")
        buffer = frame()

        // Composite exactly as the render loop would and require the options
        // to be readable somewhere on the final screen.
        let composited = buffer.compositingOverlays(
            maxWidth: 40, maxHeight: 8, palette: palette!)
        let screen = composited.lines.map { $0.stripped }
        #expect(
            screen.contains { $0.contains("Banana") },
            "the open drop-down is visible on screen: \(screen)")
    }
}
