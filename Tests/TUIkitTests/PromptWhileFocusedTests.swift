//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PromptWhileFocusedTests.swift
//
//  A field's prompt stays visible while the field is FOCUSED and still empty —
//  it only goes away once there is text to read. That is what SwiftUI and
//  AppKit do: focusing a field does not blank its placeholder.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A prompt survives focus until there is text")
struct PromptWhileFocusedTests {

    /// Renders `view`, settling a few frames so focus registration lands.
    private func lines(of view: some View, width: Int = 30) -> [String] {
        let tui = TUIContext()
        let fm = FocusManager()
        var rendered: [String] = []
        for _ in 0..<3 {
            var env = EnvironmentValues()
            env.focusManager = fm
            env.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: width, availableHeight: 4, environment: env, tuiContext: tui)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            fm.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            fm.endRenderPass()
            tui.stateStorage.endRenderPass()
            rendered = buffer.lines.map(\.stripped)
        }
        return rendered
    }

    @Test("an empty focused TextField still shows its prompt")
    func focusedEmptyFieldShowsPrompt() {
        // The sole focusable control, so it holds focus once settled.
        let rendered = lines(
            of: TextField("", text: .constant(""), prompt: Text("you@example.com")))
        #expect(
            rendered.contains { $0.contains("you@example.com") },
            "a focused, empty field must still show its prompt: \(rendered)")
    }

    @Test("typing displaces the prompt")
    func textReplacesPrompt() {
        let rendered = lines(
            of: TextField("", text: .constant("hi"), prompt: Text("you@example.com")))
        #expect(rendered.contains { $0.contains("hi") }, "the text shows: \(rendered)")
        #expect(
            !rendered.contains { $0.contains("you@example.com") },
            "the prompt must give way to real content: \(rendered)")
    }

    @Test("SecureField behaves the same way")
    func secureFieldMatches() {
        let rendered = lines(
            of: SecureField("", text: .constant(""), prompt: Text("required")))
        #expect(
            rendered.contains { $0.contains("required") },
            "a focused, empty SecureField must still show its prompt: \(rendered)")
    }
}
