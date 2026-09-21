//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkHyperlinkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// ``Link``'s OSC 8 half: what it emits, when, and the property that must hold
/// however the label is laid out.
///
/// The support flag is pinned task-locally rather than assigned, so these run
/// alongside every other suite without putting hyperlinks into anybody else's
/// rendering.
@MainActor
@Suite("Link terminal hyperlinks")
struct LinkHyperlinkTests {

    private let url = URL(string: "https://example.com/docs")!

    private func render(_ view: some View, width: Int = 40, height: Int = 6) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
    }

    /// Whether `line` leaves a link open at its end — the property whose
    /// failure spreads past the control and down the row.
    private func leavesLinkOpen(_ line: String) -> Bool {
        var scan = HyperlinkScan()
        for segment in line.ansiSegments() {
            if case .ansi(let sequence, _) = segment { scan.note(sequence) }
        }
        return scan.opening != nil
    }

    @Test("A supported host gets the sequence, and it costs no cells")
    func supportedHostGetsTheLink() {
        let view = Link("swift.org", destination: url)
        let without = TerminalHyperlink.withSupport(false) { render(view) }
        let with = TerminalHyperlink.withSupport(true) { render(view) }

        #expect(!without.lines.joined().contains("\u{1B}]8;"))
        #expect(with.lines.joined().contains("\u{1B}]8;;https://example.com/docs\u{1B}\\"))
        #expect(with.lines.joined().hasSuffix(TerminalHyperlink.closing))
        // The whole point of an escape: the layout is the same either way.
        #expect(with.width == without.width)
        #expect(with.lines.map(\.strippedLength) == without.lines.map(\.strippedLength))
        #expect(with.lines.map(\.stripped) == without.lines.map(\.stripped))
    }

    /// A disabled link is skipped by Tab, registers no region and never runs
    /// its action — and a terminal that honours OSC 8 opens a linked cell on
    /// its OWN gesture, past all of that. iTerm2 opens on every click.
    @Test("A disabled link carries no hyperlink for the terminal to open")
    func disabledLinkHasNoHyperlink() {
        let disabled = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url).disabled(true))
        }
        #expect(!disabled.lines.joined().contains("\u{1B}]8;"), "\(disabled.lines)")
        let enabled = TerminalHyperlink.withSupport(true) { render(Link("swift.org", destination: url)) }
        #expect(enabled.lines.joined().contains("\u{1B}]8;"), "the rule is about disabled, not about support")
    }

    /// Renders `view` in a pass that lets the link register and take the
    /// focus, then again — so the second buffer is the FOCUSED one, breath
    /// runs and all.
    private func focusedRender(_ view: some View) -> FrameBuffer {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 6, environment: environment, tuiContext: tui)
        var buffer = FrameBuffer()
        for _ in 0..<2 {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            environment.focusManager?.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            environment.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        return buffer
    }

    /// A focused link breathes by REPLACING its cells with pre-rendered
    /// frames, and the splice closes any open link at the cut. Frames without
    /// their own pair stripped the hyperlink from the one link the user had
    /// selected, on the first tick.
    @Test("A focused link's breath frames carry the hyperlink too")
    func breathFramesKeepTheLink() {
        let buffer = TerminalHyperlink.withSupport(true) {
            focusedRender(Link("swift.org", destination: url))
        }
        #expect(!buffer.animatedCells.isEmpty, "a focused link breathes")
        for run in buffer.animatedCells {
            for frame in run.frames {
                #expect(frame.contains("\u{1B}]8;;https://"), "a frame without the link: \(frame.debugDescription)")
                #expect(!leavesLinkOpen(frame))
            }
        }
    }

    /// A run can carry what its cells owe per frame (`AnimatedRunAlpha`), and when it
    /// does the run is the ONLY thing saying so: a blinking caret over a faded well has
    /// no rectangle true of both its frames. The link rebuilds every run to give its
    /// frames their own pair, and rebuilt field by field it dropped that payload — so a
    /// text field in a link's label replayed its well at full strength on a host that
    /// honours OSC 8, and faded correctly on one that does not.
    ///
    /// The oracle is the same view without the hyperlink: the escapes cost no cells and
    /// the spans are run-relative, so the payload must come through unchanged.
    @Test("A label's run keeps its per-frame alpha through the hyperlink")
    func runAlphaSurvivesTheLink() throws {
        func drawn() -> FrameBuffer {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            environment.palette = FadedAll()
            environment.applyRuntimeServices(from: tui)
            // Its own focus manager, or the field is not focused and has no caret.
            environment.focusManager = FocusManager()
            let context = RenderContext(
                availableWidth: 40, availableHeight: 3, environment: environment, tuiContext: tui
            ).isolatingRenderCache()
            // A URL mode, so the label is not wrapped in a button and the field is the
            // one focusable thing on the page.
            let view = Link(destination: url) {
                TextField("label", text: .constant("abc")).textCursor(.block, animation: .blink)
            }
                .linkDisplay(.urlInParentheses)
            return renderToBuffer(view, context: context)
        }
        let plain = TerminalHyperlink.withSupport(false) { drawn() }
        let linked = TerminalHyperlink.withSupport(true) { drawn() }

        let expected = try #require(
            plain.animatedCells.first { $0.alpha != nil },
            "the premise: the caret's run states its alpha when nothing rebuilds it")
        let caret = try #require(
            linked.animatedCells.first { $0.offsetX == expected.offsetX && $0.offsetY == expected.offsetY },
            "the caret still animates: \(linked.animatedCells.map { ($0.offsetX, $0.offsetY) })")
        #expect(caret.frames.allSatisfy { $0.contains("\u{1B}]8;;https://") }, "the premise: it was rebuilt")
        #expect(caret.alpha == expected.alpha, "the payload came through: \(String(describing: caret.alpha))")
    }

    /// A terminal-owned ⌘-click goes to the system opener over the top of
    /// ``OpenURLAction``, so an app that intercepts its own scheme needs a way
    /// to keep every URL for itself.
    @Test(".terminalHyperlinks(false) removes it on a host that would honour it")
    func subtreeCanOptOut() {
        let opted = TerminalHyperlink.withSupport(true) {
            render(VStack { Link("swift.org", destination: url) }.terminalHyperlinks(false))
        }
        #expect(!opted.lines.joined().contains("\u{1B}]8;"))
        #expect(opted.lines.joined().contains("swift.org"))
    }

    /// One balanced pair per LINE. A pair spanning rows would be split by any
    /// container that clipped between them, and a row whose link is left open
    /// hands it to everything drawn after it.
    @Test("Every row is balanced, and a multi-row label shares one id")
    func everyRowIsSelfContained() {
        let wrapped = TerminalHyperlink.withSupport(true) {
            render(Link("a documentation link long enough to wrap", destination: url), width: 14)
        }
        #expect(wrapped.lines.count > 1, "the label has to wrap for this to test anything")
        for line in wrapped.lines {
            #expect(!leavesLinkOpen(line))
        }
        #expect(wrapped.lines.joined().contains("\u{1B}]8;id="), "runs of one link share an id")

        // …and a single-run link spends no bytes on an identity it cannot use.
        let single = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url))
        }
        #expect(!single.lines.joined().contains("id="))
    }

    /// The property asked of the thing a container actually does to a control
    /// too wide for it, rather than of the walk underneath.
    @Test("A clipped link never leaves the sequence open", arguments: 1...9)
    func clippingKeepsItBalanced(width: Int) {
        let clipped = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url).frame(width: width), width: width + 4)
        }
        for line in clipped.lines {
            #expect(!leavesLinkOpen(line))
        }
    }

    /// The clips above cut a link TUIkit itself emitted, which is balanced
    /// before anything pads it — so the cut lands outside the link and nothing
    /// is left open. The route that does leave one open is content the app
    /// hands in: `Text`, a `Table` cell and a `List` row all pass a raw OSC 8
    /// through unchanged, and `truncatedToWidth` then clips it.
    ///
    /// That clip took the byte-drop fast path in
    /// `ansiAwarePrefix(visibleCount:knownVisibleWidth:)`, which returned the
    /// line minus its trailing space bytes — byte-identical to the walk for
    /// everything EXCEPT the one thing the walk adds at a cut: the closing
    /// sequence of a link still open. The width re-scan guarding that path
    /// cannot see the difference, because a closing sequence is zero cells.
    /// The link then ran on over the ellipsis and over whatever the caller
    /// appended next — a row's fill and badge, the scrollbar column, the diff
    /// writer's padding — and a click anywhere along that opened the URL.
    @Test("A truncated line closes a hyperlink the content left open", arguments: 1...6)
    func truncatingClosesAnOpenHyperlink(excess: Int) {
        let raw = "\u{1B}]8;;https://example.com/docs\u{1B}\\click here      "
        let clipped = raw.truncatedToWidth(raw.strippedLength - excess)
        #expect(!leavesLinkOpen(clipped), "excess \(excess): \(clipped.debugDescription)")
    }

    /// A hyperlink is not styling, so it must not be mistaken for any: the
    /// label keeps its accent and its underline, and the row still measures
    /// what it paints.
    @Test("The link rides alongside the styling rather than replacing it")
    func stylingSurvives() {
        let styled = TerminalHyperlink.withSupport(true) {
            render(Link("swift.org", destination: url))
        }
        let joined = styled.lines.joined()
        // SGR 4 arrives folded into the run's colour (`ESC[4;38;2;…m`), which
        // is the point: the link and the styling are separate sequences and
        // neither has displaced the other.
        #expect(joined.contains("\u{1B}[4;") || joined.contains("\u{1B}[4m"), "still underlined")
        #expect(joined.strippedLength == styled.lines.map(\.strippedLength).reduce(0, +))
    }
}
