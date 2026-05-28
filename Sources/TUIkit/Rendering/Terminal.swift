//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Terminal.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// Platform-specific type for `termios` flag fields.
///
/// Darwin uses `UInt` (64-bit), Linux uses `tcflag_t` (`UInt32`).
/// This typealias ensures flag bitmask operations compile on both.
#if os(Linux)
    private typealias TermFlag = UInt32
#else
    private typealias TermFlag = UInt
#endif

/// Represents the terminal and controls input and output.
///
/// `Terminal` is the central interface to the terminal. It provides:
/// - Terminal size queries
/// - Raw mode configuration
/// - Safe input and output
/// - Frame-buffered output (all writes collected, flushed in one syscall)
///
/// ## Output Buffering
///
/// During rendering, call ``beginFrame()`` before writing and ``endFrame()``
/// after. All ``write(_:)`` calls between them are collected in an internal
/// `[UInt8]` buffer and flushed as a single `write()` syscall, reducing
/// per-frame syscalls from ~40+ to exactly 1.
///
/// Outside of a frame (setup, teardown), ``write(_:)`` writes immediately
/// as before — safe by default.
///
/// ## Thread Safety
///
/// `Terminal` is `@MainActor` isolated. All terminal operations must occur
/// on the main thread, which is enforced by the Swift concurrency system.
@MainActor
final class Terminal: TerminalProtocol {
    /// Whether raw mode is active.
    private var isRawMode = false

    /// The mouse tracking mode last sent to the terminal.
    ///
    /// `applyMouseSupport` consults this to decide whether to emit a
    /// new mode-set escape code; idempotency lets it be called every
    /// frame at no cost.
    private var appliedMouseMode: MouseTrackingMode = .none

    /// Bytes of an in-progress escape sequence saved between
    /// ``readBytes`` calls. With `VTIME=0/VMIN=0` reads we can't
    /// block on a partial sequence; we save what we have, return
    /// `[]`, and let the next call try to drain more bytes from
    /// stdin. See ``readBytes(maxBytes:)`` for the full design note.
    private var pendingBytes: [UInt8] = []

    /// How many consecutive ``readBytes`` calls have failed to add
    /// any new bytes to a non-empty ``pendingBytes`` buffer. Once
    /// this hits the threshold (see ``readBytes(maxBytes:)``) we
    /// commit the partial so a bare Esc key (which looks like a
    /// partial CSI introducer for the first frame) finally fires.
    private var pendingStaleFrames: Int = 0

    /// The original terminal settings.
    private var originalTermios: termios?

    /// Whether frame buffering is active.
    ///
    /// When `true`, ``write(_:)`` appends to ``frameBuffer`` instead of
    /// writing to `STDOUT_FILENO` immediately.
    private var isBuffering = false

    /// Collects all output bytes during a buffered frame.
    ///
    /// Starts empty, grows via ``write(_:)`` calls, flushed by ``endFrame()``.
    /// Initial capacity of 16 KB covers typical frames without reallocation.
    private var frameBuffer: [UInt8] = []

    /// A copy of the last fully-assembled frame, saved just before it is
    /// flushed to the terminal.  Used by ``dumpLastFrame(to:)`` so that a
    /// debugging snapshot can be written without re-rendering.
    private(set) var lastFrameData: [UInt8] = []

    /// Creates a new terminal instance.
    init() {
        frameBuffer.reserveCapacity(16_384)
    }

    /// Destructor ensures raw mode is disabled.
    ///
    /// Note: `deinit` cannot be actor-isolated, so we use `MainActor.assumeIsolated`
    /// which is safe because Terminal instances are only created and destroyed
    /// on the main thread (in AppRunner).
    deinit {
        if isRawMode {
            MainActor.assumeIsolated {
                disableRawMode()
            }
        }
    }
}

// MARK: - Internal API

extension Terminal {
    /// Returns the current terminal size.
    ///
    /// - Returns: A tuple with width and height in characters/lines.
    func getSize() -> (width: Int, height: Int) {
        var windowSize = winsize()

        #if canImport(Glibc) || canImport(Musl)
            let result = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize)
        #else
            let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
        #endif

