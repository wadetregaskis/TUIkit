//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - What the terminal said about its colours

/// A terminal's answers to ``TerminalColorQuery``'s requests, as they arrived:
/// nothing filled in, nothing guessed.
///
/// A local value, and NOT the process-wide record of the terminal's colours
/// that rendering will read: that record's shape is still being decided.
/// ``TerminalColorQuery/resolve(_:)`` turns this into a ``Resolved`` whose
/// fields are the ones that record needs, so it can be built field for field.
struct TerminalColorReport: Equatable, Sendable {

    /// A reported colour, scaled to eight bits per channel.
    struct RGB: Hashable, Sendable {
        /// The red channel.
        var red: UInt8
        /// The green channel.
        var green: UInt8
        /// The blue channel.
        var blue: UInt8

        /// `#000000`.
        static let black = Self(red: 0, green: 0, blue: 0)
        /// `#ffffff`.
        static let white = Self(red: 255, green: 255, blue: 255)
    }

    /// Which theme a `CSI ? 997 ; Ps n` report names.
    enum Appearance: Equatable, Sendable {
        /// `Ps` = 1.
        case dark
        /// `Ps` = 2.
        case light
    }

    /// How many ANSI slots are asked for: the eight colours and their bright
    /// twins.
    static let slotCount = 16

    /// The default foreground (OSC 10), or `nil` if the terminal did not say.
    var foreground: RGB?

    /// The default background (OSC 11), or `nil` if the terminal did not say.
    var background: RGB?

    /// Slots 0 to 15 (OSC 4), each `nil` until its reply arrives. Sixteen
    /// entries.
    var slots: [RGB?] = Array(repeating: nil, count: slotCount)

    /// What a `CSI ? 997 ; Ps n` report said, or `nil` for none.
    ///
    /// Recorded, and not resolved: it is not a colour, and whether it may
    /// stand in for OSC 11 is a later rung of the plan. Under tmux it is
    /// tmux's own reading of the client's background (measured), so it adds
    /// nothing there.
    var appearance: Appearance?

    /// Whether the status fence's reply, `CSI 0 n`, arrived.
    var sawStatusFence = false
}

// MARK: - What to believe

extension TerminalColorReport {

    /// A report with every gap filled, and each colour marked with where it
    /// came from.
    struct Resolved: Equatable, Sendable {

        /// Where a resolved colour came from.
        enum Source: Equatable, Sendable {
            /// The terminal reported it.
            case reported
            /// The terminal reported the other colour, and this is whichever
            /// of black and white contrasts with it more.
            case inferred
            /// The terminal reported neither colour, so this is the
            /// assumption: black on white.
            case assumed
        }

        /// The default foreground.
        var foreground: RGB
        /// Where ``foreground`` came from.
        var foregroundSource: Source
        /// The default background.
        var background: RGB
        /// Where ``background`` came from.
        var backgroundSource: Source

        /// All sixteen slots, or `nil` when fewer than sixteen answered.
        ///
        /// All or nothing: a partial table cannot answer "what does this
        /// name paint" for the names it lacks, and mixing reported slots with
        /// xterm's defaults would describe no terminal at all.
        var slots: [RGB]?

        /// What a terminal that says nothing is taken to be: black on white,
        /// with no slots.
        ///
        /// Light, because that is the owner's decision for a silent terminal.
        static let assumed = Self(
            foreground: .black, foregroundSource: .assumed,
            background: .white, backgroundSource: .assumed, slots: nil)
    }
}

// MARK: - Asking a terminal for its colours

/// The requests that ask a terminal for its default foreground (OSC 10),
/// background (OSC 11) and sixteen ANSI slots (OSC 4), and the parsers for
/// what comes back.
///
/// Nothing sends these yet. They are the pieces the startup exchange will run
/// through `Terminal.fencedExchange(request:timeout:sawFence:)`, reading to
/// ``sawStatusFence(_:)``, handing back what ``isReply(_:)`` and
/// ``isStatusFence(_:)`` do not claim, then keeping ``resolve(_:)`` of
/// ``parse(_:)``.
///
/// ## The fence
///
/// Each request ends with `CSI 5 n`, a status report every measured host
/// answered with `CSI 0 n`, including screen and Warp, which answer none of
/// the colour queries. It is not `CSI 6 n`, the cursor report the other
/// startup exchanges use, so ``isStatusFence(_:)`` is its own test.
///
/// ## Why OSC and not DCS
///
/// Apple Terminal parses OSC but not DCS or APC, and no measured host printed
/// any of these queries (`Documentation/Terminal-compatibility.md`, "Asking
/// the terminal for its colours").
enum TerminalColorQuery {

