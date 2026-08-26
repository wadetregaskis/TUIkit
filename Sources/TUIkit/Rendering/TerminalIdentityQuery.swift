//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalIdentityQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - What the terminal said about itself

/// A terminal's answers to the identity queries in ``TerminalIdentityQuery``.
///
/// Deliberately holds the replies verbatim rather than a verdict: the parse is
/// mechanical and testable, the verdict is a judgement about measured terminal
/// behaviour, and keeping them apart means the judgement can be argued with
/// (and unit-tested) without a terminal in the room.
struct TerminalIdentity: Equatable {
    /// The Primary Device Attributes reply (`ESC[?…c`), verbatim, or `nil` if
    /// the terminal did not answer.
    var primaryAttributes: String?

    /// The Secondary Device Attributes reply (`ESC[>…c`), verbatim, or `nil`.
    var secondaryAttributes: String?

    /// Whether the terminal answered XTVERSION at all. The *content* is not
    /// needed here — under ``TerminalHost/hostProgram(environment:)`` a
    /// terminal that answers XTVERSION either named itself in the environment
    /// or is one tmux's client identification already handles; what matters to
    /// the fingerprint below is that Apple Terminal answers **nothing**.
    var answeredVersion: Bool = false

    /// Whether the DSR fence's reply was seen. The exchange is complete once
    /// it has been: every terminal answers DSR, and it is sent last, so its
    /// arrival means every earlier query has either answered or declined to.
    var sawFence: Bool = false

    /// Bytes that arrived during the exchange and are not replies to it —
    /// keystrokes typed while the app was starting. They belong to the input
    /// parser, and dropping them would silently eat a keypress.
    var unconsumed: [UInt8] = []
}

// MARK: - Asking

/// The startup exchange that asks a terminal who it is.
///
/// ## Why this exists
///
/// `TERM_PROGRAM` does not cross an ssh hop (see
/// ``TerminalHost/hostProgram(environment:)``), and the one host whose
/// cursor-advance quirks most need compensating — Apple Terminal — sets no
/// variable ssh forwards and answers no XTVERSION. An escape query has neither
/// problem: it is answered by the terminal itself, at the far end of however
/// many hops.
///
/// ## Shape of the exchange
///
/// One write, one round trip. The queries are sent back to back and finished
/// with a DSR cursor-position request, which every terminal answers; reading
/// until that reply arrives means a query nobody implements costs nothing and
/// hangs nothing.
///
/// **CSI queries only.** A DCS query (XTGETTCAP, `ESC P + q … ESC \`) is not
/// safe here: Apple Terminal does not parse DCS and *prints the payload* —
/// measured, it left a literal `+q544e` on the screen. Every query below is a
/// CSI sequence, which even a terminal that implements none of them consumes
/// correctly, because CSI parsing is generic (parameter bytes, then a final
/// byte).
enum TerminalIdentityQuery {

    /// The queries, in the order their replies come back:
    /// XTVERSION (`ESC[>0q`), DA1 (`ESC[c`), DA2 (`ESC[>c`), then the DSR
    /// fence (`ESC[6n`) that ends the read.
    static let request = "\u{1B}[>0q\u{1B}[c\u{1B}[>c\u{1B}[6n"

    /// Sorts a raw reply buffer into ``TerminalIdentity``.
    ///
    /// Walks escape sequences with the repo's canonical CSI rule
    /// (``Swift/String/isCSIBodyByte(_:)`` /
    /// ``Swift/String/isCSIFinalByte(_:)``) rather than "digits and `;` then a
    /// letter", which stops at the `?` of a DA1 reply and would strand the rest
    /// as text.
    ///
    /// Anything that is not one of the replies asked for is preserved in
    /// ``TerminalIdentity/unconsumed`` — a keystroke that landed during the
    /// round trip is the user's, not ours.
    static func parse(_ bytes: [UInt8]) -> TerminalIdentity {
        var identity = TerminalIdentity()
        var index = bytes.startIndex

        while index < bytes.endIndex {
            guard bytes[index] == 0x1B else {
                // Not an escape at all, so not a reply: someone typed while the
                // app was starting. Keep it and carry on — abandoning the walk
                // here would strand every reply after it, and the replies are
                // what we came for.
                identity.unconsumed.append(bytes[index])
                index += 1
                continue
            }
            // A trailing bare ESC, or a sequence whose tail has not arrived, is
            // a split sequence: not ours to interpret, so hand back the rest.
            guard index + 1 < bytes.endIndex,
                let next = consume(bytes, from: index, into: &identity)
            else {
                identity.unconsumed.append(contentsOf: bytes[index...])
                return identity
            }
            if identity.sawFence {
                identity.unconsumed.append(contentsOf: bytes[next...])
                return identity
            }
            index = next
        }
        return identity
    }