        if result == 0 && windowSize.ws_col > 0 && windowSize.ws_row > 0 {
            return (Int(windowSize.ws_col), Int(windowSize.ws_row))
        }

        // Fallback to environment variables
        let cols = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init) ?? 80
        let rows = ProcessInfo.processInfo.environment["LINES"].flatMap(Int.init) ?? 24

        return (cols, rows)
    }

    /// Enables raw mode for direct character handling.
    ///
    /// In raw mode:
    /// - Each keystroke is reported immediately (without Enter)
    /// - Echo is disabled
    /// - Signals like Ctrl+C are not automatically processed
    func enableRawMode() {
        guard !isRawMode else { return }

        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw

        raw.c_lflag &= ~TermFlag(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~TermFlag(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~TermFlag(OPOST)
        raw.c_cflag |= TermFlag(CS8)

        // Safe: termios.c_cc is a fixed-size array; rebinding to cc_t is valid.
        withUnsafeMutablePointer(to: &raw.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { buffer in
                buffer[Int(VMIN)] = 0
                buffer[Int(VTIME)] = 0
            }
        }

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isRawMode = true

        // Enable bracketed paste mode so that terminal paste operations
        // are wrapped in ESC[200~ ... ESC[201~ markers. This allows the
        // application to detect pasted text and insert it as a single
        // bulk operation instead of processing each character individually.
        writeImmediate("\u{1B}[?2004h")

        // Ask xterm-compatible terminals (iTerm2, Ghostty, kitty, wezterm,
        // gnome-terminal, …) to report modified cursor keys in canonical
        // `ESC[1;<mod><letter>` form so that combinations like
        // Shift+Option+Left arrive with both modifier bits set. Without
        // this, many terminals fall back to a stripped form that drops
        // the Option modifier and reports only Shift.
        //
        //   `CSI > 1 ; 2 m`  — modifyCursorKeys = 2 (canonical reporting)
        //
        // macOS Terminal.app ignores this hint; users on Terminal.app who
        // want word-level Shift+Option selection need to remap the key in
        // its preferences (or use a terminal with full modifier support).
        writeImmediate("\u{1B}[>1;2m")

        // Mouse tracking is now managed dynamically by
        // ``applyMouseSupport(_:)`` — see ``MouseSupport`` for the
        // selection of tracking modes. We always end up enabling SGR
        // extended position reporting (?1006h) when any mouse feature
        // is requested.
    }

    /// Disables raw mode and restores normal terminal operation.
    func disableRawMode() {
        guard isRawMode, var original = originalTermios else { return }

        // Reset modifyCursorKeys back to the terminal's default before
        // restoring terminal state.
        writeImmediate("\u{1B}[>1;0m")

        // Turn off all mouse tracking modes we might have enabled.
        // Sending all of them is safe: terminals ignore disables for
        // modes that aren't currently active.
        writeImmediate("\u{1B}[?1006l")
        writeImmediate("\u{1B}[?1003l")
        writeImmediate("\u{1B}[?1002l")
        writeImmediate("\u{1B}[?1000l")
        appliedMouseMode = .none

        // Disable bracketed paste mode before restoring terminal state.
        writeImmediate("\u{1B}[?2004l")

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        isRawMode = false
    }

    /// Updates the terminal's mouse-tracking mode to match the
    /// effective mouse-support configuration.
    ///
    /// Picks the lowest-impact tracking mode that satisfies the
    /// configuration (1000 → clicks only, 1002 → adds drag, 1003 →
    /// adds motion). SGR extended coordinate reporting is enabled
    /// whenever any tracking mode is active.
    ///
    /// Idempotent: only writes escape codes when the effective mode
    /// differs from the last applied mode, so it's cheap to call
    /// every frame.
    func applyMouseSupport(_ support: MouseSupport) {
        let target = trackingMode(for: support)
        guard target != appliedMouseMode else { return }

        // Turn off the previous mode (if any) before turning on the
        // new one. Disabling a mode that isn't active is a no-op on
        // every terminal we care about, so this also handles the
        // "stale state from a crashed prior process" case.
        if appliedMouseMode != .none {
            writeImmediate("\u{1B}[?\(appliedMouseMode.escapeNumber)l")
        }
        if target != .none {
            writeImmediate("\u{1B}[?\(target.escapeNumber)h")
            // SGR coords are paired with whichever tracking mode is on.
            writeImmediate("\u{1B}[?1006h")
        } else {
            writeImmediate("\u{1B}[?1006l")
        }
        appliedMouseMode = target
    }

    /// The tracking modes we know about. Higher values are strict
    /// supersets of lower ones.
    enum MouseTrackingMode: Equatable {
        case none
        case clicks       // ?1000h — press/release/scroll
        case drag         // ?1002h — adds drag motion
        case motion       // ?1003h — adds any-event motion

        var escapeNumber: Int {
            switch self {
            case .none: return 0
            case .clicks: return 1000
            case .drag: return 1002
            case .motion: return 1003
            }
        }
    }

    /// Picks the smallest tracking mode that satisfies the
    /// requested feature set.
    private func trackingMode(for support: MouseSupport) -> MouseTrackingMode {
        if support.motion { return .motion }
        if support.drag { return .drag }
        if support.clicks || support.scrolling { return .clicks }
        return .none
    }

    /// Begins a buffered frame.
    ///
    /// After this call, all ``write(_:)`` calls append to an internal
    /// `[UInt8]` buffer instead of issuing syscalls. Call ``endFrame()``
    /// to flush the collected output in a single `write()` syscall.
    func beginFrame() {
        guard !isBuffering else { return }
        isBuffering = true
        frameBuffer.removeAll(keepingCapacity: true)
    }

    /// Ends a buffered frame and flushes all collected output.
    func endFrame() {
        guard isBuffering else { return }
        isBuffering = false
        lastFrameData = frameBuffer          // snapshot before flush
        flushBuffer()
    }

    /// Writes the raw ANSI bytes of the last completed frame to a file.
    ///
    /// Triggered by the F9 key during a running app. The file can be opened
    /// in a hex viewer or piped through `cat` in another terminal to inspect
    /// the exact sequences sent for a given frame.
    ///
    /// - Parameter path: Destination file path.  Defaults to `tuikit-frame.ansi`.
    func dumpLastFrame() {
        guard !lastFrameData.isEmpty else {
            writeImmediate("\u{1B}[s\u{1B}[1;1H\u{1B}[7m[TUIkit] No frame data to dump\u{1B}[0m\u{1B}[u")
            return
        }

        let url = URL(fileURLWithPath: "tuikit-frame (\(Date().formatted(date: .abbreviated, time: .standard))).ansi")

        do {
            try Data(lastFrameData).write(to: url)
            writeImmediate("\u{1B}[s\u{1B}[1;1H\u{1B}[7mFrame dumped → \(url.path)\u{1B}[0m\u{1B}[u")
        } catch {
            // Show the error on-screen rather than crashing (a crash would leave
            // the terminal in raw-mode / alternate-screen).
            writeImmediate("\u{1B}[s\u{1B}[1;1H\u{1B}[7m[TUIkit] Dump failed: \(error)\u{1B}[0m\u{1B}[u")
        }
    }

    /// Writes a string to the terminal.
    ///
    /// When frame buffering is active (between ``beginFrame()`` and
    /// ``endFrame()``), the string's UTF-8 bytes are appended to the
    /// internal buffer. Otherwise, the bytes are written directly to
    /// `STDOUT_FILENO` via the POSIX `write` syscall.
    ///
    /// - Parameter string: The string to write.
    func write(_ string: String) {
        if isBuffering {
            appendToBuffer(string)
        } else {
            writeImmediate(string)
        }
    }

    /// Moves the cursor to the specified position.
    ///
    /// - Parameters:
    ///   - row: The row (1-based).
    ///   - column: The column (1-based).
    func moveCursor(toRow row: Int, column: Int) {
        write(ANSIRenderer.moveCursor(toRow: row, column: column))
    }

    /// Hides the cursor.
    func hideCursor() {
        write(ANSIRenderer.hideCursor)
    }

    /// Shows the cursor.
    func showCursor() {
        write(ANSIRenderer.showCursor)
    }

    /// Switches to the alternate screen buffer.
    func enterAlternateScreen() {
        write(ANSIRenderer.enterAlternateScreen)
    }

    /// Exits the alternate screen buffer.
    func exitAlternateScreen() {
        write(ANSIRenderer.exitAlternateScreen)
    }

    /// Tries to read exactly one byte from stdin. Pure non-blocking;
    /// returns `nil` immediately if the kernel has nothing for us.
    private func tryReadOneByte() -> UInt8? {
        var byte: UInt8 = 0
        return read(STDIN_FILENO, &byte, 1) > 0 ? byte : nil
    }

    /// Reads raw bytes from the terminal, handling escape sequences.
    ///
    /// Reads exactly one event's worth of bytes. Returns either:
    ///   - a single non-escape byte (a plain keystroke),
    ///   - a complete escape sequence (Alt+key, SS3 function key, full
    ///     CSI sequence, legacy or SGR mouse report), or
    ///   - an empty array when the kernel has no data right now.
    ///
    /// ## Partial-sequence buffering
    ///
    /// A long sequence (notably SGR mouse reports — up to ~18 bytes
    /// for three-digit coords) can arrive at the application across
    /// multiple `read()` calls if the terminal hasn't finished
    /// flushing the bytes by the time we drain stdin. With
    /// `VTIME=0/VMIN=0` an empty read returns 0 immediately, which
    /// would otherwise break the CSI loop before the terminator
    /// arrived and leave the remaining bytes to be re-read on the
    /// next call as ordinary keystrokes — that's how SGR mouse
    /// reports leaked into focused TextFields as gibberish like
    /// `<64;68;28M`.
    ///
    /// Instead of busy-waiting with `usleep` (which freezes the run
    /// loop), we *save* a partial sequence in ``pendingBytes`` and
    /// return `[]`. The next `readBytes` call resumes from that
    /// buffer: if more bytes are now available we continue reading
    /// toward the terminator; if they still aren't, we save again.
    /// The cost of a partial read is therefore just one main-loop
    /// idle frame (~24ms) — the main loop keeps animating, accepting
    /// other input, etc.
    ///
    /// A bare Esc key produces only `0x1B`, with no continuation.
    /// That looks identical to a partial CSI introducer until a
    /// full frame later, when the byte is still alone — at which
    /// point we commit it as an Esc keystroke. So pressing Esc has
    /// a one-frame (~24ms) commit latency; every other key path is
    /// untouched.
    ///
    /// - Parameter maxBytes: Maximum bytes per sequence. Defaults
    ///   to 32 — enough for any realistic CSI, including SGR mouse
    ///   reports at three-digit coordinates.
    /// - Returns: The bytes read, or `[]` if nothing is ready yet.
    func readBytes(maxBytes: Int = 32) -> [UInt8] {
        let initialCount = pendingBytes.count
        var result = pendingBytes
        pendingBytes = []

        // No partial in flight — try to read the first byte.
        if result.isEmpty {
            guard let first = tryReadOneByte() else { return [] }

            // Plain (non-escape) byte: a single-byte key event.
            if first != 0x1B {
                pendingStaleFrames = 0
                return [first]
            }
            result.append(first)
        }

        // Try to complete the escape sequence using whatever's
        // available right now. If we can't, save the partial and
        // bail.
        if tryCompleteEscapeSequence(&result, maxBytes: maxBytes) {
            pendingStaleFrames = 0
            return result
        }

        if result.count > initialCount {
            // We made progress this call — keep the partial and try
            // again on the next `readBytes`. The main loop will
            // idle for ~24ms before then, which gives the terminal
            // plenty of time to finish writing the sequence.
            pendingStaleFrames = 0
            pendingBytes = result
            return []
        }

        // No progress at all on this call. That means the partial
        // we already had still has no fresh bytes behind it.
        // Stale for one frame is fine; stale for two means whatever
        // was coming isn't, so commit what we have and let the
        // caller try to parse it (it'll either match e.g. an Esc
        // key, or fail and be silently dropped).
        pendingStaleFrames += 1
        if pendingStaleFrames >= 2 {
            pendingStaleFrames = 0
            return result
        }
        pendingBytes = result
        return []
    }

    /// Attempts to read the rest of an escape sequence given a
    /// partial `result` that starts with `0x1B`.
    ///
    /// - Returns: `true` if the sequence is now complete, `false` if
    ///   bytes are missing — in which case `result` holds whatever
    ///   was read so far, ready to be saved as a partial.
    private func tryCompleteEscapeSequence(_ result: inout [UInt8], maxBytes: Int) -> Bool {
        // Need at least the byte after ESC to know which sequence
        // variant this is.
        if result.count == 1 {
            guard let b = tryReadOneByte() else { return false }
            result.append(b)
        }

        let secondByte = result[1]

        if secondByte == 0x5B {  // ESC [ = CSI
            return tryCompleteCSI(&result, maxBytes: maxBytes)
        }

        if secondByte == 0x4F {  // ESC O = SS3 (F1-F4 etc.)
            if result.count == 2 {
                guard let b = tryReadOneByte() else { return false }
                result.append(b)
            }
            return true
        }

        // Alt+key — ESC followed by single key. Two bytes total.
        return true
    }

    /// Reads CSI parameter bytes until a terminator (a letter or
    /// `~`) or `maxBytes` is reached. Handles the legacy "X10"
    /// mouse-report sub-format (`ESC[M<b><x><y>`, six bytes) where
    /// `M` is the *introducer*, not the terminator, and the three
    /// trailing coord bytes can sit anywhere in 0x20…0xFF.
    ///
    /// - Returns: `true` if the CSI is complete, `false` if bytes
    ///   are still pending.
    private func tryCompleteCSI(_ result: inout [UInt8], maxBytes: Int) -> Bool {
        // Need the first param byte to disambiguate.
        if result.count == 2 {
            guard let b = tryReadOneByte() else { return false }
            result.append(b)
        }

        let firstParam = result[2]

        if firstParam == 0x4D {  // 'M' — legacy mouse report
            // Read exactly three more coord bytes. Each is the raw
            // value + 32 and may take any byte value.
            while result.count < 6 {
                guard let b = tryReadOneByte() else { return false }
                result.append(b)
            }
            return true
        }

        // Single-letter CSI terminator straight after `[`
        // (e.g. `ESC[A` for Up Arrow).
        if firstParam >= 0x40 && firstParam <= 0x7E {
            return true
        }

        // Read parameter bytes until terminator.
        while result.count < maxBytes {
            guard let b = tryReadOneByte() else { return false }
            result.append(b)
            if b >= 0x40 && b <= 0x7E {
                return true
            }
        }
        // Reached maxBytes without terminator — treat as complete;
        // downstream parsers will reject the malformed sequence.
        return true
    }

    /// Reads a key event from the terminal.
    ///
    /// When bracketed paste mode is active the terminal wraps pasted text
    /// in `ESC[200~` ... `ESC[201~` markers. This method detects the start
    /// marker, buffers all bytes until the end marker, and returns the
    /// entire pasted text as a single `Key.paste(String)` event.
    ///
    /// - Returns: The key event, or nil on timeout/error.
    func readKeyEvent() -> KeyEvent? {
        let bytes = readBytes()
        guard !bytes.isEmpty else { return nil }

        // Detect bracketed paste start: ESC [ 2 0 0 ~
        if bytes == [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E] {
            let pastedText = readBracketedPasteContent()
            return KeyEvent(key: .paste(pastedText))
        }

        return KeyEvent.parse(bytes)
    }

    /// Reads the next input event from the terminal, whether key or mouse.
    ///
    /// Recognises SGR-extended mouse reports (`CSI < … M/m`) and routes
    /// them through ``MouseEvent.parseSGR(_:)``; everything else falls
    /// through the same path as ``readKeyEvent()`` for key handling.
    ///
    /// - Returns: The next event, or nil on timeout/error.
    func readEvent() -> TerminalInput? {
        let bytes = readBytes()
        guard !bytes.isEmpty else { return nil }

        // SGR mouse report: ESC [ < … M / m
        if bytes.count >= 9, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x3C {
            if let mouse = MouseEvent.parseSGR(bytes) {
                return .mouse(mouse)
            }
        }

        // Legacy ("X10") mouse report: ESC [ M <button+32> <x+32> <y+32>
        // Apple's Terminal.app sometimes falls back to this even when
        // SGR mouse mode is requested.
        if bytes.count == 6, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x4D {
            if let mouse = MouseEvent.parseLegacy(bytes) {
                return .mouse(mouse)
            }
            // Malformed but unambiguously a legacy report — drop it
            // entirely rather than letting the coord bytes leak back
            // through KeyEvent.parse as gibberish.
            return nil
        }

        // Bracketed paste start.
        if bytes == [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E] {
            let pastedText = readBracketedPasteContent()
            return .key(KeyEvent(key: .paste(pastedText)))
        }

        if let key = KeyEvent.parse(bytes) {
            return .key(key)
        }
        return nil
    }

    /// Reads bytes until the bracketed paste end marker `ESC[201~` is found.
    ///
    /// Called after the paste start marker `ESC[200~` has been detected.
    /// Reads byte-by-byte, watching for the 6-byte end sequence. All bytes
    /// before the end marker are collected and returned as a UTF-8 string.
    ///
    /// - Returns: The pasted text content.
    private func readBracketedPasteContent() -> String {
        var content: [UInt8] = []
        // The end marker is: ESC [ 2 0 1 ~
        let endMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]

        // Safety limit to prevent infinite buffering on malformed input.
        let maxPasteBytes = 65_536

        while content.count < maxPasteBytes {
            var byte = [UInt8](repeating: 0, count: 1)
            let bytesRead = read(STDIN_FILENO, &byte, 1)
            guard bytesRead > 0 else {
                // No more data available right now. For non-blocking reads
                // (VMIN=0, VTIME=0) this means the paste end marker has not
                // yet arrived. Wait briefly and retry.
                usleep(1_000)  // 1ms
                continue
            }

            content.append(byte[0])

            // Check if content ends with the paste end marker.
            if content.count >= endMarker.count {
                let tail = Array(content.suffix(endMarker.count))
                if tail == endMarker {
                    // Remove the end marker from the content.
                    content.removeLast(endMarker.count)
                    break
                }
            }
        }

        return String(bytes: content, encoding: .utf8) ?? String(content.map { Character(UnicodeScalar($0)) })
    }
}

