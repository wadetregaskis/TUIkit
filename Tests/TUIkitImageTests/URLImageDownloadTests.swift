//  🖥️ TUIKit — Terminal UI Kit for Swift
//  URLImageDownloadTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@testable import TUIkitImage

// MARK: - Tarpit

/// A TCP listener that never answers.
///
/// It binds and listens but never calls `accept`, so the kernel completes the
/// handshake into the backlog: a client connects, sends its request, and then
/// waits — for the full request timeout, if nothing cancels it. That is the
/// shape of a slow image server, reproduced locally with no network access and
/// no dependence on any external host.
private final class Tarpit {
    let port: UInt16
    private let listener: Int32

    /// One-time SIGPIPE suppression, run before the first tarpit exists.
    ///
    /// SIGPIPE's default action is to kill the process, and a tarpit exists to
    /// manufacture connections that end badly: when the listener closes, every
    /// connection still queued in its backlog is reset, and the next write to
    /// one of those takes EPIPE. The writer is URLSession — in THIS process,
    /// because the fake server and its client are the same program — so the
    /// signal lands here and takes the whole test bundle with it, mid-suite,
    /// with no failing expectation to point at. macOS CI died exactly that way
    /// (`exited with unexpected signal code 13`).
    ///
    /// An app gets this from `SignalManager.install`; a test bundle installs
    /// nothing, and a library has no business setting a process-wide
    /// disposition its host did not ask for. So it belongs here, next to the
    /// sockets that need it.
    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    init() throws {
        _ = Self.ignoreSIGPIPE

        #if canImport(Darwin)
            let streamType = SOCK_STREAM
        #else
            let streamType = Int32(SOCK_STREAM.rawValue)
        #endif
        let fd = socket(AF_INET, streamType, 0)
        guard fd >= 0 else { throw TarpitError.failed("socket") }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0  // any free port
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian  // 127.0.0.1
        #if canImport(Darwin)
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw TarpitError.failed("bind/listen")
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            close(fd)
            throw TarpitError.failed("getsockname")
        }

        listener = fd
        port = UInt16(bigEndian: assigned.sin_port)
    }

    var urlString: String { "http://127.0.0.1:\(port)/tarpit.png" }

    deinit { close(listener) }

    enum TarpitError: Error { case failed(String) }
}

/// Runs `body` against a tarpit that is guaranteed to still be listening for
/// the whole call.
///
/// Not `let tarpit = try Tarpit()` at the top of a test. ARC ends an object's
/// life after its last USE, and a test's last use of the tarpit is the
/// `urlString` read on its first line — so `deinit` closed the listener before
/// any download reached it, and every connection got refused instead of
/// stalled. Both tests below passed for that reason and neither measured what
/// it claimed: the ten-download pool test finished in five MILLISECONDS.
///
/// It surfaced as two different CI failures once the timing shifted. On Linux
/// a transfer really was in flight, and cancelling it took 2.8 s against a 1 s
/// bound that had never been tested. On macOS the premature close reset live
/// connections and the process died of SIGPIPE (`unexpected signal code 13`).
private func withTarpit<T>(_ body: (Tarpit) async throws -> T) async throws -> T {
    let tarpit = try Tarpit()
    defer { withExtendedLifetime(tarpit) {} }
    return try await body(tarpit)
}

// MARK: - Tests

/// A URL image load must suspend, not block, and must honour cancellation.
///
/// The download used to be a `DispatchSemaphore` around `URLSession`'s
/// callback. That parked the calling thread for the whole transfer — and the
/// caller is `_ImageCore`'s load task, running on the cooperative pool, which
/// has one thread per core. Two slow images on a small machine and no other
/// async work could run at all. Cancellation was equally impossible: a blocked
/// thread cannot notice that its task was cancelled, so leaving the page did
/// not release anything until the request timed out on its own.
@Suite("URL image download")
struct URLImageDownloadTests {

    /// Cancelling the task must abandon the download promptly. The timeout is
    /// 30 s and the tarpit never replies, so pre-fix this could only finish by
    /// waiting all of it out; the bound below is generous for "promptly" while
    /// still being an order of magnitude short of the timeout.
    @Test("Cancellation abandons an in-flight download")
    func cancellationAbandonsDownload() async throws {
        try await withTarpit { tarpit in
            let loader = PlatformImageLoader()
            let url = tarpit.urlString

            let task = Task<Bool, Never> {
                do {
                    _ = try await loader.loadImage(fromURL: url, timeout: 30)
                    return false  // the tarpit cannot serve an image
                } catch is CancellationError {
                    return true
                } catch {
                    // A cancelled transfer may also surface as URLError.cancelled
                    // if the check races; either way the load gave up early, which
                    // is what this test is about.
                    return Task.isCancelled
                }
            }

            // Let the task start and its request reach the tarpit, so what is
            // cancelled is a transfer in flight rather than a task not yet begun.
            try await Task.sleep(for: .milliseconds(250))
            let clock = ContinuousClock()
            let begin = clock.now
            task.cancel()
            let cancelled = await task.value
            let elapsed = clock.now - begin

            #expect(cancelled, "a cancelled download reports cancellation, not a network failure")
            // Five seconds, not one. What this test discriminates is "gave up
            // now" from "waited out the 30 s timeout", and five is still an
            // order of magnitude short of that. One second was a bound the
            // tests never actually exercised (the tarpit was already closed,
            // so nothing was ever in flight to cancel); against a real stalled
            // transfer on a CI runner saturated by the rest of the suite, the
            // cancel round-trip measured 2.8 s.
            #expect(
                elapsed < .seconds(5),
                "cancelling must abandon the transfer, not wait out the 30 s timeout (took \(elapsed))"
            )
        }
    }

    /// The load must not occupy the thread it is called on. Ten concurrent
    /// downloads against a tarpit, on a pool with far fewer threads than that,
    /// still leave room for other work to run to completion.
    @Test("A slow download does not block the cooperative pool")
    func slowDownloadDoesNotBlockThePool() async throws {
        try await withTarpit { tarpit in
            let loader = PlatformImageLoader()
            let url = tarpit.urlString

            let downloads = (0..<10).map { _ in
                Task { try? await loader.loadImage(fromURL: url, timeout: 30) }
            }
            defer { for download in downloads { download.cancel() } }

            // Let the requests actually reach the tarpit before timing the
            // unrelated work. Without this the downloads might still be queued
            // rather than stalled, and a pool nothing is occupying yet proves
            // nothing about a pool full of stalled transfers.
            try await Task.sleep(for: .milliseconds(250))

            // Unrelated async work, started after the downloads and expected to
            // finish while they are all still in flight.
            let counter = Task { () -> Int in
                var total = 0
                for _ in 0..<100 {
                    await Task.yield()
                    total += 1
                }
                return total
            }

            let clock = ContinuousClock()
            let begin = clock.now
            let total = await counter.value
            let elapsed = clock.now - begin

            #expect(total == 100)
            #expect(
                elapsed < .seconds(5),
                "ten stalled downloads must not starve the pool (took \(elapsed))")
        }
    }
}
