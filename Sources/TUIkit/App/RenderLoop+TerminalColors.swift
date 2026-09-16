//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+TerminalColors.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - What the terminal says about its colours, once the app is drawing

/// The run loop's side of the two objects that keep the record of what the
/// terminal paints: ``TerminalColorRefresher``, which publishes what the
/// terminal says, and ``TerminalColorRequester``, which decides when it is
/// asked.
///
/// Neither rule lives here — each is testable on its own, with what it publishes
/// or asks recorded rather than assigned process-wide or written to a terminal.
/// What lives here is the wiring: the moments the loop knows about, handed on.
///
/// Separate from `RenderLoop.swift` because that file is at its length limit,
/// and this is a coherent thing to lift out — the same bargain
/// `Terminal+Replies.swift` makes with `Terminal.swift`. It is why the two
/// properties it reaches are the only ones on the type that are not private:
/// `private` is file scope, and the type itself is internal either way.
extension RenderLoop {

    /// Applies the colour answers the input parser siphoned out of one drain's
    /// bytes — see ``TerminalColorRefresher``, which publishes what they add to
    /// what was known and asks for the repaint.
    ///
    /// Called once per drain with whatever `Terminal.takeVolunteeredColorReplies`
    /// held, which on almost every frame is nothing.
    ///
    /// `sawStatusFence` is the other half of the same drain: the `CSI 0 n` that
    /// says a request made here has been answered as far as it is going to be,
    /// so the one waiting behind it may go out (see ``TerminalColorRequester``).
    func noteVolunteeredColorReplies(_ bytes: [UInt8], sawStatusFence: Bool) {
        terminalColors.noteReplies(bytes)
        if sawStatusFence { colorQueries.noteStatusFence() }
    }
}
