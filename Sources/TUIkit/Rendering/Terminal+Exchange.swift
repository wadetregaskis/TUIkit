//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+Exchange.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import DequeModule
import Foundation

// MARK: - Asking the terminal a question and reading the answer

/// The read loop every startup query shares, and the hand-back that lets one
/// of them return what it read but does not own.
///
/// Separate from `Terminal.swift` because that file is at its length limit.
/// The loop used to be spelled out three times (identity, DECRQM, graphics),
/// and the three copies differed only in how each recognised its fence.
extension Terminal {

    /// Writes `request`, then reads stdin until `sawFence` says the fence has
    /// come back or `timeout` elapses, and returns every byte it read.
    ///
    /// The fence is a query every terminal answers, sent last, so its reply
    /// means every earlier query has either answered or declined to. That is
    /// what lets a question nobody implements cost nothing and hang nothing.
    ///
    /// NOT a parser, and NOT a policy on stray bytes. The result is everything
    /// that arrived, replies and keystrokes alike, including anything after the
    /// fence in the same read. Each caller decides what is a reply, and hands
    /// the rest back: identity through its own walk and ``enqueue(input:)``,
    /// the others through ``handBackUnconsumed(from:isReply:isFence:)``.
    ///
    /// Nor a guard: callers check for a tty in raw mode before asking, since
    /// what "no answer" means differs per question.
    ///
    /// - Parameters:
    ///   - request: The queries and their fence, written in one go.
    ///   - timeout: How long to wait for the fence. Only a terminal that
    ///     answers no fence reaches it, since the read ends as soon as the fence
    ///     lands.
    ///   - sawFence: Whether the bytes read so far contain the fence's reply.
    ///     Called with the whole buffer after every read, and once with no bytes
    ///     before the first, so a split reply is seen once its tail arrives.
    /// - Returns: The bytes read, in arrival order. Empty when nothing came.
    func fencedExchange(
        request: String, timeout: Double, sawFence: ([UInt8]) -> Bool
    ) -> [UInt8] {
        if let exchangeTransport {
            exchangeTransport.send(request)
        } else {
            writeImmediate(request)
        }

        var collected: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(timeout)
        while !sawFence(collected) {
            // EINTR-aware, and against the same deadline throughout — see
            // ``Terminal/waitForInput(on:until:)``.
            let ready =
                exchangeTransport?.waitForInput(deadline)
                ?? Self.waitForInput(until: deadline)
            guard ready else { break }
            let read = chunk.withUnsafeMutableBufferPointer { readSource($0) }
            guard read > 0 else { break }
            collected.append(contentsOf: chunk[0..<read])
        }
        return collected
    }

    /// Appends bytes to the pending-input buffer as though they had just been
    /// read from stdin.
    ///
    /// For handing back bytes another reader took but does not own: see
    /// ``queryIdentity(timeout:)`` and
    /// ``handBackUnconsumed(from:isReply:isFence:)``. Appends rather than
    /// prepends because anything already buffered was read from stdin before
    /// the exchange began. At startup the buffer is empty; on resume, where
    /// the mode query runs again, it may not be, and these are still the
    /// newest bytes.
    func enqueue(input bytes: [UInt8]) {
        input.append(addingCount: bytes.count) { (span: inout OutputSpan<UInt8>) in
            for byte in bytes { span.append(byte) }
        }
    }

    /// Puts what an exchange read, less its replies and its fence, into the
    /// input buffer: a keystroke typed during the round trip, a focus report
    /// sent the moment reporting was enabled, and anything behind the fence.
    ///
    /// See ``TerminalQueryReplies/unconsumed(_:isReply:isFence:)`` for how a
    /// reply is told from the rest.
    func handBackUnconsumed(
        from collected: [UInt8],
        isReply: (ArraySlice<UInt8>) -> Bool,
        isFence: (ArraySlice<UInt8>) -> Bool
    ) {
        let unconsumed = TerminalQueryReplies.unconsumed(
            collected, isReply: isReply, isFence: isFence)
        if !unconsumed.isEmpty { enqueue(input: unconsumed) }
    }