    /// Consumes the one escape sequence beginning at `index`, recording what it
    /// says, and returns the index just past it — or `nil` if it is truncated.
    private static func consume(
        _ bytes: [UInt8], from index: Int, into identity: inout TerminalIdentity
    ) -> Int? {
        switch bytes[index + 1] {
        case 0x5B: return consumeCSI(bytes, from: index, into: &identity)
        case 0x50: return consumeDCS(bytes, from: index, into: &identity)
        default:
            // ESC followed by anything else is not a reply we asked for.
            identity.unconsumed.append(bytes[index])
            return index + 1
        }
    }

    /// The CSI branch: a DA1 reply, a DA2 reply, the DSR fence, or someone's
    /// arrow key.
    private static func consumeCSI(
        _ bytes: [UInt8], from index: Int, into identity: inout TerminalIdentity
    ) -> Int? {
        var end = index + 2
        while end < bytes.endIndex, String.isCSIBodyByte(UInt32(bytes[end])) { end += 1 }
        guard end < bytes.endIndex, String.isCSIFinalByte(UInt32(bytes[end])) else { return nil }
        // The first parameter byte is what tells a DA1 reply (`?`) from a DA2
        // reply (`>`); `end > index + 2` guards a parameterless `ESC[c`, where
        // that byte IS the final one.
        let lead: UInt8? = end > index + 2 ? bytes[index + 2] : nil
        switch (bytes[end], lead) {
        case (0x63, 0x3F):  // 'c' after '?' — Primary Device Attributes
            identity.primaryAttributes = ascii(bytes[index...end])
        case (0x63, 0x3E):  // 'c' after '>' — Secondary Device Attributes
            identity.secondaryAttributes = ascii(bytes[index...end])
        case (0x52, _):  // 'R' — the DSR fence, which ends the exchange
            identity.sawFence = true
        default:
            identity.unconsumed.append(contentsOf: bytes[index...end])
        }
        return end + 1
    }

    /// The DCS branch. Any DCS here is an XTVERSION reply — it is the only
    /// query in ``request`` that answers with one — so its content is not
    /// examined, only its existence.
    private static func consumeDCS(
        _ bytes: [UInt8], from index: Int, into identity: inout TerminalIdentity
    ) -> Int? {
        var end = index + 2
        while end < bytes.endIndex {
            if bytes[end] == 0x07 { break }  // BEL terminator
            if bytes[end] == 0x1B, end + 1 < bytes.endIndex, bytes[end + 1] == 0x5C {
                end += 1  // ST — ESC \
                break
            }
            end += 1
        }
        guard end < bytes.endIndex else { return nil }
        identity.answeredVersion = true
        return end + 1
    }

    /// An escape sequence as a `String`. Every byte of a CSI sequence is ASCII
    /// by construction — ESC, `[`, parameter bytes (`0x20...0x3F`) and a final
    /// byte (`0x40...0x7E`) — so each maps to exactly one scalar, and there is
    /// no decoding to get wrong.
    private static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        var text = ""
        text.unicodeScalars.append(contentsOf: bytes.map { Unicode.Scalar($0) })
        return text
    }
}

// MARK: - The verdict

extension TerminalHost {

