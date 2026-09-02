//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StringOSCScanningTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// Every scan that walks framework-generated output used to assume an escape
/// is a CSI — `ESC [ … final byte`. OSC 8 hyperlinks break that assumption in
/// the worst possible way: an unrecognised `ESC ]` leaves the introducer's `]`
/// and the whole URI to be counted as **visible text**, so the line claims
/// columns nothing paints and everything laid out around it moves.
///
/// A hyperlink is a good adversary for these scans, because its payload
/// contains the bytes the CSI rule is made of. `https://example.com/a;b[c]m`
/// has a `;`, a `[`, an `m` and a `]` in it — parameter bytes, an introducer
/// and two plausible final bytes — so a scanner that half-recognises the
/// family lands somewhere different for every URL rather than failing the same
/// way twice.
@Suite("OSC scanning in the width and split machinery")
struct StringOSCScanningTests {

    /// The two spellings of the terminator, and a URI made of the bytes a CSI
    /// scanner reacts to.
    static let awkwardURI = "https://example.com/a;b[c]m"

    static func link(_ text: String, terminator: String = "\u{1B}\\") -> String {
        "\u{1B}]8;;\(awkwardURI)\(terminator)\(text)\u{1B}]8;;\(terminator)"
    }

    // MARK: - Width

    @Test(
        "A hyperlink adds no width",
        arguments: ["\u{1B}\\", "\u{07}"])
    func linkIsZeroWidth(terminator: String) {
        let line = Self.link("Docs", terminator: terminator)
        #expect(line.strippedLength == 4)
        #expect(line.stripped == "Docs")
    }

    /// The ASCII byte path is not a shortcut past the family — it is the path a
    /// link actually takes. OSC 8 URIs are percent-encoded, hence ASCII, so a
    /// linked line of ASCII text never reaches the general scalar walk. A fast
    /// path that did not know the family would return a wrong number rather
    /// than declining to answer.
    @Test("The ASCII fast path and the general path agree about a link")
    func fastPathAgreesWithGeneralPath() {
        let ascii = Self.link("Docs")
        #expect(ascii.asciiStrippedLength() == 4, "the link is all-ASCII, so this path runs")
        #expect(ascii.strippedLength == 4)

        // One non-ASCII glyph forces the general path for the same question.
        let wide = Self.link("Docs漢")
        #expect(wide.asciiStrippedLength() == nil)
        #expect(wide.strippedLength == 6, "4 + a 2-cell CJK glyph")
    }

    /// An unterminated sequence runs to the end of the string. Everything after
    /// a truncated introducer is *inside* the sequence as far as the terminal
    /// is concerned, so counting the tail as visible would be a width for cells
    /// nothing paints — the same reading ``sanitizedForTerminal`` takes.
    @Test("An unterminated hyperlink swallows the rest of the line")
    func unterminatedLinkSwallowsTheRest() {
        let truncated = "before\u{1B}]8;;https://example.com"
        #expect(truncated.strippedLength == 6)
        #expect(truncated.stripped == "before")
    }

    // MARK: - Segmentation and skipping

    /// One segment, not shredded. Every splitter in `String+ANSISplitting.swift`
    /// is built on these and copies an `.ansi` segment through untouched, so a
    /// sequence that arrives here in pieces is one that arrives at a cut in
    /// pieces too.
    @Test("ansiSegments yields the whole sequence as one escape")
    func segmentsKeepTheSequenceWhole() {
        let segments = Self.link("Hi").ansiSegments()
        var escapes: [String] = []
        var visible = ""
        for segment in segments {
            switch segment {
            case .ansi(let sequence, let isSGR):
                escapes.append(sequence)
                #expect(!isSGR, "a hyperlink is not styling")
            case .visible(let character):
                visible.append(character)
            }
        }
        #expect(visible == "Hi")
        #expect(escapes == ["\u{1B}]8;;\(Self.awkwardURI)\u{1B}\\", "\u{1B}]8;;\u{1B}\\"])
    }

    /// The walker the cursor-compensation passes use. They copy escapes through
    /// and price everything else as a grapheme cluster, so a URI walked as text
    /// would be measured, erased and `CUF`-repaired character by character.
    @Test("escapeSequenceEnd steps over the whole sequence")
    func escapeEndStepsOverTheSequence() {
        let opening = "\u{1B}]8;;\(Self.awkwardURI)\u{1B}\\"
        let line = opening + "tail"
        let end = line.escapeSequenceEnd(from: line.startIndex)
        #expect(String(line[line.startIndex..<end]) == opening)
        #expect(String(line[end...]) == "tail")

        let belForm = "\u{1B}]0;window title\u{07}rest"
        let belEnd = belForm.escapeSequenceEnd(from: belForm.startIndex)
        #expect(String(belForm[belEnd...]) == "rest")
    }

    /// A link opening a line is exactly where the leading-sequence split used
    /// to fall between the `ESC` and its own introducer, handing the caller a
    /// bare `ESC` to replay as "styling" and a remainder beginning inside a
    /// sequence.
    @Test("leadingANSISplit keeps a leading link with the styling")
    func leadingSplitKeepsTheLinkWhole() {
        let opening = "\u{1B}[4m\u{1B}]8;;\(Self.awkwardURI)\u{1B}\\"
        let (prefix, remainder) = (opening + "Docs").leadingANSISplit()
        #expect(prefix == opening)
        #expect(remainder == "Docs")
    }

    // MARK: - SGR netting

    /// The reconciler emits pending styling immediately before the next glyph.
    /// With the family unrecognised, the URI's characters reach it one at a
    /// time — so an `ESC[…m` gets emitted *inside* the URI, which loses the
    /// styling and the link at once.
    @Test("Collapsing adjacent SGR never writes styling into the payload")
    func collapsingKeepsThePayloadIntact() {
        let line = "\u{1B}[0m\u{1B}[34m" + Self.link("Docs") + "\u{1B}[0m"
        let collapsed = line.collapsingAdjacentSGR()
        #expect(collapsed.contains("\u{1B}]8;;\(Self.awkwardURI)\u{1B}\\"))
        #expect(collapsed.strippedLength == 4)
        #expect(collapsed.stripped == "Docs")
    }

    // MARK: - The row diff

    /// A hyperlink is state that spans cells, and a span write lands the cursor
    /// in the middle of a row — so a row carrying one is rewritten whole rather
    /// than in runs. Declining is the answer here, and it has to be a decision
    /// rather than a fall-through.
    @Test("A row carrying a hyperlink declines the span diff")
    func linkedRowDeclinesTheSpanDiff() {
        let width = 8
        let previous = "Docs    "
        let updated = Self.link("Docs") + "    "
        #expect(updated.strippedLength == width)
        #expect(updated.ansiCellDiff(replacing: previous, width: width, mergingGapsUpTo: 8)
            == .wholeLine)
        #expect(ANSIRowCells(decomposing: updated, width: width) == nil)
    }
}