    /// A scripted terminal for ``fencedExchange(request:timeout:sawFence:)``:
    /// see ``Terminal/exchangeTransport``. The replies themselves still come
    /// through ``Terminal/readSource``.
    struct ExchangeTransport {
        /// Receives the request instead of stdout.
        var send: (String) -> Void
        /// Whether input is ready before the deadline, instead of `poll` on
        /// stdin. Answering `true` with nothing staged is safe: the read then
        /// returns 0, which ends the exchange.
        var waitForInput: (Date) -> Bool
    }
}

// MARK: - Telling a reply from everything else

/// The split every startup exchange makes between the bytes it asked for and
/// the bytes that belong to the input parser.
enum TerminalQueryReplies {

    /// The bytes in `bytes` that are neither a reply nor the fence, in arrival
    /// order.
    ///
    /// Walks whole escape sequences, so a reply is known by its shape, never
    /// by a substring: a CSI ends at its final byte, and OSC, DCS, APC, PM and
    /// SOS end at BEL or ST. Each complete sequence is offered to `isFence`,
    /// then `isReply`. The first fence ends the walk, and everything behind it
    /// is kept as it is. A reply is dropped. Everything else is kept byte for
    /// byte, including an ESC that starts no sequence (an Alt chord), so the
    /// parser reads exactly what it would have read from stdin.
    ///
    /// Two shapes are kept without being judged, because the parser already
    /// has rules for them:
    /// - A sequence still open when the bytes run out is kept. It is a reply
    ///   the timeout cut off, or a key whose tail is in the next read, and only
    ///   the parser can wait for that tail.
    /// - A string sequence that a new ESC interrupts keeps its prefix, and the
    ///   interrupting sequence is judged on its own, as
    ///   `Terminal.stringSequenceLength()` treats it.
    ///
    /// - Parameters:
    ///   - bytes: Everything the exchange read.
    ///   - isReply: Whether a complete sequence answers this exchange's
    ///     question.
    ///   - isFence: Whether a complete sequence is the fence's reply.
    static func unconsumed(
        _ bytes: [UInt8],
        isReply: (ArraySlice<UInt8>) -> Bool,
        isFence: (ArraySlice<UInt8>) -> Bool
    ) -> [UInt8] {
        var kept: [UInt8] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            guard bytes[index] == 0x1B else {
                kept.append(bytes[index])
                index += 1
                continue
            }
            switch extent(of: bytes, from: index) {
            case .incomplete:
                kept.append(contentsOf: bytes[index...])
                return kept
            case .notASequence:
                kept.append(0x1B)
                index += 1
            case .complete(let end):
                let sequence = bytes[index..<end]
                if isFence(sequence) {
                    kept.append(contentsOf: bytes[end...])
                    return kept
                }
                if !isReply(sequence) { kept.append(contentsOf: sequence) }
                index = end
            }
        }
        return kept
    }

    /// How far the escape sequence at an `ESC` reaches.
    private enum Extent {
        /// It ends just before `end`.
        case complete(end: Int)
        /// The bytes ran out before it ended.
        case incomplete
        /// The `ESC` starts no sequence this walk recognises, or one that a
        /// byte outside its grammar cut short.
        case notASequence
    }

    /// The extent of the sequence whose `ESC` is at `index`.
    private static func extent(of bytes: [UInt8], from index: Int) -> Extent {
        let introducer = index + 1
        guard introducer < bytes.endIndex else { return .incomplete }
        let second = UInt32(bytes[introducer])
        if second == 0x5B {  // '[', CSI
            var cursor = introducer + 1
            while cursor < bytes.endIndex, String.isCSIBodyByte(UInt32(bytes[cursor])) {
                cursor += 1
            }
            guard cursor < bytes.endIndex else { return .incomplete }
            return String.isCSIFinalByte(UInt32(bytes[cursor]))
                ? .complete(end: cursor + 1) : .notASequence
        }
        guard String.isStringFamilyIntroducer(second) else { return .notASequence }
        var cursor = introducer + 1
        while cursor < bytes.endIndex {
            if bytes[cursor] == 0x07 { return .complete(end: cursor + 1) }  // BEL
            if bytes[cursor] == 0x1B {
                guard cursor + 1 < bytes.endIndex else { return .incomplete }
                return bytes[cursor + 1] == 0x5C ? .complete(end: cursor + 2) : .notASequence
            }
            cursor += 1
        }
        return .incomplete
    }
}
