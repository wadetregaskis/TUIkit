//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MemoVerifierDrawsFreshTests.swift
//
//  The memo verifiers are a debugging aid for a view that fails to update: with
//  them on, what the cache serves is rendered or measured again, and the FRESH
//  result is what the frame uses — so a view the cache was serving stale starts
//  updating, and the report names it. These pin both halves: it draws fresh,
//  and it still says what it found.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A card whose `==` ignores the text it draws — the lie the cache cannot see.
private struct TitledCard: View, @preconcurrency Equatable {
    let title: String
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View { Text(verbatim: text) }
}

/// Frames of the real loop's lifecycle over one render cache.
@MainActor
private final class VerifierLoop {
    let tui = TUIContext()

    func frame(_ view: some View, width: Int = 30) -> [String] {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(
            availableWidth: width, availableHeight: 4, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map(\.stripped)
    }
}

@MainActor
@Suite("The memo verifiers draw what a frame without the cache would", .serialized)
struct MemoVerifierDrawsFreshTests {
    /// Draws a card, then the same title over new text, and returns the second
    /// frame's first line and what the verifier reported.
    private func servedText(verifying: Bool) -> (line: String, reports: [String]) {
        let was = RenderCache.verifiesRenderMemo
        defer { RenderCache.verifiesRenderMemo = was }
        RenderCache.verifiesRenderMemo = verifying
        let loop = VerifierLoop()
        _ = loop.frame(TitledCard(title: "t", text: "old").equatable())
        _ = loop.frame(TitledCard(title: "t", text: "old").equatable())
        let line = loop.frame(TitledCard(title: "t", text: "new").equatable()).first ?? ""
        return (line, loop.tui.renderCache.renderMemoMismatches)
    }

    @Test("Without the verifier, a view whose == hides a change is served stale")
    func staleWithoutTheVerifier() {
        let served = servedText(verifying: false)
        #expect(served.line.hasPrefix("old"), "precondition: the cache serves the stale card: \(served.line)")
        #expect(served.reports.isEmpty)
    }

    @Test("With the verifier, it is drawn fresh, and reported")
    func freshAndReportedWithTheVerifier() {
        let served = servedText(verifying: true)
        #expect(served.line.hasPrefix("new"), "the verifier drew the stale buffer: \(served.line)")
        #expect(
            served.reports.contains { $0.contains("TitledCard") },
            "the stale serve went unreported: \(served.reports)")
    }

    /// The size half: a card beside a bar, whose served width is the old
    /// text's; under the measure verifier the bar moves to where the new
    /// text's width puts it.
    @Test("With the measure verifier, a stale size is replaced by the fresh one, and reported")
    func freshSizeWithTheVerifier() {
        let was = RenderCache.verifiesMeasureMemo
        defer { RenderCache.verifiesMeasureMemo = was }
        func secondFrame(verifying: Bool) -> (line: String, reports: [String]) {
            RenderCache.verifiesMeasureMemo = verifying
            let loop = VerifierLoop()
            func view(_ text: String) -> some View {
                HStack(spacing: 0) { TitledCard(title: "t", text: text).equatable(); Text("|") }
            }
            _ = loop.frame(view("ab"))
            _ = loop.frame(view("ab"))
            let line = loop.frame(view("abcdef")).first ?? ""
            return (line, loop.tui.renderCache.measureMemoMismatches)
        }
        let fresh = secondFrame(verifying: true)
        #expect(fresh.line.hasPrefix("abcdef|"), "laid out at the stale width: \(fresh.line)")
        #expect(!fresh.reports.isEmpty, "the stale size went unreported")
    }
}
