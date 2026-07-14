//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Terminal.swift
//
//  Created by LAYERED.work
//  License: MIT

import DequeModule
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

    /// All input bytes that have been drained from stdin but not yet
    /// dispatched as events. Bytes are appended at the back by
    /// ``appendDrain()`` (one `read()` syscall per call) and consumed
    /// from the front by ``readEvent()`` as it identifies events.
    ///
    /// ``UniqueDeque`` is a noncopyable ring buffer with O(1)
    /// removeFirst and an "append into uninitialised storage via
    /// `OutputSpan`" API — together those let us `read()` straight
    /// into the deque's backing buffer with zero intermediate
    /// copies, and consume bytes off the front without paying any
    /// shuffling cost. Capacity grows geometrically when needed
    /// and ``consume(_:)`` shrinks it back to ``baselineCapacity``
    /// once a transient large paste has been fully consumed.
    private var input: UniqueDeque<UInt8> = .init(
        minimumCapacity: Terminal.baselineCapacity)

    /// Initial — and steady-state minimum — capacity for ``input``.
    /// Sized to comfortably hold a frame's worth of bursty mouse
    /// events without ever needing to grow.
    private static let baselineCapacity = 4096

    /// True while we're between the bracketed-paste start (`ESC[200~`)
    /// and end (`ESC[201~`) markers. Paste content is accumulated
    /// across as many `readEvent()` calls as it takes for the end
    /// marker to arrive — no blocking, no `usleep`. The run loop
    /// stays responsive even for very large pastes.
    private var inPasteMode: Bool = false

    /// Frames during which we couldn't make progress on whatever
    /// sits at the front of the input buffer. Increments only when
    /// a drain produced no new bytes *and* the buffer still has an
    /// unparseable partial at the front. Resets on any drained byte
    /// or successful extract.
    ///
    /// Two roles:
    /// - Bare-Esc disambiguation: `0x1B` alone looks identical to
    ///   the first byte of a CSI / SS3 / Alt+key sequence until
    ///   something definitive arrives. After two stale frames
    ///   (~48ms) we *defer* it via ``pendingBareEsc`` rather than
    ///   committing immediately — so a split sequence's late tail
    ///   can still cancel it (see ``resolveStuckPartial()``).
    /// - Stuck-byte recovery: if a malformed or truncated sequence
    ///   sits at the front and the terminal really isn't sending
    ///   anything more, we consume one byte to make progress and
    ///   let the parser try again.
    private var staleFrames: Int = 0

    /// Set when a lone `ESC` has gone stale and we've removed it from the
    /// buffer but not yet committed it as the Escape key.
    ///
    /// A `0x1B` at the front is ambiguous: it can be the Escape key, OR the
    /// introducer of a CSI/SS3 sequence (arrow key, mouse report, focus event,
    /// …) whose remaining bytes were split into a later `read()`. Committing it
    /// as Escape too early strands the sequence's `[` / `O` to be parsed as a
    /// literal keystroke on the next pass — which is how an arrow key could
    /// momentarily register as `[` (e.g. jumping `TUIkitExample` to its `[` =
    /// Sliders page). So instead we hold the decision one round: the next
    /// ``readEvent()`` re-attaches the `ESC` if a `[`/`O` arrived (parsing the
    /// real sequence, no Escape emitted), and otherwise commits the Escape.
    private var pendingBareEsc: Bool = false

    /// The raw byte source feeding the parser. Production reads from stdin;
    /// tests inject a closure to script split reads deterministically, since
    /// the parser is otherwise impossible to drive without a live TTY.
    var readSource: (UnsafeMutableBufferPointer<UInt8>) -> Int = { buffer in
        read(STDIN_FILENO, buffer.baseAddress, buffer.count)
    }

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

    /// The terminal cell's height-to-width ratio, derived from the window's
    /// reported pixel size, or `nil` when the terminal doesn't report it.
    ///
    /// `TIOCGWINSZ` also carries the drawable area in pixels (`ws_xpixel`,
    /// `ws_ypixel`); dividing by the cell grid gives each cell's pixel size, and
    /// their ratio is the aspect an undistorted image needs (see
    /// ``View/imageCellAspect(_:)``). Not every terminal fills these fields —
    /// some report `0` — in which case this returns `nil` and callers keep their
    /// default. This self-corrects for the terminal + font + line spacing on the
    /// terminals that do report it, without any escape-sequence round trip.
    func cellPixelAspect() -> Double? {
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

        let cellWidth = Double(windowSize.ws_xpixel) / Double(windowSize.ws_col)
        let cellHeight = Double(windowSize.ws_ypixel) / Double(windowSize.ws_row)
        guard cellWidth > 0 else { return nil }
        let aspect = cellHeight / cellWidth
        // Guard against nonsense (a cell that's wider than tall, or absurdly
        // tall) so a misreporting terminal can't distort worse than the default.
        return (aspect >= 1.0 && aspect <= 4.0) ? aspect : nil
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

    /// Removes `n` bytes from the front of the buffer and, if the
    /// resulting size fits back inside ``baselineCapacity``, shrinks
    /// the backing allocation down too. The shrink is the reason
    /// for the explicit `reallocate(capacity:)` call: ``UniqueDeque``
    /// grows geometrically (1.5×) when needed but doesn't shrink on
    /// its own, so we have to ask.
    private func consume(_ n: Int) {
        input.removeFirst(n)
        if input.count <= Self.baselineCapacity
            && input.capacity > Self.baselineCapacity
        {
            input.reallocate(capacity: Self.baselineCapacity)
        }
    }

    /// Drains whatever stdin has waiting straight into the deque's
    /// uninitialised tail storage, with zero intermediate copies.
    ///
    /// Implementation:
    /// - ``UniqueDeque/append(addingCount:initializingWith:)`` hands
    ///   us an `OutputSpan<UInt8>` covering contiguous free space
    ///   at the back of the ring buffer.
    /// - `withUnsafeMutableBufferPointer` exposes that span as a
    ///   raw `UnsafeMutableBufferPointer`, which we pass straight to
    ///   `read(STDIN_FILENO, …)`.
    /// - We set the span's `written` count to whatever `read()`
    ///   returned; the deque keeps exactly those bytes initialised.
    ///
    /// In the (rare) case that the ring buffer's contiguous tail is
    /// smaller than our requested chunk, the deque calls our closure
    /// a second time for the wrapped portion — `read()` is called
    /// again for that span, which costs at most one extra syscall.
    ///
    /// - Returns: the number of new bytes drained from stdin.
    @discardableResult
    private func appendDrain() -> Int {
        var added = 0
        // Request up to one baseline chunk at a time. The deque
        // grows behind the scenes if we don't already have that much
        // free; subsequent drains can reuse the expanded capacity.
        input.append(addingCount: Self.baselineCapacity) { (span: inout OutputSpan<UInt8>) in
            span.withUnsafeMutableBufferPointer { buffer, written in
                let n = readSource(buffer)
                if n > 0 {
                    written = n
                    added += n
                } else {
                    written = 0
                }
            }
        }
        return added
    }

    /// The bracketed-paste start marker (`ESC [ 2 0 0 ~`).
    private static let pasteStart: [UInt8] = [
        0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E,
    ]

    /// The bracketed-paste end marker (`ESC [ 2 0 1 ~`).
    private static let pasteEnd: [UInt8] = [
        0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E,
    ]

    /// Maximum bytes we'll accumulate while waiting for a paste end
    /// marker. Anything beyond this is treated as a misbehaving
    /// terminal and discarded so it can't pin memory forever.
    private static let maxPasteBytes = 1 << 20  // 1 MiB

    /// Hard cap on bytes per regular event sequence — enough for
    /// the longest realistic CSI / SGR mouse report (three-digit
    /// coords).
    private static let maxEventBytes = 32

    /// Stale frames before a lone `ESC` is committed (the Escape-vs-sequence
    /// timeout). Short, so Escape stays responsive.
    private static let bareEscStaleFrames = 2

    /// Stale frames before an incomplete `ESC [` / `ESC O` is abandoned as a
    /// dead sequence. Generous: a read-split sequence's tail arrives within a
    /// frame or two, so by the time we reach this any real terminator is long
    /// present — we only get here for a sequence the terminal truly never
    /// finished. Until then we keep waiting rather than stranding its bytes
    /// (the leak that turned a split mouse report's `M` into a keystroke).
    private static let deadSequenceStaleFrames = 8

    /// Tries to peel one complete regular (non-paste) event off the
    /// front of ``inputBuffer``. Returns the raw bytes, or `nil` if
    /// the buffer doesn't have a complete sequence yet — in which
    /// case the bytes already there stay put for the next call.
    private func tryExtractRegularEvent() -> [UInt8]? {
        guard !input.isEmpty else { return nil }
        let first = input[0]

        // Plain (non-escape) byte: single-byte event.
        if first != 0x1B {
            consume(1)
            return [first]
        }

        // ESC + ?  — need at least the byte after ESC.
        guard input.count >= 2 else { return nil }
        let second = input[1]

        if second == 0x5B {  // ESC [ = CSI
            return tryExtractCSI()
        }

        if second == 0x4F {  // ESC O = SS3 (F1-F4 etc.)
            guard input.count >= 3 else { return nil }
            let bytes = [first, second, input[2]]
            consume(3)
            return bytes
        }

        if second == 0x1B {
            // Meta-prefixed escape sequence ("option as meta key"): ESC + a
            // full CSI/SS3 sequence, e.g. Option-Shift-Tab = ESC ESC [ Z.
            // Consuming just the two ESCs here stranded the sequence's tail
            // as literal keystrokes — the `[` then fired a page shortcut.
            // Extract the INNER event and re-attach the meta prefix; if the
            // inner sequence hasn't fully arrived, put the prefix back and
            // wait (the stale-partial machinery handles a dead one).
            consume(1)
            if let inner = tryExtractRegularEvent() {
                return [0x1B] + inner
            }
            input.insert(0x1B, at: 0)
            return nil
        }

        // Alt+key — 2 bytes total.
        let bytes = [first, second]
        consume(2)

        return bytes
    }

    /// CSI extractor — assumes `inputBuffer` starts with `ESC [`
    /// and the buffer has at least 2 bytes. Returns the full
    /// sequence bytes on success or `nil` if the terminator hasn't
    /// arrived yet.
    private func tryExtractCSI() -> [UInt8]? {
        guard input.count >= 3 else { return nil }
        let firstParam = input[2]

        // Legacy ("X10") mouse: ESC [ M <button+32> <x+32> <y+32>
        // M is the *introducer*, not the terminator, and the three
        // trailing coord bytes can take any value, so we just
        // require six bytes total.
        if firstParam == 0x4D {
            guard input.count >= 6 else { return nil }
            var bytes = [UInt8]()
            bytes.reserveCapacity(6)
            for i in 0..<6 { bytes.append(input[i]) }
            consume(6)
            return bytes
        }

        // Single-letter CSI (e.g. ESC[A for Up Arrow): the first
        // byte after `[` is already a terminator.
        if firstParam >= 0x40 && firstParam <= 0x7E {
            let bytes = [input[0], input[1], firstParam]
            consume(3)
            return bytes
        }

        // Scan forward for a real terminator (letter or `~`).
        var i = 3
        let cap = min(input.count, Self.maxEventBytes)

        while i < cap {
            let b = input[i]
            if b == 0x1B {
                // A new escape sequence started before this one terminated, so
                // this one was truncated (its terminator never arrived). Drop
                // just the malformed prefix and let the new sequence parse from
                // its `ESC` — otherwise its `[` would be mistaken for this
                // sequence's terminator and the rest would leak as keystrokes.
                consume(i)
                return nil
            }
            if b >= 0x40 && b <= 0x7E {
                var bytes = [UInt8]()
                bytes.reserveCapacity(i + 1)
                for j in 0...i { bytes.append(input[j]) }
                consume(i + 1)
                return bytes
            }
            i += 1
        }

        if i >= Self.maxEventBytes {
            // Maxed out without a terminator. Treat as malformed —
            // consume the truncated prefix and move on.
            var bytes = [UInt8]()
            bytes.reserveCapacity(Self.maxEventBytes)
            for j in 0..<Self.maxEventBytes { bytes.append(input[j]) }
            consume(Self.maxEventBytes)
            return bytes
        }

        // Buffer simply doesn't have the terminator yet.
        return nil
    }

    /// While `inPasteMode` is set, scans ``inputBuffer`` for the
    /// paste end marker. If found, builds a paste event from the
    /// content between markers and consumes through the end marker.
    /// Otherwise returns `nil` and leaves the buffer intact.
    private func tryExtractPaste() -> TerminalInput? {
        let endMarker = Self.pasteEnd
        guard input.count >= endMarker.count else { return nil }

        // Scan for the end marker. Note: the start marker is no
        // longer in the buffer — `readEvent()` consumed it before
        // setting `inPasteMode = true`.
        let searchEnd = input.count - endMarker.count + 1
        for start in 0..<searchEnd {
            var match = true
            for i in 0..<endMarker.count where input[start + i] != endMarker[i] {
                match = false
                break
            }
            if !match { continue }

            // Content is everything before the marker.
            var content = [UInt8]()
            content.reserveCapacity(start)
            for i in 0..<start { content.append(input[i]) }
            consume(start + endMarker.count)
            inPasteMode = false

            let text = String(bytes: content, encoding: .utf8)
                ?? String(content.map { Character(UnicodeScalar($0)) })
            return .key(KeyEvent(key: .paste(text)))
        }

        // No end marker yet. Safety: if a runaway paste fills more
        // than the cap, give up on it so we don't pin memory.
        if input.count > Self.maxPasteBytes {
            consume(input.count)
            inPasteMode = false
        }
        return nil
    }

    /// Whether the parser is holding something that needs another
    /// ``readEvent()`` soon to resolve, even if no new bytes arrive: a lone
    /// `ESC` mid Escape-vs-sequence disambiguation, a deferred bare `ESC`, or an
    /// incomplete escape sequence awaiting its terminator.
    ///
    /// The run loop reads this to schedule a bounded wake while it's true, so
    /// these resolve on a wall-clock deadline (a prompt Escape, a dropped dead
    /// sequence) instead of waiting for unrelated input or animation to tick the
    /// loop. It's `false` the rest of the time, so a genuinely idle screen still
    /// blocks with zero wakeups.
    var hasPendingInput: Bool {
        !input.isEmpty || pendingBareEsc
    }

    /// Reads up to one complete event from the input stream.
    /// Returns `nil` when nothing is ready right now.
    ///
    /// This is the single entry point for the input pipeline. It
    /// drains stdin opportunistically (once per call, only when
    /// the buffer is empty or a partial sequence needs more
    /// bytes), parses events out of the buffer, and never blocks
    /// the run loop.
    func readEvent() -> TerminalInput? {
        // Make sure there's something to inspect.
        if input.isEmpty {
            appendDrain()
        }

        // Resolve a deferred bare ESC (armed by `resolveStuckPartial`). If a CSI
        // `[` or SS3 `O` introducer is now at the front, the earlier `ESC` was
        // this sequence's introducer, split into a later read — re-attach it and
        // parse the real sequence (no Escape emitted, no `[` leaked as a literal
        // page shortcut). Otherwise the `ESC` really was the Escape key: commit
        // it now (the next byte, if any, is handled on the following call).
        if pendingBareEsc {
            pendingBareEsc = false
            if !input.isEmpty, input[0] == 0x5B || input[0] == 0x4F {
                input.insert(0x1B, at: 0)
            } else {
                return finalize(bytes: [0x1B])
            }
        }

        if inPasteMode {
            if let event = tryExtractPaste() {
                staleFrames = 0
                return event
            }
            // Paste content is still in flight. Give the kernel one
            // chance to deliver more right now, but don't sleep —
            // the main loop will spin again in ~24ms.
            let added = appendDrain()
            if added > 0, let event = tryExtractPaste() {
                staleFrames = 0
                return event
            }
            // Don't increment staleFrames in paste mode — large
            // pastes legitimately take several frames to fully
            // arrive, and the maxPasteBytes guard handles the
            // pathological case.
            return nil
        }

        if let bytes = tryExtractRegularEvent() {
            staleFrames = 0
            return finalize(bytes: bytes)
        }

        // No complete event yet. Try one more drain in case the
        // kernel has the missing bytes ready right now.
        let added = appendDrain()
        if added > 0, let bytes = tryExtractRegularEvent() {
            staleFrames = 0
            return finalize(bytes: bytes)
        }

        // Still nothing. If the buffer's empty there's no partial to
        // worry about; just return nil.
        guard !input.isEmpty else {
            staleFrames = 0
            return nil
        }

        // We have a stuck partial at the front. Wait one more frame
        // for the rest; if still nothing comes, give up on the front
        // of the buffer. This recovers bare Esc (which looks identical
        // to a partial CSI introducer until something definitive
        // arrives) and any truncated sequence the terminal will
        // never finish.
        if added == 0 {
            staleFrames += 1
            return resolveStuckPartial()
        }

        return nil
    }

    /// Called once per stale frame while a partial sits at the front of the
    /// buffer, and decides — based on how long it has been stuck — how to make
    /// progress without ever stranding part of a split escape sequence as a
    /// literal keystroke. Returns an event only when it pops a lone non-ESC
    /// byte; otherwise `nil` (still waiting, or it deferred/discarded).
    ///
    /// - A lone `ESC` is *deferred* (``pendingBareEsc``) after the short
    ///   ``bareEscStaleFrames`` timeout, not committed outright: its
    ///   continuation may be a CSI/SS3 sequence split into a later read. The
    ///   next ``readEvent()`` re-attaches it if a `[`/`O` arrived, else commits
    ///   the Escape.
    /// - An incomplete `ESC [` / `ESC O` is unambiguously a control sequence, so
    ///   we KEEP WAITING for its terminator — a read-split sequence's tail
    ///   (arrow, mouse report, …) arrives on a later read and completes it.
    ///   Stranding it instead leaked bytes as keystrokes: the introducer `[`
    ///   (→ Sliders page) or, for a mouse drag, the terminator `M` (→ a stray
    ///   key). Only after the generous ``deadSequenceStaleFrames`` timeout — by
    ///   which point any real terminator has long arrived — is a truly dead
    ///   sequence dropped as a unit.
    /// - Any other stuck byte is consumed singly to make progress.
    private func resolveStuckPartial() -> TerminalInput? {
        let first = input[0]

        if first == 0x1B {
            if input.count == 1 {
                // Lone ESC — Escape-vs-sequence ambiguity. Defer after the
                // short timeout so a split sequence's tail can still cancel it.
                if staleFrames >= Self.bareEscStaleFrames {
                    staleFrames = 0
                    input.removeFirst(1)
                    pendingBareEsc = true
                }
                return nil
            }
            if input[1] == 0x5B || input[1] == 0x4F {
                // Incomplete CSI/SS3: wait for the terminator; drop only a
                // long-dead sequence.
                if staleFrames >= Self.deadSequenceStaleFrames {
                    staleFrames = 0
                    consume(input.count)
                }
                return nil
            }
        }

        // Any other stuck byte (not a recognised escape introducer): make
        // progress by popping one, after the short timeout.
        if staleFrames >= Self.bareEscStaleFrames {
            staleFrames = 0
            if let byte = input.popFirst() {
                return finalize(bytes: [byte])
            }
        }
        return nil
    }

    /// Wraps raw event bytes into a ``TerminalInput``. Detects
    /// the bracketed-paste start marker and flips into paste mode.
    private func finalize(bytes: [UInt8]) -> TerminalInput? {
        // SGR mouse report: ESC [ < … M / m
        if bytes.count >= 9, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x3C {
            if let mouse = MouseEvent.parseSGR(bytes) {
                return .mouse(mouse)
            }
        }

        // Legacy mouse report: ESC [ M <b> <x> <y>
        if bytes.count == 6, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x4D {
            if let mouse = MouseEvent.parseLegacy(bytes) {
                return .mouse(mouse)
            }
            // Recognisably a legacy report but malformed — drop it
            // rather than letting the coord bytes leak as keystrokes.
            return nil
        }

        // Bracketed paste start: switch into paste mode and try to
        // extract the content right now if it's already buffered.
        if bytes == Self.pasteStart {
            inPasteMode = true
            return tryExtractPaste()
        }

        if let key = KeyEvent.parse(bytes) {
            return .key(key)
        }
        return nil
    }

    /// Reads raw event bytes — back-compat for the
    /// ``TerminalProtocol`` interface. New code should prefer
    /// ``readEvent()`` which gives you parsed events directly and
    /// handles bracketed paste, mouse reports, and the bare-Esc
    /// disambiguation in one place.
    ///
    /// - Returns: One event's bytes, or `[]` if no complete event
    ///   is buffered.
    func readBytes(maxBytes: Int = 32) -> [UInt8] {
        if input.isEmpty { appendDrain() }
        return tryExtractRegularEvent() ?? []
    }

    /// Reads a key event from the terminal — back-compat for the
    /// ``TerminalProtocol`` interface. New code should call
    /// ``readEvent()`` and switch on the returned ``TerminalInput``.
    ///
    /// If the next event is a mouse event it is consumed and `nil`
    /// is returned — the legacy interface has nowhere to surface it.
    /// Callers that care about mouse events must use `readEvent()`.
    func readKeyEvent() -> KeyEvent? {
        guard let event = readEvent() else { return nil }
        if case .key(let key) = event { return key }
        return nil
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