    /// The `TERM_PROGRAM`-style name of the terminal that gave these answers,
    /// or `nil` for one they do not positively identify.
    ///
    /// `nil` is the overwhelmingly common answer and the safe one: absent
    /// explicit evidence, a terminal is assumed to render correctly, and every
    /// compensation gated on a host name works around a *measured defect*.
    /// Naming a terminal that does not have those defects would break rows that
    /// were fine, so this identifies exactly one host and does it by
    /// conjunction.
    ///
    /// **Apple Terminal**, measured 2026-08-26 (Terminal.app 455.1, macOS 15.7,
    /// through an ssh hop, `Tools/TerminalProbes/identity_probe.py`):
    ///
    /// | Query | Apple Terminal | Ghostty | Warp | iTerm2 |
    /// |---|---|---|---|---|
    /// | XTVERSION | *silent* | answers | answers | answers |
    /// | DA1 | `ESC[?1;2c` | `ESC[?62;22c` | `ESC[?62c` | `ESC[?62;…c` |
    /// | DA2 | `ESC[>1;95;0c` | `ESC[>1;10;0c` | — | `ESC[>…;…;0c` |
    ///
    /// (Ghostty's and Warp's replies were read out of their shipped binaries;
    /// the XTVERSION column is the measured table in
    /// `Documentation/Terminal-compatibility.md`.)
    ///
    /// All three clauses carry weight, and each excludes something the others
    /// do not:
    ///
    /// - **XTVERSION silence** excludes every terminal that answers it — the
    ///   three above, and kitty, WezTerm, foot and contour besides.
    /// - **DA1 `ESC[?1;2c`** is "VT100 with the Advanced Video Option", a 1978
    ///   feature set. Modern emulators report VT220 or later (`?62`, `?63`,
    ///   `?64`) because applications gate features on it, so this is the clause
    ///   that does most of the work.
    /// - **DA2 `ESC[>1;…;0c`** excludes the multiplexers, which are the real
    ///   collision risk for the DA1 clause: GNU screen also reports VT100+AVO,
    ///   but identifies itself as terminal type 83 (`'S'`), and xterm as 41.
    ///   tmux never reaches here — it is detected from `$TMUX` first — but
    ///   screen is not detected at all, and applying Apple Terminal's
    ///   compensation inside a multiplexer would corrupt its grid.
    ///
    /// The firmware field of DA2 is deliberately **not** pinned to the measured
    /// `95`: it is a version number by definition, and matching it exactly
    /// would mean a macOS update silently switching the compensation back off —
    /// which is precisely the failure this whole path exists to end. The
    /// identifying fields are the terminal type (`1`) and the ROM cartridge
    /// (`0`).
    static func nameFromDeviceAttributes(_ identity: TerminalIdentity) -> String? {
        guard !identity.answeredVersion,
            identity.primaryAttributes == "\u{1B}[?1;2c",
            let secondary = identity.secondaryAttributes,
            secondary.hasPrefix("\u{1B}[>1;"), secondary.hasSuffix(";0c")
        else { return nil }
        return "Apple_Terminal"
    }
}

// MARK: - Seeding what was discovered

extension TerminalHost {

    /// What the startup Device Attributes exchange asked and was told, kept for
    /// the diagnostic surface (``TerminalClient/current``).
    ///
    /// `nil` when the exchange never ran — the environment already named the
    /// host, or we are in a tmux pane, or there is no terminal at all. Nothing
    /// in rendering reads this; the answer itself travels through the
    /// environment (see ``seedDiscoveredHost(_:)``), which is what keeps a
    /// single source of truth for "which terminal is this".
    @MainActor static var startupIdentity: TerminalIdentity?

    /// Runs the identity exchange, records it, and seeds whatever it named.
    ///
    /// The one entry point, so that the recording and the seeding cannot drift
    /// apart: a diagnostic that reported a different host from the one actually
    /// being compensated for would be worse than no diagnostic.
    ///
    /// - Parameter terminal: the terminal to ask — it owns stdin, the termios
    ///   state the replies depend on, and the input buffer any stray keystrokes
    ///   have to be handed back to.
    /// - Returns: the name discovered, or `nil`.
    @MainActor @discardableResult
    static func identify(using terminal: Terminal) -> String? {
        let (identity, name) = terminal.queryIdentity()
        startupIdentity = identity
        if let name { seedDiscoveredHost(name) }
        return name
    }

    /// Records a host discovered at runtime, so every existing reader of
    /// ``isAppleTerminal`` and friends sees it.
    ///
    /// It goes into the process environment — the same place the answer would
    /// have come from had ssh forwarded it — rather than into a new global.
    /// That keeps exactly one source of truth for "which terminal is this",
    /// and means nothing downstream needs to know the answer arrived late.
    ///
    /// - Important: the detectors are `static let`, so each freezes on first
    ///   read. This must therefore run **before** anything reads one, which in
    ///   practice means before the render loop (and its `FrameDiffWriter`) is
    ///   constructed. `Tools/Smoke/identity_smoke.py` is what holds that
    ///   ordering: nothing in the type system can.
    ///
    /// - Parameter name: a `TERM_PROGRAM`-style name, as
    ///   ``nameFromDeviceAttributes(_:)`` returns.
    static func seedDiscoveredHost(_ name: String) {
        setenv("TUIKIT_TERM_PROGRAM", name, 1)
    }
}
