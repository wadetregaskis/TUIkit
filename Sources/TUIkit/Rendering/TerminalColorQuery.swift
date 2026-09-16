//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitStyling

// MARK: - What the terminal said about its colours

/// A terminal's answers to ``TerminalColorQuery``'s requests, as they arrived:
/// nothing filled in, nothing guessed.
///
/// A local value, and NOT the process-wide record of the terminal's colours
/// that rendering reads, `TerminalColors`:
/// ``TerminalColorQuery/resolve(_:environment:)`` turns this into one.
struct TerminalColorReport: Equatable, Sendable {

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
    var foreground: TerminalColors.RGB?

    /// The default background (OSC 11), or `nil` if the terminal did not say.
    var background: TerminalColors.RGB?

    /// Slots 0 to 15 (OSC 4), each `nil` until its reply arrives. Sixteen
    /// entries.
    var slots: [TerminalColors.RGB?] = Array(repeating: nil, count: slotCount)

    /// What a `CSI ? 997 ; Ps n` report said, or `nil` for none.
    ///
    /// Not a colour. ``TerminalColorQuery/resolve(_:environment:)`` reads it
    /// for `prefersDark` only when OSC 11 went unanswered: Ghostty's did not
    /// follow the background it painted, and under tmux it is tmux's own
    /// reading of the client's background (both measured).
    var appearance: Appearance?

    /// Whether the status fence's reply, `CSI 0 n`, arrived.
    var sawStatusFence = false
}

// MARK: - Asking a terminal for its colours

/// The requests that ask a terminal for its default foreground (OSC 10),
/// background (OSC 11) and sixteen ANSI slots (OSC 4), and the parsers for
/// what comes back.
///
/// `TerminalClient.detectColors(using:)` asks once at startup, before the
/// first frame. It sends ``startupRequest(isTmux:)`` through
/// `Terminal.fencedExchange(request:timeout:sawFence:)`, reads to
/// ``sawStatusFence(_:)``, hands back what ``isReply(_:)`` and
/// ``isStatusFence(_:)`` do not claim, and publishes
/// ``colorsToPublish(_:environment:)`` of ``parse(_:)``. Nothing asks again
/// later yet, so ``slotsRequest`` is not sent.
///
/// An answer that arrives after that exchange has closed is not lost: the input
/// parser keeps it (`Terminal.noteVolunteeredColorReply`) instead of dropping it
/// with the rest of what nobody typed, and `TerminalColorRefresher` applies it
/// through ``refreshed(_:over:environment:)``.
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
    private static func color(fromSpec spec: ArraySlice<UInt8>) -> TerminalColors.RGB? {
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
        return TerminalColors.RGB(red: values[0], green: values[1], blue: values[2])
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

    /// What the process record of the terminal's colours holds, given what the
    /// terminal said and the environment the process runs in.
    ///
    /// Nothing is filled in:
    /// - Each default colour is the one reported, or `nil`. A reported
    ///   foreground says nothing about the background, nor the other way round.
    /// - Slots are all sixteen, or `nil`. A partial table cannot say what the
    ///   slots it lacks paint, and mixing reported slots with xterm's values
    ///   would describe no terminal at all.
    /// - `prefersDark` is the first of these that says anything:
    ///   1. The reported background: dark when white contrasts with it at least
    ///      as much as black does (WCAG ratio), so grey 117 is dark and 118
    ///      light.
    ///   2. A `CSI ? 997 ; Ps n` report. It ranks below the background because
    ///      Ghostty 1.3.1 answered `997;2` (light) on a black background, and
    ///      under tmux 3.7c it is tmux's own reading of the background (both
    ///      measured).
    ///   3. `COLORFGBG`'s last field, a slot number: dark for 0–6 and 8, light
    ///      for 7 and 9–15. Ignored under tmux or screen, because a pane's
    ///      environment comes from whatever started the session, so the variable
    ///      can describe a terminal that is no longer attached (inferred, not
    ///      measured: it was unset in every pane probed).
    ///
    /// A terminal that said nothing, in an environment with nothing to say, is
    /// `TerminalColors.unknown`.
    ///
    /// For a report that arrived once something was already published, see
    /// ``refreshed(_:over:environment:)``.
    static func resolve(_ report: TerminalColorReport, environment: [String: String]) -> TerminalColors {
        var resolved = TerminalColors(foreground: report.foreground, background: report.background)
        let answered = report.slots.compactMap { $0 }
        if answered.count == report.slots.count {
            resolved.slots = TerminalColors.Slots(answered)
        }
        if let background = report.background {
            resolved.prefersDark = isDark(background)
        } else if let appearance = report.appearance {
            resolved.prefersDark = appearance == .dark
        } else if !isMultiplexed(environment) {
            resolved.prefersDark = environment["COLORFGBG"].flatMap(prefersDark(colorFgBg:))
        }
        return resolved
    }

    /// The record after a report that arrived once `known` was published: what
    /// the report says, over what was already known.
    ///
    /// A late answer is not a fresh start. A terminal that reports its sixteen
    /// slots after the exchange closed — tmux, whose silent client holds the
    /// fence about half a second (measured) — has said nothing about the default
    /// pair it answered before, and ``resolve(_:environment:)`` reads a silence as
    /// `nil`. So each field the report does not fill keeps what was known, and
    /// each field it fills replaces it, `prefersDark` included: a background
    /// reported now outranks a hint published then, by `resolve`'s own ranking.
    static func refreshed(
        _ report: TerminalColorReport, over known: TerminalColors, environment: [String: String]
    ) -> TerminalColors {
        var refreshed = resolve(report, environment: environment)
        if refreshed.foreground == nil { refreshed.foreground = known.foreground }
        if refreshed.background == nil { refreshed.background = known.background }
        if refreshed.slots == nil { refreshed.slots = known.slots }
        if refreshed.prefersDark == nil { refreshed.prefersDark = known.prefersDark }
        return refreshed
    }

    /// Whether `rgb` is a dark background: white contrasts with it at least as
    /// much as black does (WCAG ratio), so a tie is dark.
    private static func isDark(_ rgb: TerminalColors.RGB) -> Bool {
        let color = Color.rgb(rgb.red, rgb.green, rgb.blue)
        return color.contrastRatio(against: .rgb(255, 255, 255)) >= color.contrastRatio(against: .rgb(0, 0, 0))
    }

    /// Whether the process runs inside tmux or GNU screen, where an inherited
    /// `COLORFGBG` can describe a terminal that is no longer attached.
    private static func isMultiplexed(_ environment: [String: String]) -> Bool {
        if TerminalHost.detectTmux(environment: environment) { return true }
        if let session = environment["STY"], !session.isEmpty { return true }
        return false
    }

    /// What `COLORFGBG` says about the background, or `nil` when it has fewer
    /// than two fields or its last field is not a slot number (`default`, empty,
    /// out of range).
    ///
    /// `fg;bg`, or `fg;default;bg` as rxvt spells it: the last field is the
    /// background's slot. Slots 0–6 and 8 (black, the six dark hues, bright
    /// black) are the dark ones.
    private static func prefersDark(colorFgBg value: String) -> Bool? {
        let fields = value.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 2, let field = fields.last,
            let slot = ASCIIDecimal.value(of: field.utf8),
            (0..<TerminalColorReport.slotCount).contains(slot)
        else { return nil }
        return slot <= 6 || slot == 8
    }
}

