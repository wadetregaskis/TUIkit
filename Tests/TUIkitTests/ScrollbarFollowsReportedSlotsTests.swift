//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarFollowsReportedSlotsTests.swift
//
//  The vertical scrollbar is kept on its handler with the inputs it was drawn
//  from (`VerticalScrollbarMemo`). At sixteen colours an RGB colour is emitted as
//  the slot nearest to what that slot PAINTS — the colour the terminal reported
//  for it, or xterm's value while it has reported none — so the bar's bytes are a
//  function of the terminal's colours as well as of the palette. The key has to
//  say which colours it was drawn under, or a report arriving after the bar was
//  first drawn never reaches it.
//
//  Keyed on the colours themselves rather than on `TerminalColors.generation`, as
//  the image caches are (b7a2f35d): a task-local pin changes what a slot measures
//  as without moving the generation.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// A palette whose scrollbar colours are RGB, so nothing about it is grounded on
/// the terminal's colours: the report reaches the bar only through the sixteen-colour
/// quantiser. (220, 0, 0) is nearer xterm's red (205, 0, 0) than its bright red, and
/// nearer Apple Terminal "Basic"'s bright red (230, 0, 0) than its red (153, 0, 0),
/// so the same colour is SGR 31/41 unreported and 91/101 there.
private struct RedBarPalette: Palette, Hashable {
    let id = "red-bar"
    let name = "Red bar"
    let background: Color = .rgb(0, 0, 0)
    let foreground: Color = .rgb(200, 200, 200)
    let foregroundSecondary: Color = .rgb(220, 0, 0)
    let foregroundTertiary: Color = .rgb(220, 0, 0)
    let foregroundQuaternary: Color = .rgb(90, 90, 90)
    let accent: Color = .rgb(220, 0, 0)
    let success: Color = .rgb(0, 200, 0)
    let warning: Color = .rgb(200, 200, 0)
    let error: Color = .rgb(200, 0, 0)
    let info: Color = .rgb(0, 200, 200)
    let border: Color = .rgb(100, 100, 100)
}

@MainActor
@Suite("A scrollbar drawn in the terminal's sixteen follows what it reports")
struct ScrollbarFollowsReportedSlotsTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them on
    /// 2026-09-14 (Documentation/Terminal-compatibility.md), in slot order.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255),
        slots: TerminalColors.Slots([
            rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
            rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
            rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
            rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
        ]))

    /// One scroll view, rendered as many times as asked, each frame under its own
    /// terminal colours — the memo on the handler is what carries from one to the next.
    @MainActor
    private struct Harness {
        let tui = TUIContext()
        let focusManager = FocusManager()

        func frame(terminal: TerminalColors) -> FrameBuffer {
            let view = ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<60, id: \.self) { index in Text("row \(index)") }
                }
            }
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            environment.palette = RedBarPalette()
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = TerminalColors.withCurrent(terminal) {
                ColorDepth.withCurrent(.basic16) {
                    renderToBuffer(view, context: context)
                }
            }
            focusManager.endRenderPass()
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            return buffer
        }

        var handler: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    /// The bar each frame left on the handler, one entry per element of `terminals`.
    ///
    /// The bar the MEMO holds, not the frame's lines: at sixteen colours every colour
    /// in the frame quantises through the report, so whole-frame bytes would differ
    /// whether or not the bar itself was drawn again.
    private func bars(under terminals: [TerminalColors]) throws -> (lines: [[String]], hits: [Int]) {
        let harness = Harness()
        var lines: [[String]] = []
        var hits: [Int] = []
        for terminal in terminals {
            _ = harness.frame(terminal: terminal)
            let handler = try #require(harness.handler, "no scroll handler registered")
            let memo = try #require(handler.verticalScrollbarMemo, "the bar was not kept")
            lines.append(memo.bar.lines)
            hits.append(handler.verticalScrollbarMemoHits)
        }
        return (lines, hits)
    }

    @Test("A report that moves the bar's slots draws it again, rather than serving the one before")
    func reportedSlotsDrawTheBarAgain() throws {
        let apple = Self.appleTerminal
        // The fixture: three frames of the same scroll view, all under the report and
        // all under silence, so focus and the pulse are in the same state either way.
        let reported = try bars(under: [apple, apple, apple])
        let silent = try bars(under: [.unknown, .unknown, .unknown])
        #expect(
            reported.lines[2] != silent.lines[2],
            "the fixture: a reported table must change which slot the bar's red is")

        // The same three frames, with the report landing on the third — as a reply
        // that arrives after the app has drawn does.
        let late = try bars(under: [.unknown, .unknown, apple])
        #expect(
            late.hits[2] == late.hits[1],
            "the bar drawn before the report answered the frame after it: \(late.hits)")
        #expect(
            late.lines[2] == reported.lines[2],
            "the bar kept the slots it was drawn under before the terminal reported its own")
    }

    @Test("Unchanged colours are still served from the memo")
    func unchangedColoursStillHit() throws {
        let apple = Self.appleTerminal
        let served = try bars(under: [apple, apple])
        #expect(
            served.hits[1] > served.hits[0],
            "a frame under the colours the bar was drawn under must be served: \(served.hits)")
        #expect(served.lines[1] == served.lines[0])
    }
}