    // MARK: Requests

    /// Foreground, background and the sixteen slots, then the fence: the
    /// startup request for a terminal that is not tmux. 170 bytes.
    ///
    /// Every slot is its own query. That is the spelling every measured host
    /// answered; the multi-pair spelling was measured only under tmux.
    static let nativeRequest = foregroundQuery + backgroundQuery + slotQueries + statusQuery

    /// Foreground and background only, then the fence: the startup request
    /// under tmux.
    ///
    /// No slots, because tmux forwards OSC 4 to one client, and when that
    /// client does not answer, the fence waits about half a second (measured
    /// on tmux 3.7c). Foreground and background come from tmux's own record
    /// and are answered in under a millisecond.
    static let tmuxStartupRequest = foregroundQuery + backgroundQuery + statusQuery

    /// The sixteen slots, one query each, then the fence: for asking after the
    /// first frame, where tmux's wait holds up nothing that draws.
    static let slotsRequest = slotQueries + statusQuery

    private static let foregroundQuery = "\u{1B}]10;?\u{1B}\\"
    private static let backgroundQuery = "\u{1B}]11;?\u{1B}\\"
    private static let slotQueries = (0..<TerminalColorReport.slotCount)
        .map { "\u{1B}]4;\($0);?\u{1B}\\" }.joined()
    private static let statusQuery = "\u{1B}[5n"

    // MARK: Telling replies apart

    /// Whether `bytes` holds the fence's reply, `CSI 0 n`, which ends the read.
    ///
    /// The hand-back walk run for its fence alone, its kept bytes discarded:
    /// so the read ends on exactly the sequence the hand-back will treat as
    /// the fence, never on bytes that merely contain `ESC [ 0 n`.
    static func sawStatusFence(_ bytes: [UInt8]) -> Bool {
        var saw = false
        _ = TerminalQueryReplies.unconsumed(
            bytes, isReply: { _ in false },
            isFence: { sequence in
                saw = isStatusFence(sequence)
                return saw
            })
        return saw
    }

    /// Whether one complete escape sequence is `CSI 0 n`, the fence. No key
    /// sends one.
    static func isStatusFence(_ sequence: ArraySlice<UInt8>) -> Bool {
        sequence.elementsEqual([0x1B, 0x5B, 0x30, 0x6E])  // ESC [ 0 n
    }

    /// Whether one complete escape sequence answers this exchange: an OSC 10,
    /// 11 or 4 reply, well formed or not, or a `CSI ? 997 ; Ps n` report.
    ///
    /// A malformed body still counts. The terminal sent it, no key sends an
    /// OSC, and the input parser would only swallow it.
    static func isReply(_ sequence: ArraySlice<UInt8>) -> Bool {
        if let body = oscBody(of: sequence) { return oscCode(of: body) != nil }
        return isAppearanceReport(sequence)
    }

    // MARK: Parsing

    /// What `bytes` says about the terminal's colours.
    ///
    /// Walks whole sequences with the hand-back's own rule, so a reply is
    /// recorded exactly when the hand-back drops it. That includes stopping at
    /// the fence: a reply behind it is left to the input parser, and not
    /// recorded here as well. Every measured reply arrived before its fence.
    ///
    /// A later well-formed reply for the same colour replaces an earlier one.
    /// A malformed reply changes nothing.
    static func parse(_ bytes: [UInt8]) -> TerminalColorReport {
        var report = TerminalColorReport()
        _ = TerminalQueryReplies.unconsumed(
            bytes,
            isReply: { sequence in
                record(sequence, into: &report)
                return isReply(sequence)
            },
            isFence: { sequence in
                report.sawStatusFence = isStatusFence(sequence)
                return report.sawStatusFence
            })
        return report
    }