// MARK: - Asking at startup

extension TerminalColorQuery {

    /// How long the startup exchange waits for its fence: half a second, as
    /// the other startup exchanges wait for theirs.
    ///
    /// Only a terminal that answers no `CSI 5 n` waits it out, because the
    /// read ends when the fence lands. Every measured host answered it.
    static let startupTimeout = 0.5

    /// The request the startup exchange sends: ``tmuxStartupRequest`` under
    /// tmux, ``nativeRequest`` everywhere else.
    static func startupRequest(isTmux: Bool) -> String {
        isTmux ? tmuxStartupRequest : nativeRequest
    }

    /// What the startup exchange publishes: ``resolve(_:environment:)`` of
    /// what the terminal said, or `nil` when that says nothing at all.
    ///
    /// `nil` leaves `TerminalColors.current` as it was, `unknown` at startup,
    /// rather than assigning `unknown` over it. A terminal that answered no
    /// colour and no `997` still publishes what `COLORFGBG` says about dark,
    /// which is a statement from the environment, not a colour guessed for
    /// the terminal.
    static func colorsToPublish(
        _ report: TerminalColorReport, environment: [String: String]
    ) -> TerminalColors? {
        let resolved = resolve(report, environment: environment)
        return resolved == .unknown ? nil : resolved
    }
}

extension Terminal {

    /// Asks the terminal for its colours, or returns `nil` without asking when
    /// stdin is not a TTY in raw mode.
    ///
    /// The same exchange as ``queryGraphicsSupport(timeout:)``: one write
    /// through ``fencedExchange(request:timeout:sawFence:)``, then read until
    /// the status fence lands or the deadline passes. What arrives and is not
    /// a reply, a keystroke typed while the app starts or a focus report, goes
    /// back to the input parser through
    /// ``handBackUnconsumed(from:isReply:isFence:)``.
    ///
    /// Asked of every host, measured or not. No measured host printed any of
    /// these queries, and one that answers none of them costs the round trip
    /// to its fence.
    func queryColors(timeout: Double = TerminalColorQuery.startupTimeout) -> TerminalColorReport? {
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return nil }
        return askColors(isTmux: TerminalHost.isTmux, timeout: timeout)
    }

    /// The exchange behind ``queryColors(timeout:)``, without its guard.
    ///
    /// Apart so a test can run the exchange through ``readSource`` and
    /// ``exchangeTransport``: the guard wants a real TTY in raw mode, which a
    /// test process does not have.
    func askColors(
        isTmux: Bool, timeout: Double = TerminalColorQuery.startupTimeout
    ) -> TerminalColorReport {
        let collected = fencedExchange(
            request: TerminalColorQuery.startupRequest(isTmux: isTmux), timeout: timeout,
            sawFence: TerminalColorQuery.sawStatusFence)
        handBackUnconsumed(
            from: collected, isReply: TerminalColorQuery.isReply,
            isFence: TerminalColorQuery.isStatusFence)
        return TerminalColorQuery.parse(collected)
    }
}

extension TerminalClient {

    /// Asks the terminal for its colours at startup, and publishes what it
    /// said to `TerminalColors.current`.
    ///
    /// Run once, before `RenderLoop` is built, so the first frame is drawn
    /// with whatever the terminal reported. A terminal that says nothing leaves
    /// the record as it was. A reply later than the deadline is not read here:
    /// the input parser siphons it out of the keystrokes instead, and
    /// `TerminalColorRefresher` publishes what it adds to what was known.
    @MainActor
    static func detectColors(using terminal: Terminal) {
        guard let report = terminal.queryColors(),
            let colors = TerminalColorQuery.colorsToPublish(
                report, environment: ProcessInfo.processInfo.environment)
        else { return }
        TerminalColors.current = colors
    }
}
