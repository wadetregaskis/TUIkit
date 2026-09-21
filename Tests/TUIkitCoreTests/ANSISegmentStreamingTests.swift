//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSISegmentStreamingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// Pins `forEachANSISegment(_:)` — the streaming walk every splitter now runs
/// on — to `ansiSegments()`, the array form it replaced and which the rest of
/// this directory already uses as an oracle.
///
/// Two claims, and the second is the one worth a suite of its own:
///
/// 1. **Same segments, same order.** The streaming walk yields visible runs
///    character by character without copying each run out into a `String`
///    first, whenever the characters are plain ASCII. That shortcut rests on a
///    Unicode claim — two consecutive ASCII scalars always have a grapheme
///    break between them, CR LF excepted, because nothing that extends a
///    cluster is ASCII — so the corpus below is built to break it if it is
///    wrong: combining marks after ASCII, a CR LF pair, ZWJ sequences, skin
///    tones split across an escape, and an `Extend` scalar immediately after a
///    sequence's terminator (the exact case the scalar-level scan exists for).
///
/// 2. **Stopping is honoured, and immediately.** A clip wants the first few
///    cells; the array form gave it the whole line. A walk that "stops" by
///    ignoring the rest would be no faster, so what is asserted is the count of
///    segments the body actually saw.
@Suite("Streaming ANSI segments")
struct ANSISegmentStreamingTests {

    private static let corpus: [String] = [
        "",
        "x",
        "plain ascii content",
        "\u{1B}[31mred\u{1B}[0m",
        "\u{1B}[38;5;40m status\u{1B}[0m ",
        "\u{1B}[48;5;17m selected row   \u{1B}[0m",
        "abc\u{1B}[31mdef\u{1B}[0m   ",
        // An `Extend` scalar right after a terminator — the fusion the walk is
        // scalar-level to avoid.
        "\u{1B}[31m\u{1F3FD}tail",
        "\u{1B}[1mA\u{0308}\u{1B}[0m",  // combining diaeresis after ASCII
        "line one\r\nline two",  // the one ASCII pair that is a single cluster
        "👋🏽 hi 👨‍👩‍👧‍👦 fam ❤️ love 🇺🇸 flag",
        "日本語テスト ",
        "mix 日本 and ascii  ",
        "content\u{1B}[0 q  ",  // CSI carrying an intermediate space
        "\u{1B}(Bhello",  // nF escape
        "\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\",  // OSC 8
        "\u{1B}]8;;u\u{9C}abc",  // OSC closed by an 8-bit ST
        "\u{1B}[?25lhidden",
        "trailing escape\u{1B}[",  // truncated CSI
        "\u{1B}",  // a lone ESC
    ]

    /// Equal as *values*: `ANSISegment` is not `Equatable`, so the comparison
    /// is on a rendering of each case that keeps both payloads apart.
    private func describe(_ segment: ANSISegment) -> String {
        switch segment {
        case .ansi(let sequence, let isSGR): "A\(isSGR ? "s" : "-"):\(Array(sequence.unicodeScalars.map(\.value)))"
        case .visible(let character): "V:\(Array(character.unicodeScalars.map(\.value)))"
        }
    }

    /// The independent oracle: the scalar-accumulating walk `ansiSegments()`
    /// used to be, before it became a thin wrapper over the streaming one.
    ///
    /// It is spelled out here rather than called, because `ansiSegments()` is
    /// now BUILT on `forEachANSISegment` — comparing them would assert nothing.
    /// (A first draft of this suite did exactly that, and passed with the ASCII
    /// shortcut's guard deleted.) Every visible run is copied out and
    /// grapheme-clustered whole, which is the behaviour the shortcut claims to
    /// reproduce without the copy.
    private func referenceSegments(_ value: String) -> [String] {
        var segments: [String] = []
        let scalars = value.unicodeScalars
        var index = scalars.startIndex
        var visible = String.UnicodeScalarView()

        func flushVisible() {
            guard !visible.isEmpty else { return }
            for character in String(visible) { segments.append(describe(.visible(character))) }
            visible = String.UnicodeScalarView()
        }

        while index < scalars.endIndex {
            guard scalars[index].value == 0x1B else {
                visible.append(scalars[index])
                index = scalars.index(after: index)
                continue
            }
            flushVisible()
            let (end, isSGR) = String.escapeSequenceEnd(startingAt: index, in: scalars)
            segments.append(describe(.ansi(String(scalars[index..<end]), isSGR: isSGR)))
            index = end
        }
        flushVisible()
        return segments
    }

