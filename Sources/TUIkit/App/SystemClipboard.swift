//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SystemClipboard.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The system clipboard, reached through the platform's helper binaries
/// (`pbcopy`/`pbpaste` on macOS, `xclip`/`xsel` on Linux) with hardened child
/// I/O.
///
/// Every exchange with a helper is **bounded and non-blocking**, because the
/// helpers fail in ways that would otherwise take the whole app with them —
/// these are real behaviours, not hypotheticals:
///
/// - a helper can exit before reading its stdin (`xclip` on a headless box
///   prints "Error: Can't open display" and quits), which makes a blocking
///   write die on the broken pipe;
/// - a helper can stop reading while stdin still has data (wedged X
///   connection), which makes a blocking write of more than the ~64 KB pipe
///   buffer hang forever;
/// - a helper can hang without ever closing its stdout, which makes
///   `readDataToEndOfFile` hang forever.
///
/// The clipboard is driven synchronously from the input path (a Ctrl+C/V/X in
/// a text field), so "hang forever" means the main actor blocks — and while it
/// is blocked, the dispatch-source signal handlers can't run either, so even
/// Ctrl+C can't kill the app. Hence: pipe fds are switched to `O_NONBLOCK`,
/// every I/O loop and the exit reap check a wall-clock deadline, and a child
/// that outlives its deadline is terminated. On failure the operation reports
/// cleanly (`false`/`nil`) instead of crashing or wedging.
enum SystemClipboard {
    /// One-time SIGPIPE suppression for processes that never ran an `App`
    /// (unit tests, harnesses). `SignalManager.install` also ignores SIGPIPE
    /// for the app itself; doing it again here is an idempotent no-op. Without
    /// it, the first write to an already-exited helper would deliver SIGPIPE
    /// and terminate the *host* process before the `EPIPE` handling below ever
    /// ran.
    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    /// How long any one clipboard exchange may take before it is abandoned.
    /// The helpers normally answer in single-digit milliseconds; two seconds
    /// is generous enough for a loaded machine and a multi-megabyte payload,
    /// while keeping a wedged helper from freezing the app for longer than a
    /// noticeable-but-survivable moment.
    static let defaultDeadline: TimeInterval = 2.0

    // MARK: - Public surface

    /// Copies `text` to the system clipboard. Silently does nothing when no
    /// helper is available or the helper misbehaves — clipboard trouble must
    /// never take the app down with it.
    static func copy(_ text: String) {
        #if os(macOS)
            _ = run(
                tool: "/usr/bin/pbcopy", arguments: [],
                writing: Data(text.utf8), readsOutput: false
            )
        #elseif os(Linux)
            for (tool, arguments) in [
                ("/usr/bin/xclip", ["-selection", "clipboard"]),
                ("/usr/bin/xsel", ["--clipboard", "--input"]),
            ] where FileManager.default.fileExists(atPath: tool) {
                if run(tool: tool, arguments: arguments, writing: Data(text.utf8), readsOutput: false) != nil {
                    return
                }
            }
        #endif
    }

    /// Returns the system clipboard's text, or `nil` when no helper is
    /// available, the helper misbehaves, or the content isn't UTF-8.
    static func paste() -> String? {
        #if os(macOS)
            return textFromHelper(tool: "/usr/bin/pbpaste", arguments: [])
        #elseif os(Linux)
            for (tool, arguments) in [
                ("/usr/bin/xclip", ["-selection", "clipboard", "-o"]),
                ("/usr/bin/xsel", ["--clipboard", "--output"]),
            ] where FileManager.default.fileExists(atPath: tool) {
                if let text = textFromHelper(tool: tool, arguments: arguments) {
                    return text
                }
            }
            return nil
        #else
            return nil
        #endif
    }

    private static func textFromHelper(tool: String, arguments: [String]) -> String? {
        guard let data = run(tool: tool, arguments: arguments, writing: nil, readsOutput: true),
            var result = String(bytes: data, encoding: .utf8)
        else { return nil }
        // Strip the single trailing newline the helpers append.
        if result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }

    // MARK: - Bounded child I/O

