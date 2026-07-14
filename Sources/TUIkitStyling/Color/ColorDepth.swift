//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorDepth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The color depth supported by the terminal.
///
/// Detected automatically from `TERM` and `COLORTERM` environment
/// variables. The detected value is cached and used by
/// ``ANSIRenderer`` to downsample colors that exceed the terminal's
/// capabilities.
///
/// ## Detection Order
///
/// 1. `COLORTERM` containing `truecolor` or `24bit` → ``truecolor``
/// 2. `TERM` not set → ``truecolor`` (backward-compatible default)
/// 3. `TERM` equal to `dumb` → ``noColor``
/// 4. `TERM` containing `direct` → ``truecolor``
/// 5. `TERM` containing `color` → ``basic16``
/// 6. `TERM` set but unrecognized → ``basic16``
///
/// > Note: `NO_COLOR` (https://no-color.org/) is not handled here because
/// > it represents a user preference, not a terminal capability. It should
/// > be handled at the output layer (e.g., by stripping ANSI codes before
/// > writing to stdout). Use ``noColor`` directly if you need to disable
/// > color output programmatically.
///
/// ## Override
///
/// Set ``current`` to override the detected value, for example when
/// building for a known target environment or in tests:
///
/// ```swift
/// ColorDepth.current = .palette256
/// ```
public enum ColorDepth: Int, Sendable, Comparable {
    /// No color output.
    ///
    /// Detected when `TERM` is `dumb`. Can also be set manually
    /// to disable color output programmatically.
    /// ``ANSIRenderer`` emits no color escape codes at this level;
    /// text attributes (bold, underline, etc.) are still emitted.
    case noColor = 0

    /// 16 colors: 8 standard + 8 bright ANSI colors (SGR 30–37, 90–97).
    case basic16 = 1

    /// 256 colors: 16 ANSI + 6×6×6 RGB cube + 24 grayscale (SGR 38;5;n).
    case palette256 = 2

    /// 24-bit true color / 16.7 million colors (SGR 38;2;r;g;b).
    case truecolor = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Detection

extension ColorDepth {
    /// The process-wide colour depth, before any task-local pin.
    ///
    /// `nonisolated(unsafe)` is intentional: the value is set once during
    /// initialization (from environment variables that don't change) and
    /// read from the render path. Any override is expected before rendering
    /// starts.
    nonisolated(unsafe) private static var processCurrent: ColorDepth = detect()

    /// A task-scoped pin of ``current``, bound by ``withCurrent(_:operation:)``.
    ///
    /// Task-local rather than a plain global so a scoped pin — a test
    /// asserting on rendered colour, a subtree deliberately rendered at a
    /// different depth — is visible ONLY to work on the pinning task.
    /// Parallel tasks (notably Swift Testing's parallel test runner) keep
    /// seeing the process value; a global mutate-and-restore would bleed a
    /// pinned depth into every concurrently-rendering test.
    @TaskLocal private static var taskCurrent: ColorDepth?

    /// The color depth to use for rendering.
    ///
    /// Automatically detected from environment variables at launch.
    /// Assign a value to override detection process-wide (expected before
    /// rendering starts); use ``withCurrent(_:operation:)`` for a scoped,
    /// task-local pin.
    public static var current: ColorDepth {
        get { taskCurrent ?? processCurrent }
        set { processCurrent = newValue }
    }

    /// Runs `operation` with ``current`` pinned to `depth` on the current
    /// task, restoring the previous behaviour afterwards.
    ///
    /// The pin is task-local: concurrent tasks are unaffected, so parallel
    /// test runs can each pin their own depth without serialization.
    @discardableResult
    public static func withCurrent<T>(
        _ depth: ColorDepth, operation: () throws -> T
    ) rethrows -> T {
        try $taskCurrent.withValue(depth, operation: operation)
    }

    /// Async variant of ``withCurrent(_:operation:)`` — the pin covers the
    /// whole async operation, including its suspensions (task-locals are
    /// inherited across awaits and by child tasks, but not by detached ones).
    @discardableResult
    public static func withCurrent<T>(
        _ depth: ColorDepth, operation: () async throws -> T
    ) async rethrows -> T {
        try await $taskCurrent.withValue(depth, operation: operation)
    }

    /// Detects the terminal's color depth from environment variables.
    ///
    /// This method inspects `COLORTERM` and `TERM` in the order
    /// described in ``ColorDepth``. It is called once to initialize
    /// ``current`` and can be called again if the environment changes.
    public static func detect() -> ColorDepth {
        let environment = ProcessInfo.processInfo.environment

        // COLORTERM is the most reliable indicator of truecolor support.
        // Modern terminals (iTerm2, GNOME Terminal, Alacritty, WezTerm,
        // Ghostty, etc.) set this to "truecolor" or "24bit".
        if let colorterm = environment["COLORTERM"]?.lowercased() {
            if colorterm.contains("truecolor") || colorterm.contains("24bit") {
                return .truecolor
            }
        }

        // TERM encodes the terminal type and sometimes color depth.
        guard let term = environment["TERM"]?.lowercased() else {
            // TERM is not set. This typically means the process is not
            // running in a traditional terminal (e.g. IDE, redirected
            // output, or env wasn't propagated). Default to truecolor
            // to preserve backward compatibility — we only downgrade
            // when there is positive evidence of limited capabilities.
            return .truecolor
        }

        // TERM=dumb means a very limited terminal (e.g. Emacs shell,
        // CI log viewers). No escape codes should be emitted.
        if term == "dumb" {
            return .noColor
        }

        // "direct" suffix indicates direct-color (24-bit) support,
        // e.g. "xterm-direct", "iterm2-direct".
        if term.contains("direct") {
            return .truecolor
        }

        // "-256color" suffix is the standard indicator for 256-color
        // support, e.g. "xterm-256color", "screen-256color", "tmux-256color".
        if term.contains("256color") {
            return .palette256
        }

        // "-Ncolor" pattern (e.g. "xterm-16color") or any TERM value
        // containing "color" indicates at least basic color support.
        if term.contains("color") {
            return .basic16
        }

        // TERM is set but doesn't match any known pattern.
        // Default to basic 16-color as the safest assumption for
        // an unknown terminal type.
        return .basic16
    }
}
