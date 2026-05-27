//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalInput.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Terminal Input

/// A single input event read from the terminal.
///
/// Terminals report keys and mouse activity through the same input
/// stream, distinguished only by the escape sequence that wraps each
/// event. `TerminalInput` is the discriminated union the parser returns
/// so call sites can pattern-match against either kind.
public enum TerminalInput: Sendable, Equatable {
    /// A keyboard event (key press, paste, etc.).
    case key(KeyEvent)

    /// A mouse event (click, release, motion, drag, scroll).
    case mouse(MouseEvent)
}
