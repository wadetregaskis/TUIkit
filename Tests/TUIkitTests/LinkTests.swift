//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LinkTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitView

/// Captures the URL an ``OpenURLAction`` was asked to open. A reference type so
/// the action's `@Sendable` handler can record into it; used only synchronously
/// on the main actor here.
private final class URLSink: @unchecked Sendable {
    var url: URL?
}

/// Coverage for ``Link`` and ``OpenURLAction``: the action fires its handler,
/// the link renders its label, and activating a focused link opens the
/// destination through the environment action — while a disabled link stays
/// inert.
@MainActor
@Suite("Link")
struct LinkTests {

    private let url = URL(string: "https://example.com/docs")!

    @Test("OpenURLAction invokes its handler with the URL")
    func openURLActionFires() {
        let sink = URLSink()
        let action = OpenURLAction { sink.url = $0 }
        action(url)
        #expect(sink.url == url)
    }

    @Test("A link renders its title as styled text")
    func rendersTitle() {
        let buffer = renderToBuffer(
            Link("Docs", destination: url), context: makeRenderContext(width: 20, height: 3))
        let text = buffer.lines.map { $0.stripped }.joined()
        #expect(text.contains("Docs"))
        // Styled (accent + underline) → the raw output carries SGR escapes.
        #expect(buffer.lines.joined().contains("\u{1B}["))
    }

    @Test("Activating a focused link opens its destination")
    func activationOpens() {
        let sink = URLSink()
        let context = makeRenderContext(width: 20, height: 3)
        let view = Link("Docs", destination: url)
            .environment(\.openURL, OpenURLAction { sink.url = $0 })
        _ = renderToBuffer(view, context: context)  // registers + auto-focuses the link
        let handled = context.environment.focusManager!.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(handled)
        #expect(sink.url == url)
    }

    @Test("A disabled link opens nothing when activated")
    func disabledIsInert() {
        let sink = URLSink()
        let context = makeRenderContext(width: 20, height: 3)
        let view = Link("Docs", destination: url)
            .disabled(true)
            .environment(\.openURL, OpenURLAction { sink.url = $0 })
        _ = renderToBuffer(view, context: context)
        _ = context.environment.focusManager!.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(sink.url == nil)
    }

    @Test("A view-builder label link also opens on activation")
    func viewBuilderLabel() {
        let sink = URLSink()
        let context = makeRenderContext(width: 20, height: 3)
        let view = Link(destination: url) { Text("Site") }
            .environment(\.openURL, OpenURLAction { sink.url = $0 })
        let text = renderToBuffer(view, context: context).lines.map { $0.stripped }.joined()
        #expect(text.contains("Site"))
        _ = context.environment.focusManager!.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(sink.url == url)
    }
}
