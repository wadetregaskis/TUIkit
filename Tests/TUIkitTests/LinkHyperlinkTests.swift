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
