//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHyperlinkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// The sequence itself: how a destination is spelled, and why it is re-encoded
/// rather than trusted.
@Suite("OSC 8 hyperlink sequences")
struct TerminalHyperlinkSequenceTests {

    @Test("A link wraps its cells and adds no width")
    func linkAddsNoWidth() {
        let wrapped = "Docs".hyperlinked(to: TerminalHyperlink(destination: "https://example.com"))
        #expect(wrapped == "\u{1B}]8;;https://example.com\u{1B}\\Docs\u{1B}]8;;\u{1B}\\")
        #expect(wrapped.strippedLength == 4)
    }

    @Test("An id goes in the parameter field, shared by every run of one link")
    func idIsAParameter() {
        let link = TerminalHyperlink(destination: "https://example.com", id: "docs-1")
        #expect(link.opening == "\u{1B}]8;id=docs-1;https://example.com\u{1B}\\")
    }

    /// The sequence ends at an `ESC` or a `BEL`, so a destination carrying
    /// either does not render oddly — it ENDS THE SEQUENCE, and the rest is
    /// text the terminal draws. A URL is exactly the kind of value an app
    /// builds from data it did not author, which is why the encoding lives
    /// here rather than in each caller.
    @Test("A destination cannot break out of the sequence")
    func destinationCannotEscape() {
        let hostile = "https://example.com/\u{1B}]0;pwned\u{07}"
        let opening = TerminalHyperlink(destination: hostile).opening
        #expect(opening.hasSuffix("\u{1B}\\"), "it still ends with its own ST")
        // Between the introducer and that ST there must be no ESC and no BEL:
        // either would end the sequence early and print the rest.
        let payload = opening.dropFirst(TerminalHyperlink.introducer.count).dropLast(2)
        #expect(!payload.contains("\u{1B}"))
        #expect(!payload.contains("\u{07}"))
        #expect(payload.contains("%1B"), "the ESC is carried as an encoded byte")

        // And it is still one zero-width sequence to every scan.
        let line = "Docs".hyperlinked(to: TerminalHyperlink(destination: hostile))
        #expect(line.strippedLength == 4)
        #expect(line.stripped == "Docs")
    }

    /// Everything outside printable ASCII is percent-encoded, `%` included so
    /// the encoding round-trips: a destination that already said `%41` must
    /// reach the host as `%41` and not as `A`.
    @Test("Encoding is total, and round-trips its own escape character")
    func encodingRoundTrips() {
        #expect(TerminalHyperlink.encoded("a b") == "a%20b")
        #expect(TerminalHyperlink.encoded("%41") == "%2541")
        #expect(TerminalHyperlink.encoded("café") == "caf%C3%A9", "UTF-8 bytes, not scalars")
        #expect(TerminalHyperlink.encoded("a;b[c]m") == "a;b[c]m", "printable ASCII is left alone")
    }

    /// An id is a parameter VALUE: `;` ends the parameter list, `:` separates
    /// parameters and `=` splits key from value, so in an id those three are
    /// the container's syntax and must be encoded — while in the URI, the
    /// last field, they are the URI's own and must not be.
    @Test("An id encodes its field syntax; the URI keeps its own")
    func parameterValueEncodesFieldSyntax() {
        #expect(TerminalHyperlink.encoded("a;b:c=d", in: .parameterValue) == "a%3Bb%3Ac%3Dd")
        #expect(TerminalHyperlink.encoded("a;b:c=d") == "a;b:c=d", "the URI is the last field")
        let link = TerminalHyperlink(destination: "https://x/?a=1;b", id: "row;2")
        #expect(link.opening == "\u{1B}]8;id=row%3B2;https://x/?a=1;b\u{1B}\\")
        #expect(TerminalHyperlink.opensLink(link.opening))
    }

    /// The difference between the two sequences is the URI field, not the
    /// spelling — `ESC]8;;ST` names no destination, and that is precisely how
    /// OSC 8 says "the link ends here".
    @Test("Open and close are told apart by the URI field")
    func openAndCloseAreDistinguished() {
        #expect(TerminalHyperlink.opensLink("\u{1B}]8;;https://example.com\u{1B}\\"))
        #expect(TerminalHyperlink.opensLink("\u{1B}]8;id=x;https://example.com\u{07}"))
        #expect(!TerminalHyperlink.opensLink(TerminalHyperlink.closing))
        #expect(!TerminalHyperlink.opensLink("\u{1B}]8;;\u{07}"))
        #expect(!TerminalHyperlink.opensLink("\u{1B}]0;a title\u{07}"), "a different OSC command")
        #expect(!TerminalHyperlink.opensLink("\u{1B}[31m"))
    }
}

/// What a cut does to a link, which is the half that can go wrong invisibly in
/// one direction and very visibly in the other.
@Suite("A hyperlink across a cut")
struct HyperlinkCutTests {

    static let url = "https://example.com/a;b[c]m"
    static let opening = "\u{1B}]8;;\(url)\u{1B}\\"
    static let closing = TerminalHyperlink.closing

    /// Whether `line` leaves a link open at its end — the property every cut
    /// must preserve, and the one whose failure spreads.
    static func leavesLinkOpen(_ line: String) -> Bool {
        var scan = HyperlinkScan()
        for segment in line.ansiSegments() {
            if case .ansi(let sequence, _) = segment { scan.note(sequence) }
        }
        return scan.opening != nil
    }

    static func linked(_ text: String) -> String { opening + text + closing }

    // MARK: - Prefixes