    /// Records one complete sequence into `report`, when it is a well-formed
    /// reply.
    private static func record(_ sequence: ArraySlice<UInt8>, into report: inout TerminalColorReport) {
        guard let body = oscBody(of: sequence) else {
            if isAppearanceReport(sequence) { report.appearance = appearance(of: sequence) ?? report.appearance }
            return
        }
        guard let code = oscCode(of: body) else { return }
        let fields = body.split(separator: 0x3B, omittingEmptySubsequences: false)  // ';'
        switch code {
        case .foreground where fields.count == 2:
            report.foreground = color(fromSpec: fields[1]) ?? report.foreground
        case .background where fields.count == 2:
            report.background = color(fromSpec: fields[1]) ?? report.background
        case .slot where fields.count == 3:
            guard let index = ASCIIDecimal.value(of: fields[1]),
                report.slots.indices.contains(index),
                let rgb = color(fromSpec: fields[2])
            else { return }
            report.slots[index] = rgb
        default:
            return
        }
    }

    /// The OSC numbers this exchange asks about.
    private enum OSCCode: Int {
        case slot = 4
        case foreground = 10
        case background = 11
    }

    /// The body of an OSC sequence, between `ESC ]` and its BEL or ST, or
    /// `nil` when `sequence` is not an OSC.
    private static func oscBody(of sequence: ArraySlice<UInt8>) -> ArraySlice<UInt8>? {
        let start = sequence.startIndex
        guard sequence.count >= 3, sequence[start] == 0x1B, sequence[start + 1] == 0x5D else {
            return nil
        }
        if sequence.last == 0x07 { return sequence[(start + 2)..<(sequence.endIndex - 1)] }  // BEL
        guard sequence.count >= 4, sequence[sequence.endIndex - 2] == 0x1B, sequence.last == 0x5C
        else { return nil }  // ST
        return sequence[(start + 2)..<(sequence.endIndex - 2)]
    }

    /// Which of this exchange's OSC numbers a body carries, read from the
    /// digits before its first `;`, or `nil` for any other OSC.
    private static func oscCode(of body: ArraySlice<UInt8>) -> OSCCode? {
        guard let semicolon = body.firstIndex(of: 0x3B),
            let number = ASCIIDecimal.value(of: body[..<semicolon])
        else { return nil }
        return OSCCode(rawValue: number)
    }

    private static let appearancePrefix = Array("\u{1B}[?997;".utf8)

    /// Whether one complete sequence is `CSI ? 997 ; Ps n`, whatever `Ps` is.
    private static func isAppearanceReport(_ sequence: ArraySlice<UInt8>) -> Bool {
        sequence.count > appearancePrefix.count && sequence.starts(with: appearancePrefix)
            && sequence.last == 0x6E  // 'n'
    }

    /// The theme a `CSI ? 997 ; Ps n` report names, or `nil` for a `Ps` that
    /// is neither 1 nor 2.
    private static func appearance(of report: ArraySlice<UInt8>) -> TerminalColorReport.Appearance? {
        let digits = report[(report.startIndex + appearancePrefix.count)..<(report.endIndex - 1)]
        switch ASCIIDecimal.value(of: digits) {
        case 1: return .dark
        case 2: return .light
        default: return nil
        }
    }

    // MARK: Colour specs

    private static let rgbPrefix = Array("rgb:".utf8)
    private static let rgbaPrefix = Array("rgba:".utf8)

