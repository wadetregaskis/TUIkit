//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalGraphicsQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#endif

// MARK: - Asking whether pictures are possible

/// The startup exchange that asks a terminal whether it can draw an image
/// **into the cell grid**.
///
/// ## Why this is asked rather than looked up
///
/// Every other terminal capability in this project is a table: a host is
/// identified, and what it can do is what somebody measured it doing. That is
/// forced on us — no terminal reports whether it honours OSC 8, or how far it
/// advances a keycap. The Kitty graphics protocol is the exception. It has a
/// real handshake, and the handshake answers the question at the granularity
/// that matters:
///
/// - **Warp** answers the *protocol* query `OK` and then refuses a virtual
///   placement by name — `UnicodePlaceholderUnsupported`. A table written from
///   its feature list would have said "supports Kitty graphics" and been
///   wrong about the only part TUIkit uses.
/// - **Ghostty** answers `OK` to both.
/// - **Apple Terminal** and **tmux** answer nothing.
///
/// So the question asked here is not "does this terminal speak the protocol"
/// but "will it place an image for me": a one-pixel image is transmitted, a
/// virtual placement of it is requested, and the image is deleted again. Only
/// `OK` to the *placement* counts.
///
/// ## Why it is not asked of everybody
///
/// This is an APC sequence, and **Apple Terminal does not parse APC** — it
/// prints the payload (measured; `Documentation/Terminal-compatibility.md`).
/// Two defences, because one is a table and tables go stale:
///
/// 1. The exchange is skipped on a host identified as one that prints APC.
/// 2. It is wrapped in save-cursor / restore-cursor / erase-to-end anyway, so
///    an unmeasured terminal with the same parser gap has whatever it printed
///    wiped before the first frame. The payload is kept deliberately tiny
///    (one pixel, ~80 bytes) so that what such a host prints fits in a row.
enum TerminalGraphicsQuery {

    /// The id the handshake borrows. The top of the range, so it cannot
    /// collide with one ``TerminalImageStore`` has allocated — that store
    /// counts up from 1.
    static let probeID: KittyGraphics.ImageID = KittyGraphics.maximumImageID

    /// The id the compression probe borrows — the one below the placement's,
    /// and equally out of the store's reach.
    static let compressionProbeID: KittyGraphics.ImageID = KittyGraphics.maximumImageID - 1

    /// One black pixel, RGBA.
    private static let onePixel: [UInt8] = [0, 0, 0, 0]

    /// A 32×32 black RGBA image, deflated: 4,096 bytes that any zlib inflates
    /// from these twenty-six.
    ///
    /// A constant rather than ``SystemZlib``'s output so the question is asked
    /// the same way on every host, zlib or no zlib — and the SIZE is the
    /// point. A terminal that ignores the `o=z` key would read these bytes as
    /// raw pixels, and twenty-six bytes cannot be a 32×32 picture, so it
    /// errors; one that honours the key inflates them to exactly the 4,096 it
    /// expects and answers `OK`. A one-pixel probe could not tell those apart:
    /// its twelve deflated bytes are MORE than the four a pixel needs, and a
    /// terminal that ignored the key might have accepted them.
    private static let deflatedBlock: [UInt8] = [
        0x78, 0x9C, 0xED, 0xC1, 0x01, 0x0D, 0x00, 0x00, 0x00, 0xC2, 0xA0, 0xF7, 0x4F,
        0x6D, 0x0F, 0x07, 0x14, 0x00, 0x00, 0x00, 0xF0, 0x6E, 0x10, 0x00, 0x00, 0x01,
    ]

    /// The exchange: transmit quietly, ask for a placement out loud, delete
    /// quietly; then offer a deflated transmission out loud and delete that
    /// too; tidy up, and fence with DSR so a silent terminal reports silence
    /// instead of hanging.
    ///
    /// Two commands speak, and they are told apart by id — see ``parse(_:)``.
    /// Everything else is `q=2`, so the reply holds exactly the two answers
    /// and not a chorus of acknowledgements in the same `ESC _ G i=…;` shape.
    static var request: String {
        "\u{1B}[s"  // save the cursor, in case the payload is printed
            + KittyGraphics.transmit(pixels: onePixel, width: 1, height: 1, id: probeID)
            + "\u{1B}_Ga=p,U=1,q=0,i=\(probeID),c=1,r=1\u{1B}\\"
            + KittyGraphics.delete(id: probeID)
            + compressionRequest
            + "\u{1B}[u\u{1B}[J"  // …and wipe it if it was
            + "\u{1B}[6n"
    }

    /// The compression half: the deflated block, transmitted with `o=z` and
    /// `q=0` so the transmission itself is the thing acknowledged or refused.
    /// No placement — nothing about a picture is in question here, only
    /// whether the bytes were understood.
    private static var compressionRequest: String {
        var encoded: [UInt8] = []
        KittyGraphics.base64(deflatedBlock, into: &encoded)
        return "\u{1B}_Ga=t,q=0,f=32,t=d,o=z,s=32,v=32,i=\(compressionProbeID);"
            + KittyGraphics.ascii(encoded) + "\u{1B}\\"
            + KittyGraphics.delete(id: compressionProbeID)
    }

    /// What the terminal said to each of the two questions.
    struct Answers: Equatable {
        /// It drew — accepted — a virtual placement.
        var placement = false
        /// It accepted a deflated transmission.
        var compression = false
    }