    @Test("Yields exactly what the copy-every-run walk does")
    func matchesTheReferenceWalk() {
        for line in Self.corpus {
            var streamed: [String] = []
            let finished = line.forEachANSISegment { segment in
                streamed.append(describe(segment))
                return true
            }
            #expect(finished, "an unstopped walk reaches the end: \(line.debugDescription)")
            #expect(
                streamed == referenceSegments(line),
                "segments differ for \(line.debugDescription)")
        }
    }

    @Test("A body that stops is not called again")
    func stoppingIsImmediate() {
        for line in Self.corpus {
            let total = line.ansiSegments().count
            guard total > 1 else { continue }
            for stopAfter in 1...total {
                var seen = 0
                let finished = line.forEachANSISegment { _ in
                    seen += 1
                    return seen < stopAfter
                }
                #expect(seen == stopAfter, "stopped late in \(line.debugDescription)")
                // Stopping on the LAST segment still counts as stopped: the
                // body said so, and the walk has no way to know it was the end.
                #expect(!finished, "reported finished though the body stopped")
            }
        }
    }

    /// The ASCII shortcut's boundary: the same run reached through an escape
    /// must cluster the same way it would standing alone, and that is what a
    /// run being clustered independently means.
    @Test("An escape never fuses its terminator onto the text after it")
    func escapeTerminatorNeverFuses() {
        let line = "\u{1B}[31m\u{1F3FD}x"
        let visible = line.ansiSegments().compactMap { segment -> Character? in
            if case .visible(let character) = segment { return character }
            return nil
        }
        #expect(visible.count == 2, "the modifier is its own cluster, not part of the escape")
        #expect(visible.last == "x")
    }
}

/// `leavesSGROpen` asks one question — is anything still in force at the end of
/// this line — and its answer decides whether a truncated cell gets a closing
/// reset. The parameter test under it became byte-wise; these pin what that did
/// and did not change.
@Suite("SGR left open at the end of a line")
struct LeavesSGROpenTests {

    @Test("Plain text leaves nothing open")
    func plainLeavesNothing() {
        #expect(!"no escapes here".leavesSGROpen)
        #expect(!"".leavesSGROpen)
    }

    @Test("The LAST SGR decides, not any before it")
    func lastSGRDecides() {
        #expect("\u{1B}[31mred".leavesSGROpen)
        #expect(!"\u{1B}[31mred\u{1B}[0m".leavesSGROpen)
        #expect("\u{1B}[31mred\u{1B}[0m\u{1B}[1m".leavesSGROpen)
        #expect(!"\u{1B}[1m\u{1B}[4m\u{1B}[m".leavesSGROpen, "a bare ESC[m is a reset")
        #expect(!"\u{1B}[0;0mx".leavesSGROpen)
        #expect(!"\u{1B}[;mx".leavesSGROpen, "empty parameters default to 0")
        #expect("\u{1B}[0;1mx".leavesSGROpen)
        #expect("\u{1B}[1;0mx".leavesSGROpen, "a non-zero parameter counts even before a zero")
        #expect(!"\u{1B}[00mx".leavesSGROpen)
    }

    @Test("A non-SGR escape decides nothing")
    func nonSGRIsIgnored() {
        #expect("\u{1B}[31mred\u{1B}[2J".leavesSGROpen, "the erase does not close the colour")
        #expect(!"\u{1B}[0m\u{1B}[?25l".leavesSGROpen)
    }

    /// The one deliberate divergence from the `Int(_:)` parse this replaced:
    /// `Int("-0")` is zero, so `ESC[-0m` used to read as a reset. `-` is a
    /// legal CSI parameter byte and not a legal SGR one, so the sequence is
    /// one that cannot be PROVEN to be a reset — and the documented rule for
    /// that case is to count it open, because erring the other way bleeds the
    /// attribute over whatever is appended next.
    @Test("A sequence that cannot be proven a reset counts as open")
    func unprovableCountsAsOpen() {
        #expect("\u{1B}[-0m".leavesSGROpen)
        #expect("\u{1B}[0:0m".leavesSGROpen, "a colon sub-parameter is not parsed")
    }
}