// MARK: - Private Helpers

extension Terminal {
    /// Appends a string's UTF-8 bytes to the frame buffer.
    fileprivate func appendToBuffer(_ string: String) {
        frameBuffer.append(contentsOf: string.utf8)
    }

    /// Writes all buffered bytes to `STDOUT_FILENO` in a single syscall.
    fileprivate func flushBuffer() {
        guard !frameBuffer.isEmpty else { return }
        frameBuffer.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let count = buffer.count
            var written = 0
            while written < count {
                let result = Foundation.write(STDOUT_FILENO, baseAddress + written, count - written)
                if result <= 0 { break }
                written += result
            }
        }
        frameBuffer.removeAll(keepingCapacity: true)
    }

    /// Writes a string directly to `STDOUT_FILENO` without buffering.
    fileprivate func writeImmediate(_ string: String) {
        // Safe: UTF8 string is valid UInt8 sequence; rebinding preserves memory layout.
        string.utf8CString.withUnsafeBufferPointer { buffer in
            let count = buffer.count - 1
            guard count >= 1, let baseAddress = buffer.baseAddress else { return }
            baseAddress.withMemoryRebound(to: UInt8.self, capacity: count) { pointer in
                var written = 0
                while written < count {
                    let result = Foundation.write(STDOUT_FILENO, pointer + written, count - written)
                    if result <= 0 { break }
                    written += result
                }
            }
        }
    }
}