    /// The acknowledgements in `bytes`, each credited to the question that
    /// asked it.
    ///
    /// Reads the APC reply's body rather than searching the buffer for `OK`:
    /// the body is `i=<id>;OK` on success and `i=<id>;<some error text>`
    /// otherwise, and at least one of those error texts
    /// (`UnicodePlaceholderUnsupported`) is a refusal that a substring search
    /// for `OK` would not have distinguished from success on its own. The id
    /// decides WHICH question was answered, which is what lets two of them
    /// share one exchange: a placement `OK` carries ``probeID``, a compression
    /// `OK` carries ``compressionProbeID``, and an `OK` naming neither — a
    /// stray acknowledgement of something else — credits nothing.
    static func parse(_ bytes: [UInt8]) -> Answers {
        var answers = Answers()
        var index = bytes.startIndex
        while index + 2 < bytes.endIndex {
            guard bytes[index] == 0x1B, bytes[index + 1] == 0x5F, bytes[index + 2] == 0x47
            else {
                index += 1
                continue
            }
            var end = index + 3
            while end < bytes.endIndex, bytes[end] != 0x1B { end += 1 }
            var body = ""
            body.unicodeScalars.append(
                contentsOf: bytes[(index + 3)..<end].map { Unicode.Scalar($0) })
            if let semicolon = body.firstIndex(of: ";"),
                body[body.index(after: semicolon)...] == "OK"
            {
                let keys = body[..<semicolon].split(separator: ",")
                let id = keys.lazy.compactMap { key -> KittyGraphics.ImageID? in
                    guard key.hasPrefix("i=") else { return nil }
                    return KittyGraphics.ImageID(key.dropFirst(2))
                }.first
                if id == probeID { answers.placement = true }
                if id == compressionProbeID { answers.compression = true }
            }
            index = end
        }
        return answers
    }

    /// Whether the DSR fence has come back, which ends the read.
    ///
    /// `TerminalModeQuery`'s scan, not a second spelling: this one used to
    /// test only the LAST byte, so a keystroke landing behind the reply held
    /// the read open for the whole timeout, and a bare `ESC R` typed before
    /// the reply ended it early with pictures off for the session.
    static func sawFence(_ bytes: [UInt8]) -> Bool {
        TerminalModeQuery.sawFence(bytes)
    }
}

// MARK: - Asking

extension Terminal {

    /// The terminal cell's size in pixels, or `nil` where the terminal does
    /// not report one.
    ///
    /// The same `TIOCGWINSZ` fields ``cellPixelAspect()`` divides out, kept
    /// undivided: an image drawn with the terminal's own graphics protocol is
    /// transmitted at a real pixel size, and an aspect ratio cannot say what
    /// that is. All four measured hosts report it — 16x34 on a Retina Ghostty,
    /// 8x16 on Warp, 7x14 on Apple Terminal — and one that does not gets a
    /// plausible default rather than no picture (see
    /// ``EnvironmentValues/imageCellPixels``).
    func cellPixelSize() -> TerminalCellPixels? {
        #if canImport(WASILibc)
            // wasip1 has no `ioctl`, so the pixel geometry is unavailable and
            // callers take the default cell — the same path a terminal that
            // reports zeroes puts them on.
            return nil
        #else
        var windowSize = winsize()
        #if canImport(Glibc) || canImport(Musl)
            let result = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize)
        #else
            let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
        #endif
        guard result == 0,
            windowSize.ws_col > 0, windowSize.ws_row > 0,
            windowSize.ws_xpixel > 0, windowSize.ws_ypixel > 0
        else { return nil }
        return TerminalCellPixels(
            width: Int(windowSize.ws_xpixel) / Int(windowSize.ws_col),
            height: Int(windowSize.ws_ypixel) / Int(windowSize.ws_row))
        #endif
    }

    /// Asks the terminal whether it will place an image in the cell grid.
    ///
    /// The same shape as ``queryMode(_:timeout:)``: one write, then read until
    /// the DSR fence lands or the deadline passes.
    ///
    /// Bytes that arrive during the round trip and are not replies — a
    /// keystroke typed while the app was starting — are discarded, which is
    /// what ``queryMode(_:timeout:)`` already does and for the same reason:
    /// handing them back needs the input buffer, which is private to the file
    /// that owns it. ``TerminalIdentityQuery`` is the one exchange that does
    /// preserve them, and it is the one that runs before a host is known at
    /// all. A sub-millisecond window at startup is the price.
    ///
    /// - Returns: `true` only for a terminal that acknowledged the placement.
    ///   Silence, an error reply, no tty, and a host measured to print APC all
    ///   answer `false` — which costs the glyph renderer, and nothing else.
    func queryGraphicsSupport(timeout: Double = 0.5) -> TerminalGraphicsQuery.Answers {
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return TerminalGraphicsQuery.Answers() }
        // The one host measured to PRINT an APC payload rather than consume
        // it. Everything else gets asked, including terminals nobody has
        // measured — that is the point of a handshake — with the request's own
        // erase as the guard for the ones that share the gap.
        guard !TerminalHost.isAppleTerminal else { return TerminalGraphicsQuery.Answers() }

        writeImmediate(TerminalGraphicsQuery.request)

        var collected: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(timeout)
        while !TerminalGraphicsQuery.sawFence(collected) {
            // Shared with the other two startup probes, and EINTR-aware —
            // see ``Terminal/waitForInput(on:until:)``.
            guard Terminal.waitForInput(until: deadline) else { break }
            let read = chunk.withUnsafeMutableBufferPointer { readSource($0) }
            guard read > 0 else { break }
            collected.append(contentsOf: chunk[0..<read])
        }
        return TerminalGraphicsQuery.parse(collected)
    }
}
