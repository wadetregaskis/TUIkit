//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModalContentHeightTests.swift
//
//  A presented modal/alert is built against the CONTENT AREA (screen minus app
//  header and status bar), not the full terminal height. The root compositor
//  clamps overlays to that content area top-biased, so a dialog built against
//  the full height loses its bottom rows — the footer (Done/Cancel) and bottom
//  border — under the status bar ("the gradient editor slides under the status
//  bar on short terminals"). These pin that the footer survives on a terminal
//  too short to hold the dialog's natural height.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Modal/alert render against the content area, not full height")
struct ModalContentHeightTests {

    /// Renders `view` on a short terminal — total height `terminalH`, of which
    /// `contentH` is the overlay content area (the rest is chrome) — and
    /// composites overlays exactly as `RenderLoop` does (clamped to `contentH`).
    private func renderShort<V: View>(_ view: V, terminalH: Int, contentH: Int) -> FrameBuffer {
        var env = EnvironmentValues()
        env.terminalWidth = 80
        env.terminalHeight = terminalH
        env.overlayContentHeight = contentH
        let context = RenderContext(
            availableWidth: 80, availableHeight: contentH,
            environment: env, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        return buffer.compositingOverlays(
            maxWidth: 80, maxHeight: contentH, palette: context.environment.palette)
    }

    @Test("A tall gradient editor keeps its Done/Cancel footer above the status bar")
    func gradientEditorFooterSurvives() {
        let stops = Binding.constant([Color.rgb(255, 80, 80), Color.rgb(80, 160, 255)])
        let view = Text("base")
            .modal(isPresented: .constant(true)) {
                GradientEditorPanel(stops: stops, isPresented: .constant(true))
            }
        // 20-row terminal, 14-row content area (6 rows of header/status chrome).
        // The gradient editor's natural height (~28-30) far exceeds 14, so a
        // dialog built against the full 20 rows would land its footer at rows
        // ~18-19 and lose it to the 14-row clamp.
        let buffer = renderShort(view, terminalH: 20, contentH: 14)
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(text.contains("Done"), "Done button stays on-screen:\n\(text)")
        #expect(text.contains("Cancel"), "Cancel button stays on-screen:\n\(text)")
        #expect(
            buffer.lines.count <= 14,
            "the composited overlay stays within the content area, got \(buffer.lines.count)")
    }

    @Test("A tall alert keeps its action button above the status bar")
    func alertFooterSurvives() {
        // A long message wraps to many lines, pushing the alert's natural height
        // well past the content area — so on the full-height path the OK button
        // lands below the content boundary and is clamped away.
        let longMessage = String(repeating: "This is a long alert message. ", count: 24)
        let view = Text("base")
            .alert("Heads up", isPresented: .constant(true)) {
                Button("OK") {}
            } message: {
                Text(longMessage)
            }
        let buffer = renderShort(view, terminalH: 24, contentH: 12)
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")
        #expect(text.contains("OK"), "the alert's action button stays on-screen:\n\(text)")
        #expect(
            buffer.lines.count <= 12,
            "the composited alert stays within the content area, got \(buffer.lines.count)")
    }
}
