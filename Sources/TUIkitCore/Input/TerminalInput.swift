//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalInput.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Terminal Input

/// A single input event read from the terminal.
///
/// Terminals report keys, mouse activity and focus changes through the
/// same input stream, distinguished only by the escape sequence that wraps
/// each event. `TerminalInput` is the discriminated union the parser
/// returns so call sites can pattern-match against each kind.
public enum TerminalInput: Sendable, Equatable {
    /// A keyboard event (key press, paste, etc.).
    case key(KeyEvent)

    /// A mouse event (click, release, motion, drag, scroll).
    case mouse(MouseEvent)

    /// The terminal window, tab or pane gained (`isFocused == true`) or lost
    /// (`false`) focus: a focus report, `ESC [ I` or `ESC [ O`.
    ///
    /// A terminal sends these only while focus reporting (DEC private mode
    /// 1004) is on, and many never send them at all: a terminal without the
    /// mode, or tmux without its `focus-events` option. Treat one as a hint
    /// that arrived, never as a signal that is guaranteed to.
    case focusChanged(isFocused: Bool)
}