    /// Runs `tool`, optionally feeding `input` to its stdin and/or collecting
    /// its stdout, all under `deadline`. Returns the collected stdout (empty
    /// `Data` for a write-only exchange) on success; `nil` on any failure —
    /// tool missing, deadline passed, pipe broken, non-zero exit.
    ///
    /// Internal (not fileprivate) so tests can drive it against scripted
    /// stand-ins for the real helpers — the failure modes it exists to survive
    /// (child exits without reading; child stops reading mid-payload; child
    /// never closes stdout) can't be arranged with the genuine clipboard.
    static func run(
        tool: String,
        arguments: [String],
        writing input: Data?,
        readsOutput: Bool,
        deadline: TimeInterval = defaultDeadline
    ) -> Data? {
        _ = ignoreSIGPIPE

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice

        let stdinPipe = input != nil ? Pipe() : nil
        if let stdinPipe { process.standardInput = stdinPipe }
        let stdoutPipe = readsOutput ? Pipe() : nil
        if let stdoutPipe { process.standardOutput = stdoutPipe }

        do {
            try process.run()
        } catch {
            return nil
        }
        let limit = DispatchTime.now() + deadline

        var wroteEverything = true
        if let input, let stdinPipe {
            wroteEverything = write(input, to: stdinPipe.fileHandleForWriting, until: limit)
            // Close our write end regardless, so the child sees EOF and can
            // finish; a failed write already means the exchange has failed.
            try? stdinPipe.fileHandleForWriting.close()
        }

        var output = Data()
        var readEverything = true
        if let stdoutPipe {
            readEverything = read(into: &output, from: stdoutPipe.fileHandleForReading, until: limit)
        }

        // Reap within the deadline; a child that outlives it is wedged — kill
        // it rather than leave a zombie holding the clipboard hostage.
        while process.isRunning {
            if DispatchTime.now() >= limit {
                process.terminate()
                return nil
            }
            Thread.sleep(forTimeInterval: 0.002)
        }

        guard wroteEverything, readEverything, process.terminationStatus == 0 else { return nil }
        return output
    }

    /// Writes all of `data` to `handle` with `O_NONBLOCK` + deadline polling.
    /// A plain blocking write cannot be bounded from outside: once the pipe
    /// buffer fills against a child that stopped reading, it parks the thread
    /// in the kernel and no amount of checking afterwards helps.
    private static func write(_ data: Data, to handle: FileHandle, until limit: DispatchTime) -> Bool {
        let fd = handle.fileDescriptor
        guard makeNonBlocking(fd) else { return false }
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
                #if canImport(Darwin)
                    Darwin.write(fd, buffer.baseAddress! + offset, data.count - offset)
                #else
                    Glibc.write(fd, buffer.baseAddress! + offset, data.count - offset)
                #endif
            }
            if written > 0 {
                offset += written
            } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                if DispatchTime.now() >= limit { return false }
                Thread.sleep(forTimeInterval: 0.002)
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                return false  // EPIPE (child gone), or any other write failure
            }
        }
        return true
    }

    /// Reads `handle` to EOF into `output` with `O_NONBLOCK` + deadline
    /// polling. Same reasoning as the write side: `readDataToEndOfFile`
    /// blocks until the child closes its stdout, which a hung child never
    /// does.
    private static func read(into output: inout Data, from handle: FileHandle, until limit: DispatchTime) -> Bool {
        let fd = handle.fileDescriptor
        guard makeNonBlocking(fd) else { return false }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                #if canImport(Darwin)
                    Darwin.read(fd, raw.baseAddress, raw.count)
                #else
                    Glibc.read(fd, raw.baseAddress, raw.count)
                #endif
            }
            if count > 0 {
                output.append(contentsOf: buffer[0..<count])
            } else if count == 0 {
                return true  // EOF — the child closed its end
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                if DispatchTime.now() >= limit { return false }
                Thread.sleep(forTimeInterval: 0.002)
            } else if errno == EINTR {
                continue
            } else {
                return false
            }
        }
    }

    private static func makeNonBlocking(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0
    }
}
