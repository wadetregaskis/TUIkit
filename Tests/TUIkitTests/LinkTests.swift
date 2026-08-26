//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Claims auto-focus so the link under test renders unfocused — a focused
    /// control suppresses its hover affordance, and the two renders would
    /// otherwise be identical for the wrong reason.
    private final class LinkFocusSentinel: Focusable {
        let focusID = "link-hover-sentinel"
        func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
    }

    /// The one affordance a link has. SwiftUI's `Link` is accent-coloured and
    /// leaves hover to the pointer cursor; a terminal has no cursor to change,
    /// so the colour does the work.
    ///
    /// The accent reaches the label through the button's TEXT STYLE rather than
    /// a `.foregroundStyle` on the label itself: a colour written on the label
    /// beats the one the style hands down, and it is the style that knows about
    /// the pointer. Routed the other way this test fails.
    @Test("A link lifts its colour under the pointer")
    func hoverLiftsTheLinkColour() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 40, height: 4)
            let dispatcher = context.environment.mouseEventDispatcher!
            dispatcher.setActiveSupport(.full)
            context.environment.focusManager!.register(LinkFocusSentinel())

            let view = Link("swift.org", destination: url)
            let before = renderToBuffer(view, context: context).lines.joined()
            let regions = renderToBuffer(view, context: context).hitTestRegions
            dispatcher.setRegions(regions)
            guard let region = regions.first else {
                Issue.record("expected a hit-test region from Link")
                return
            }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .none, phase: .moved,
                    x: region.offsetX + 1, y: region.offsetY))
            let after = renderToBuffer(view, context: context).lines.joined()

            let palette = context.environment.palette
            func code(_ color: Color) -> String {
                let rgb = color.resolve(with: palette).rgbComponents!
                return "38;2;\(rgb.red);\(rgb.green);\(rgb.blue)"
            }
            #expect(before.contains(code(palette.accent)), "accent at rest: \(before)")
            #expect(
                after.contains(code(palette.hoveredForeground(palette.accent))),
                "lifted under the pointer: \(after)")
        }
    }

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

    // MARK: - Underline

    /// Whether the raw output carries an underline SGR (code `4`, emitted first
    /// in a run, so the escape starts with `[4`). The accent foreground is
    /// `38;2;…`, so `[4` never appears spuriously.
    private func isUnderlined(_ raw: String) -> Bool {
        raw.contains("\u{1B}[4;") || raw.contains("\u{1B}[4m")
    }

    @Test("A view-builder-labelled link is underlined by default")
    func viewBuilderLabelUnderlinedByDefault() {
        let raw = renderToBuffer(
            Link(destination: url) { Text("Docs") },
            context: makeRenderContext(width: 20, height: 3)
        ).lines.joined()
        #expect(isUnderlined(raw), "a custom-label link underlines by default: \(raw.debugDescription)")
    }

    @Test("A string-titled link is underlined by default")
    func stringLinkUnderlinedByDefault() {
        let raw = renderToBuffer(
            Link("Docs", destination: url), context: makeRenderContext(width: 20, height: 3)
        ).lines.joined()
        #expect(isUnderlined(raw))
    }

    @Test(".linkUnderline(false) removes the underline across the subtree")
    func linkUnderlineOffRemovesUnderline() {
        let raw = renderToBuffer(
            Link("Docs", destination: url).linkUnderline(false),
            context: makeRenderContext(width: 20, height: 3)
        ).lines.joined()
        #expect(!isUnderlined(raw), "no underline SGR when opted out: \(raw.debugDescription)")
    }

    #if canImport(AppKit)
    // The SF Symbol glyph only resolves on Apple platforms with the right font;
    // off Apple the label is title-only, so there is nothing to check.
    @Test("A link underlines a Label's title but not its SF Symbol icon")
    func linkUnderlinesTitleNotSymbol() {
        guard let glyph = SFSymbol.glyph(named: "swift") else { return }
        let raw = renderToBuffer(
            Link(destination: url) { Label("apple/swift", systemImage: "swift") },
            context: makeRenderContext(width: 30, height: 3)
        ).lines.joined()
        // The title is still underlined…
        #expect(isUnderlined(raw), "the title should be underlined: \(raw.debugDescription)")
        // …but no underline SGR is active up to and including the symbol glyph.
        guard let symbolRange = raw.range(of: String(glyph)) else {
            Issue.record("symbol glyph not present in output")
            return
        }
        let throughSymbol = String(raw[..<symbolRange.upperBound])
        #expect(
            !isUnderlined(throughSymbol),
            "the SF Symbol glyph must not be underlined: \(throughSymbol.debugDescription)")
    }
    #endif

    // MARK: - OpenURLAction.Result

    /// The point of a handler returning something: it can DECLINE. An app
    /// intercepting its own scheme has to be able to hand every other URL on
    /// without re-implementing the system opener.
    @Test("A handler can handle one scheme and hand the rest to the system")
    func systemActionDefers() {
        let sink = URLSink()
        let action = OpenURLAction { url -> OpenURLAction.Result in
            sink.url = url
            return url.scheme == "myapp" ? .handled : .systemAction
        }

        // Asked of the action, not recomputed here: deferring actually LAUNCHES
        // the system opener, so `result(for:)` is the seam that lets a case see
        // the decision without one.
        let mine = URL(string: "myapp://thing")!
        #expect(action.result(for: mine) == .handled)
        #expect(sink.url == mine, "the handler saw the URL it was asked about")

        let theirs = URL(string: "https://example.com")!
        #expect(action.result(for: theirs) == .systemAction)
        #expect(sink.url == theirs)
    }

    @Test("The default action is the system opener, stated as such")
    func defaultDefersToTheSystem() {
        let action = EnvironmentValues().openURL
        #expect(action.result(for: URL(string: "https://example.com")!) == .systemAction)
    }

    @Test("The three dispositions are distinct, and a rewrite carries its URL")
    func resultCases() {
        #expect(OpenURLAction.Result.handled != OpenURLAction.Result.discarded)
        #expect(OpenURLAction.Result.handled != OpenURLAction.Result.systemAction)
        #expect(OpenURLAction.Result.discarded != OpenURLAction.Result.systemAction)
        let rewritten = URL(string: "https://example.com/canonical")!
        #expect(OpenURLAction.Result.systemAction(rewritten) != .systemAction)
        #expect(OpenURLAction.Result.systemAction(rewritten) == .systemAction(rewritten))
    }

    /// The Void handler form is TUIkit's own, and must keep winning for a
    /// closure that returns nothing — otherwise every existing override
    /// stops compiling.
    @Test("A Void handler is still a handler")
    func voidHandlerStillCompiles() {
        let sink = URLSink()
        let action = OpenURLAction { sink.url = $0 }
        action(URL(string: "https://example.com")!)
        #expect(sink.url?.absoluteString == "https://example.com")
    }
}