    /// The colour an XParseColor `rgb:` or `rgba:` spec names, or `nil` for
    /// any other spelling.
    ///
    /// `rgb:` takes three channels and `rgba:` four, separated by `/`. The
    /// alpha is read, so a malformed one refuses the spec, and then ignored:
    /// the colour a terminal paints its default slots with is opaque on its
    /// grid. The prefix is lowercase, as every measured reply spelled it.
    private static func color(fromSpec spec: ArraySlice<UInt8>) -> TerminalColorReport.RGB? {
        let channelCount: Int
        let channelBytes: ArraySlice<UInt8>
        if spec.starts(with: rgbaPrefix) {
            channelCount = 4
            channelBytes = spec.dropFirst(rgbaPrefix.count)
        } else if spec.starts(with: rgbPrefix) {
            channelCount = 3
            channelBytes = spec.dropFirst(rgbPrefix.count)
        } else {
            return nil
        }
        let channels = channelBytes.split(separator: 0x2F, omittingEmptySubsequences: false)  // '/'
        guard channels.count == channelCount else { return nil }
        let values = channels.compactMap(channel)
        guard values.count == channelCount else { return nil }
        return TerminalColorReport.RGB(red: values[0], green: values[1], blue: values[2])
    }

    /// One channel of a spec: one to four hex digits, in either case, scaled
    /// from that many bits to eight and rounded, or `nil` for anything else.
    ///
    /// Rounded, NOT the high byte. The two agree for a terminal that spells an
    /// 8-bit value by repeating it (`e6e6`), but not for a genuine 16-bit
    /// value: iTerm2 reported `18f1`, which is 24.84 of 255, so 25.
    ///
    /// Three digits are XParseColor's own form too, so they are taken, though
    /// no measured host sent anything but four.
    private static func channel(_ digits: ArraySlice<UInt8>) -> UInt8? {
        guard (1...4).contains(digits.count) else { return nil }
        var value = 0
        for byte in digits {
            guard let nibble = hexValue(byte) else { return nil }
            value = value << 4 | nibble
        }
        let maximum = (1 << (4 * digits.count)) - 1
        return UInt8((value * 255 + maximum / 2) / maximum)
    }

    /// The value of one ASCII hex digit, or `nil`.
    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case 0x30...0x39: Int(byte - 0x30)  // 0-9
        case 0x41...0x46: Int(byte - 0x41) + 10  // A-F
        case 0x61...0x66: Int(byte - 0x61) + 10  // a-f
        default: nil
        }
    }

    // MARK: Resolving

    /// What to believe, given what the terminal said.
    ///
    /// - Both colours answered: both are reported.
    /// - One answered: the other is whichever of black and white contrasts
    ///   with it more (WCAG ratio; white on a tie), marked inferred.
    /// - Neither: ``TerminalColorReport/Resolved/assumed``, black on white.
    /// - Slots, on their own: all sixteen or `nil`.
    ///
    /// The `997` report and the environment (`COLORFGBG`) are not consulted.
    /// They are later rungs of the plan, and none has an owner decision yet.
    static func resolve(_ report: TerminalColorReport) -> TerminalColorReport.Resolved {
        var resolved = TerminalColorReport.Resolved.assumed
        switch (report.foreground, report.background) {
        case (let foreground?, let background?):
            resolved.foreground = foreground
            resolved.foregroundSource = .reported
            resolved.background = background
            resolved.backgroundSource = .reported
        case (let foreground?, nil):
            resolved.foreground = foreground
            resolved.foregroundSource = .reported
            resolved.background = contrasting(foreground)
            resolved.backgroundSource = .inferred
        case (nil, let background?):
            resolved.foreground = contrasting(background)
            resolved.foregroundSource = .inferred
            resolved.background = background
            resolved.backgroundSource = .reported
        case (nil, nil):
            break
        }
        let answered = report.slots.compactMap { $0 }
        if report.slots.count == TerminalColorReport.slotCount, answered.count == report.slots.count {
            resolved.slots = answered
        }
        return resolved
    }

    /// Whichever of black and white contrasts more with `rgb`, white on a tie:
    /// the same choice, and the same tie, as the readability floor's last
    /// resort (`Color.ensuringContrast(atLeast:against:)`).
    private static func contrasting(_ rgb: TerminalColorReport.RGB) -> TerminalColorReport.RGB {
        let color = Color.rgb(rgb.red, rgb.green, rgb.blue)
        return color.contrastRatio(against: .rgb(255, 255, 255))
            >= color.contrastRatio(against: .rgb(0, 0, 0)) ? .white : .black
    }
}
