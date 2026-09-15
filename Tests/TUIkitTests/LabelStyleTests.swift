//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabelStyleTests.swift
//
//  ``LabelStyle`` — which of a ``Label``'s two halves is shown, and how they
//  are arranged.
//
//  The terminal-specific part is the fallback: an icon-only style cannot be
//  taken literally when the icon is an SF Symbol the terminal has no glyph for,
//  because the label would render as nothing at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Label styles")
struct LabelStyleTests {

    /// The rendered text, with the padding a stack adds to square its rows off
    /// removed — this is about which halves appear, not column widths.
    private func text(_ view: some View, width: Int = 30) -> String {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: 4))
            .lines
            .map {
                $0.stripped.replacingOccurrences(
                    of: " +$", with: "", options: .regularExpression)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A label built from two plain views, so neither half depends on SF
    /// Symbols being resolvable on the host.
    private func label() -> Label<Text, Text> {
        Label { Text(verbatim: "Inbox") } icon: { Text(verbatim: "*") }
    }

    @Test("the default style puts the icon before the title")
    func automatic() {
        #expect(text(label()) == "* Inbox")
    }

    @Test("titleOnly drops the icon")
    func titleOnly() {
        #expect(text(label().labelStyle(.titleOnly)) == "Inbox")
    }

    @Test("iconOnly drops the title")
    func iconOnly() {
        #expect(text(label().labelStyle(.iconOnly)) == "*")
    }

    @Test("titleAndIcon shows both")
    func titleAndIcon() {
        #expect(text(label().labelStyle(.titleAndIcon)) == "* Inbox")
    }

    /// The style is an environment value, so it reaches every label beneath it
    /// — the reason to have it at all rather than a per-label parameter.
    @Test("a style set on a container reaches every label inside")
    func cascades() {
        let drawn = text(
            VStack {
                label()
                label()
            }
            .labelStyle(.titleOnly))
        #expect(drawn == "Inbox\nInbox", "\(drawn.debugDescription)")
    }

    @Test("the innermost style wins")
    func innermostWins() {
        let drawn = text(
            VStack {
                label().labelStyle(.iconOnly)
                label()
            }
            .labelStyle(.titleOnly))
        #expect(drawn == "*\nInbox", "\(drawn.debugDescription)")
    }

    /// An unresolvable SF Symbol leaves the label with no drawable icon. Taking
    /// `.iconOnly` literally would render an empty label; showing the title is
    /// the lesser evil, and is what both ``Label`` and the style agree on.
    @Test("iconOnly falls back to the title when the icon cannot be drawn")
    func iconOnlyFallsBack() {
        let unresolvable = Label<Text, Text>(
            title: Text(verbatim: "Inbox"), icon: Text(verbatim: ""), iconIsVisible: false)
        #expect(text(unresolvable.labelStyle(.iconOnly)) == "Inbox")
        // …and the default style already omitted the gap in that case.
        #expect(text(unresolvable) == "Inbox")
    }

    /// A style is any type conforming to the protocol, as in SwiftUI — not a
    /// closed set, because a terminal can compose two views however it likes.
    @Test("a custom style can rearrange the halves")
    func customStyle() {
        struct Reversed: LabelStyle {
            func makeBody(configuration: Configuration) -> some View {
                HStack(spacing: 1) {
                    configuration.title
                    configuration.icon
                }
            }
        }
        #expect(text(label().labelStyle(Reversed())) == "Inbox *")
    }

    /// Labels are ordinary views: what wraps them still reaches inside,
    /// whichever style is in force.
    @Test("modifiers still reach a styled label")
    func modifiersPropagate() {
        let plain = renderToBuffer(
            label().labelStyle(.titleOnly),
            context: makeBareRenderContext(width: 30, height: 4)
        ).lines.joined()
        let styled = renderToBuffer(
            label().labelStyle(.titleOnly).foregroundStyle(.ansi(.red)),
            context: makeBareRenderContext(width: 30, height: 4)
        ).lines.joined()
        #expect(styled != plain)
    }
}
