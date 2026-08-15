//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RedactionTests.swift
//
//  `.redacted(reason:)` — hiding content while keeping its shape.
//
//  The interesting property is not that text is replaced, but that the
//  replacement occupies exactly the cells the original did. Redaction runs
//  inside the same transform the measure uses, so a skeleton can never lay out
//  differently from the thing it stands in for — including for double-width
//  text, where counting characters instead of cells would halve the width.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Redaction")
struct RedactionTests {

    private func lines(_ view: some View, width: Int = 30, height: Int = 6) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    private func first(_ view: some View, width: Int = 30) -> String {
        (lines(view, width: width).first ?? "")
            .replacingOccurrences(of: " +$", with: "", options: .regularExpression)
    }

    private func size(_ view: some View, width: Int = 30, height: Int = 6) -> ViewSize {
        measureChild(
            view, proposal: ProposedSize(width: width, height: height),
            context: makeBareRenderContext(width: width, height: height))
    }

    // MARK: - Replacement

    @Test("placeholder replaces the glyphs")
    func placeholder() {
        let drawn = first(Text(verbatim: "Hello").redacted(reason: .placeholder))
        #expect(drawn == "░░░░░", "\(drawn.debugDescription)")
    }

    @Test("spaces survive, so the shape of the sentence does")
    func spacesSurvive() {
        let drawn = first(Text(verbatim: "ab cd").redacted(reason: .placeholder))
        #expect(drawn == "░░ ░░", "\(drawn.debugDescription)")
    }

    @Test("privacy redacts too")
    func privacy() {
        #expect(first(Text(verbatim: "hunter2").redacted(reason: .privacy)) == "░░░░░░░")
    }

    @Test("nothing is redacted without a reason")
    func noReason() {
        #expect(first(Text(verbatim: "Hello").redacted(reason: [])) == "Hello")
        #expect(first(Text(verbatim: "Hello")) == "Hello")
    }

    /// The cells-not-characters rule. One CJK character is two cells, so its
    /// skeleton is two glyphs — otherwise a redacted table column would be half
    /// the width of the real one.
    @Test("a double-width character redacts to two cells")
    func wideCharacters() {
        let drawn = first(Text(verbatim: "日本").redacted(reason: .placeholder))
        #expect(drawn == "░░░░", "two cells each: \(drawn.debugDescription)")
    }

    /// The property that matters most: redaction must not move anything.
    @Test("a redacted view measures exactly as wide as the real one")
    func layoutIsPreserved() {
        for content in ["Hello, world", "日本語のテキスト", "a b c", "ﬁt"] {
            let plain = size(Text(verbatim: content))
            let hidden = size(Text(verbatim: content).redacted(reason: .placeholder))
            #expect(
                plain.width == hidden.width && plain.height == hidden.height,
                "\(content): \(plain) vs \(hidden)")
        }
    }

    /// Measure and render must agree, or the skeleton is clipped or padded.
    @Test("the measured width is the width actually drawn")
    func measureMatchesRender() {
        let view = Text(verbatim: "日本語 abc").redacted(reason: .placeholder)
        let drawn = first(view)
        #expect(size(view).width == drawn.strippedLength, "\(drawn.debugDescription)")
    }

    // MARK: - Cascade

    @Test("redaction reaches every text beneath it")
    func cascades() {
        let drawn = lines(
            VStack {
                Text(verbatim: "one")
                Text(verbatim: "two")
            }
            .redacted(reason: .placeholder)
        ).prefix(2).map {
            $0.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
        }
        #expect(drawn == ["░░░", "░░░"], "\(drawn)")
    }

    @Test("unredacted opts one view back out")
    func unredacted() {
        let drawn = lines(
            VStack {
                Text(verbatim: "one")
                Text(verbatim: "two").unredacted()
            }
            .redacted(reason: .placeholder)
        ).prefix(2).map {
            $0.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
        }
        #expect(drawn == ["░░░", "two"], "\(drawn)")
    }

    /// `redacted(reason:)` ADDS a reason, as SwiftUI documents — an inner call
    /// must not drop the outer one.
    @Test("reasons accumulate through nesting")
    func reasonsAccumulate() {
        let sink = ReasonSink()
        _ = renderToBuffer(
            Probe(sink: sink)
                .redacted(reason: .privacy)
                .redacted(reason: .placeholder),
            context: makeBareRenderContext(width: 20, height: 4))
        #expect(sink.seen?.contains(.placeholder) == true)
        #expect(sink.seen?.contains(.privacy) == true, "the outer reason survived")
    }

    private final class ReasonSink: @unchecked Sendable {
        var seen: RedactionReasons?
    }

    private struct Probe: View {
        @Environment(\.redactionReasons) private var reasons
        let sink: ReasonSink

        var body: some View {
            sink.seen = reasons
            return Text(verbatim: "probe")
        }
    }

    // MARK: - Invalidated

    /// `.invalidated` is the reason that does NOT replace anything: stale data
    /// is still readable, so it is dimmed instead.
    @Test("invalidated keeps the text and dims it")
    func invalidated() {
        let plain = renderToBuffer(
            Text(verbatim: "42"),
            context: makeBareRenderContext(width: 20, height: 3)
        ).lines.joined()
        let stale = renderToBuffer(
            Text(verbatim: "42").redacted(reason: .invalidated),
            context: makeBareRenderContext(width: 20, height: 3)
        ).lines.joined()

        #expect(stale.stripped.contains("42"), "the value is still readable")
        #expect(stale != plain, "but it is styled differently")
        // SGR parameters are netted into one sequence, so dim arrives as the
        // leading `2` of a combined run rather than a standalone `ESC[2m`.
        #expect(
            stale.contains("\u{1B}[2;") || stale.contains("\u{1B}[2m"),
            "dim SGR: \(stale.debugDescription)")
    }
}
