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
    /// fence in the same read. Each caller decides what is a reply, and whether
    /// the rest is handed back through ``enqueue(input:)`` or dropped.
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
        writeImmediate(request)

        var collected: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(timeout)
        while !sawFence(collected) {
            // EINTR-aware, and against the same deadline throughout — see
            // ``Terminal/waitForInput(on:until:)``.
            guard Terminal.waitForInput(until: deadline) else { break }
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
    /// ``queryIdentity(timeout:)``. Appends rather than prepends because every
    /// caller runs before the loop starts, when the buffer is empty and these
    /// ARE the oldest bytes.
    func enqueue(input bytes: [UInt8]) {
        input.append(addingCount: bytes.count) { (span: inout OutputSpan<UInt8>) in
            for byte in bytes { span.append(byte) }
        }
    }
}
