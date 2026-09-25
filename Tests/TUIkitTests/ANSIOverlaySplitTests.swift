//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIOverlaySplitTests.swift
//
//  `ansiOverlaySplit` fuses four separate ANSI-aware scans into one so that
//  compositing a child into a row stops rescanning the whole row four times.
//  A fused implementation is only worth having if it is INDISTINGUISHABLE from
//  the four it replaces, so that is what these check — differentially, over the
//  awkward cases (wide characters straddling either split point, escapes either
//  side of both boundaries, empty and past-the-end columns) rather than a
//  handful of hand-picked strings.
//
//  The scan also notes the field under each column the overlay covers
//  (`FieldsUnderOverlay`), which compositing paints the overlay over, cell by
//  cell. That is held to the state the line has in force at each column
//  (`ansiSGRStateAt(visibleColumn:)`), and "one field" to exactly when it is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("ANSI overlay split")
struct ANSIOverlaySplitTests {

    /// Every field must equal the helper it replaces, for every split point.
    private func assertMatchesHelpers(_ line: String, _ label: String) {
        let width = line.strippedLength
        // Past the ends as well as inside: an overlay can be placed at 0, and
        // can extend beyond the line it is drawn into.
        for prefixColumns in -1...(width + 2) {
            for dropColumns in -1...(width + 2) {
                let fused = line.ansiOverlaySplit(
                    prefixColumns: prefixColumns, suffixDropColumns: dropColumns)
                let (expectedPrefix, expectedPrefixWidth) =
                    line.ansiAwarePrefixWithWidth(visibleCount: prefixColumns)
                let expectedSuffix = line.ansiAwareSuffix(droppingVisible: dropColumns)

                #expect(
                    fused.prefix == expectedPrefix,
                    """
                    \(label) prefix at \(prefixColumns): \
                    \(fused.prefix.debugDescription) != \(expectedPrefix.debugDescription)
                    """)
                #expect(
                    fused.prefixWidth == expectedPrefixWidth,
                    "\(label) prefixWidth at \(prefixColumns)")
                #expect(
                    fused.suffix == expectedSuffix,
                    """
                    \(label) suffix dropping \(dropColumns): \
                    \(fused.suffix.debugDescription) != \(expectedSuffix.debugDescription)
                    """)
                #expect(
                    fused.suffixWidth == expectedSuffix.strippedLength,
                    "\(label) suffixWidth dropping \(dropColumns)")
                #expect(
                    fused.styleBeforeSuffix == Self.styleBefore(line, column: dropColumns),
                    "\(label) styleBeforeSuffix at \(dropColumns)")
                #expect(fused.totalWidth == width, "\(label) totalWidth")
                expectFieldsUnderTheOverlay(fused, line, prefixColumns..<max(prefixColumns, dropColumns), label)
                // Asked not to note the fields — the splices whose overlay states
                // its own — the same split, with the first field alone.
                let unnoted = line.ansiOverlaySplit(
                    prefixColumns: prefixColumns, suffixDropColumns: dropColumns, notingFields: false)
                #expect(
                    unnoted.prefix == fused.prefix && unnoted.suffix == fused.suffix
                        && unnoted.styleBeforeSuffix == fused.styleBeforeSuffix
                        && unnoted.backgroundUnderOverlay == fused.backgroundUnderOverlay
                        && unnoted.totalWidth == fused.totalWidth,
                    "\(label) split without the fields at \(prefixColumns), \(dropColumns)")
                #expect(
                    unnoted.fieldsUnderOverlay
                        == FieldsUnderOverlay(
                            column: prefixColumns, first: fused.fieldsUnderOverlay.first, changes: []),
                    "\(label) fields noted anyway at \(prefixColumns), \(dropColumns)")
            }
        }
    }

    /// The field `line` shows at `column`, as a row still to be written reads it:
    /// none after a reset, the terminal's own after an `ESC[49m`
    /// (``SGRState/Colour/statedTerminalField``), a colour after one — and under
    /// reverse video the ink, spelled as a field where it can be. Read escape by
    /// escape through what each says about the background, beside the netted state
    /// — which keeps a reset and a 49 alike.
    ///
    /// - Parameter includingBoundary: Whether escapes AT `column` count, as they do
    ///   for the cell drawn there; not for the state where a suffix begins.
    private static func field(_ line: String, at column: Int, includingBoundary: Bool = true) -> SGRState.Colour? {
        var state = SGRState()
        var field: SGRState.Colour?
        var visible = 0
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true):
                guard includingBoundary ? visible <= column : visible < column else {
                    return reversedInk(state) ?? field
                }
                switch state.applyReportingBackground(sequence) {
                case .reset: field = nil
                case .terminalDefault: field = .statedTerminalField
                case .colour: field = state.backgroundColour
                case nil: break
                }
            case .ansi: continue
            case .visible(let character): visible += character.terminalWidth
            }
        }
        return reversedInk(state) ?? field
    }

    /// The ink a reversed `state` shows as its field, spelled for the background
    /// slot — spelled out here, not asked of the code under test — or `nil` where
    /// the state is not reversed or its ink is the terminal's own, which has no
    /// such spelling.
    private static func reversedInk(_ state: SGRState) -> SGRState.Colour? {
        guard state.reversesVideo, let ink = state.foregroundColour else { return nil }
        switch ink {
        case .named(let code) where (30...37).contains(code) || (90...97).contains(code): return .named(code + 10)
        case .named: return nil
        case .indexed, .rgb: return ink
        }
    }

    /// Under reverse video a cell shows its INK as its field, so that is the field
    /// the split notes — in the background slot's spelling. The terminal's own ink
    /// has none, and there the slot stands.
    @Test("Under reverse video the field under an overlay is the ink, spelled as a field")
    func reversedFields() {
        let named = "\u{1B}[7;31mabc\u{1B}[27mdef".ansiOverlaySplit(prefixColumns: 1, suffixDropColumns: 5)
        #expect(named.fieldsUnderOverlay.fields(over: 1..<5) == [.named(41), .named(41), nil, nil])
        let bright = "\u{1B}[7;93mab".ansiOverlaySplit(prefixColumns: 0, suffixDropColumns: 2)
        #expect(bright.fieldsUnderOverlay.first == .named(103))
        let rgb = "\u{1B}[7;38;2;1;2;3;44mabc".ansiOverlaySplit(prefixColumns: 0, suffixDropColumns: 2)
        #expect(rgb.fieldsUnderOverlay.first == .rgb(1, 2, 3))
        #expect(rgb.backgroundUnderOverlay == "\u{1B}[48;2;1;2;3m")
        let unstated = "\u{1B}[7;44mabc".ansiOverlaySplit(prefixColumns: 0, suffixDropColumns: 2)
        #expect(unstated.fieldsUnderOverlay.first == .named(44))
        // And the suffix gets the line's own slots back, reversal and all.
        #expect(rgb.styleBeforeSuffix == "\u{1B}[7;38;2;1;2;3;44m")
    }

    /// What the insert restores where the suffix begins: the netted state there
    /// (``String/ansiStateBefore(visibleColumn:)``), with a stated 49 in force
    /// said again — netted alone, it is dropped, and the suffix's cells took the
    /// page where the line has the terminal's own.
    private static func styleBefore(_ line: String, column: Int) -> String {
        var state = SGRState()
        let netted = line.ansiStateBefore(visibleColumn: column)
        if !netted.isEmpty { state.apply(netted) }
        if field(line, at: column, includingBoundary: false) == .statedTerminalField {
            state.setBackground(.statedTerminalField)
        }
        return state.rendered
    }

    /// The fields the split notes under the covered columns are what the line has
    /// in force at each of them, and it calls them uniform exactly when they are
    /// one field.
    private func expectFieldsUnderTheOverlay(
        _ fused: ANSIOverlaySplit, _ line: String, _ covered: Range<Int>, _ label: String
    ) {
        let fields = fused.fieldsUnderOverlay.fields(over: covered)
        let expected = covered.map { Self.field(line, at: $0) }
        #expect(fields == expected, "\(label) fields under \(covered)")
        let oneField = expected.dropFirst().allSatisfy { $0 == expected[0] }
        #expect(fused.fieldsUnderOverlay.isUniform == oneField, "\(label) uniform under \(covered)")
    }

    @Test("Plain text matches the helpers at every split point")
    func plainText() {
        assertMatchesHelpers("hello world", "plain")
        assertMatchesHelpers("", "empty")
        assertMatchesHelpers("x", "single")
    }

    @Test("Styled text matches, including escapes either side of both splits")
    func styledText() {
        assertMatchesHelpers("\u{1B}[31mred\u{1B}[0m plain", "leading style")
        assertMatchesHelpers("plain \u{1B}[1mbold\u{1B}[0m", "trailing style")
        assertMatchesHelpers("\u{1B}[44ma\u{1B}[31mb\u{1B}[0mc\u{1B}[4md", "interleaved")
        assertMatchesHelpers("\u{1B}[0m\u{1B}[7m inverted \u{1B}[0m", "inverted chip")
    }

    /// The case the doc comments on `insertOverlay` single out: a wide glyph
    /// straddling a split point cannot be shown whole, so the splitters drop it
    /// and the caller pads the shortfall. The fused scan has to drop it in
    /// exactly the same place.
    @Test("Wide characters straddling either split match")
    func wideCharacters() {
        assertMatchesHelpers("ab😀cd", "emoji mid")
        assertMatchesHelpers("😀😀😀", "all wide")
        assertMatchesHelpers("日本語テキスト", "CJK")
        assertMatchesHelpers("\u{1B}[32m日\u{1B}[0m本x😀", "styled wide mix")
        assertMatchesHelpers("a\u{FE0F}b", "variation selector")
    }

    /// A seeded sweep, so the equivalence is pinned over shapes nobody thought
    /// to hand-write.
    @Test("Randomised lines match the helpers")
    func randomisedSweep() {
        // Three ways to change the field — a colour, a reset, a stated 49 — so the
        // fields noted under the overlay meet every one.
        let pieces = [
            "a", "bb", "😀", "日", "\u{1B}[31m", "\u{1B}[0m", "\u{1B}[1m", " ", "\u{1B}[44m",
            "\u{1B}[49m", "\u{1B}[48;5;196m",
        ]
        var seed: UInt64 = 0x5715_2025
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(pieces.count))
        }
        for sample in 0..<40 {
            var line = ""
            for _ in 0..<(3 + sample % 7) { line += pieces[next()] }
            assertMatchesHelpers(line, "random #\(sample)")
        }
    }
}