    /// A prefix that keeps the opening sequence and loses the closing one does
    /// not merely lose the link: on a host that honours OSC 8 every cell drawn
    /// afterwards joins it — the rest of the row, its padding included.
    @Test("A prefix cut inside a link closes it", arguments: 1...5)
    func prefixClosesTheLink(cut: Int) {
        let line = Self.linked("Documentation")
        let (prefix, width) = line.exactAnsiAwarePrefixWithWidth(visibleCount: cut)
        #expect(width == cut)
        #expect(prefix.strippedLength == cut)
        #expect(!Self.leavesLinkOpen(prefix))
        #expect(prefix.hasSuffix(Self.closing))
    }

    /// …and the Terminal.app clip, which is a second walk with the same job.
    @Test("The Terminal.app prefix closes it too")
    func terminalAppPrefixClosesTheLink() {
        let prefix = Self.linked("Documentation")
            .exactAnsiAwarePrefixForTerminalAppWithWidth(visibleCount: 4).prefix
        #expect(prefix.stripped == "Docu")
        #expect(!Self.leavesLinkOpen(prefix))
    }

    /// The fast paths return `self` untouched when the line already fits, so
    /// the walk must not add a sequence at the natural end of the string —
    /// they are required to be byte-identical for every input.
    @Test("An uncut prefix is byte-identical, link or no link")
    func uncutPrefixIsUnchanged() {
        for line in [Self.linked("Docs"), "plain", Self.opening + "unbalanced"] {
            let width = line.strippedLength
            #expect(line.exactAnsiAwarePrefixWithWidth(visibleCount: width).prefix == line)
            #expect(line.ansiAwarePrefixWithWidth(visibleCount: width).prefix == line)
            #expect(
                line.ansiAwarePrefixWithWidth(visibleCount: width, knownVisibleWidth: width).prefix
                    == line)
        }
    }

    // MARK: - Suffixes and slices

    /// The quiet obligation: nothing looks broken when it is missed, the link
    /// is simply shorter than the label it belongs to.
    @Test("A suffix beginning inside a link re-opens it")
    func suffixReopensTheLink() {
        let suffix = Self.linked("Documentation").ansiAwareSuffix(droppingVisible: 4)
        #expect(suffix.stripped == "mentation")
        #expect(suffix.hasPrefix(Self.opening))
        #expect(!Self.leavesLinkOpen(suffix))
    }

    /// A link that opened AND closed before the boundary is not in force
    /// there, so nothing is owed. The state has to be tracked rather than
    /// accumulated, which is what tells this case from the one above.
    @Test("A link that closed before the boundary is not re-opened")
    func closedLinkIsNotReopened() {
        let line = Self.linked("Docs") + " and more text"
        let suffix = line.ansiAwareSuffix(droppingVisible: 6)
        #expect(suffix.stripped == "nd more text")
        #expect(!suffix.contains(Self.url))
    }

    @Test("A slice inside a link carries it in and closes it on the way out")
    func sliceCarriesAndCloses() {
        let line = "lead " + Self.linked("Documentation") + " tail"
        let slice = line.ansiAwareSlice(visibleStart: 7, visibleCount: 5)
        #expect(slice.stripped == "cumen")
        #expect(slice.contains(Self.url), "the link the window is inside")
        #expect(!Self.leavesLinkOpen(slice))
    }

    @Test("A slice past the link carries nothing")
    func sliceOutsideCarriesNothing() {
        let line = Self.linked("Docs") + " and more text"
        let slice = line.ansiAwareSlice(visibleStart: 5, visibleCount: 3)
        #expect(slice.stripped == "and")
        #expect(!slice.contains(Self.url))
    }

    // MARK: - The overlay split

    /// One scan, two cuts at different columns: the prefix ends where the
    /// overlay begins and owes a close (an open link would run under the
    /// overlay), and the suffix begins past the overlay's right edge and owes
    /// the opening sequence.
    @Test("The overlay split closes its prefix and resumes its suffix")
    func overlaySplitBalancesBothHalves() {
        let split = Self.linked("Documentation").ansiOverlaySplit(
            prefixColumns: 3, suffixDropColumns: 8)
        #expect(split.prefix.stripped == "Doc")
        #expect(!Self.leavesLinkOpen(split.prefix))
        #expect(split.suffix.stripped == "ation")
        #expect(split.suffix.hasPrefix(Self.opening))
        #expect(!Self.leavesLinkOpen(split.suffix))
    }

    /// A line SHORTER than the overlay's column never reaches the cut inside
    /// the walk, and the overlay is composited straight after it either way.
    @Test("A short line's link is still closed before the overlay")
    func shortLineStillCloses() {
        let split = (Self.opening + "Docs").ansiOverlaySplit(
            prefixColumns: 40, suffixDropColumns: 40)
        #expect(split.prefix.stripped == "Docs")
        #expect(!Self.leavesLinkOpen(split.prefix))
    }

    // MARK: - The buffer, end to end

    /// The property that actually matters, asked of the primitive every
    /// container clips through rather than of the walks underneath it.
    @Test("Clamping a buffer never leaves a link open", arguments: 1...8)
    func clampedBufferIsBalanced(width: Int) {
        let buffer = FrameBuffer(lines: [Self.linked("Documentation")])
        let clamped = buffer.clamped(toWidth: width, height: 1)
        #expect(clamped.width == min(width, 13))
        for line in clamped.lines {
            #expect(!Self.leavesLinkOpen(line))
        }
    }
}
