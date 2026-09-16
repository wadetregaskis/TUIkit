//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorRequester.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// When the terminal is asked what colours it paints, after the startup
/// exchange has closed.
///
/// `TerminalClient.detectColors(using:)` asks once, before the first frame, and
/// waits for its fence. Under tmux it leaves the sixteen ANSI slots out of that
/// request, because tmux forwards OSC 4 to exactly one client and holds the
/// fence about half a second when that client does not answer: 516–539 ms for a
/// single slot and 515–542 ms for the whole startup batch, over 312 exchanges
/// (measured, tmux 3.7c — `Documentation/Terminal-compatibility.md`). Half a
/// second spent there is half a second before anything is on screen.
///
/// So under tmux the slots are asked for after the first frame instead, by
/// ``noteFrameWritten()``. Nothing waits for the answer:
/// - the request is written and forgotten, never read back, so tmux's wait is
///   tmux's own — and it holds no output of ours (measured: a line printed
///   straight after each batch reached the client in 0.15–0.9 ms while the
///   fence was still outstanding);
/// - what comes back arrives as a late reply. The input parser keeps it
///   (`Terminal.noteVolunteeredColorReply`) where it would have dropped it with
///   everything else nobody typed, and ``TerminalColorRefresher`` publishes what
///   it adds to what the exchange knew, repainting the screen.
///
/// Off tmux there is nothing left to ask: the startup exchange asked for the
/// slots itself, in the same round trip as the default pair, and waited for
/// them.
///
/// Separate from `RenderLoop` for the reason ``ClientCapabilityRefresher`` gives:
/// the rule is unit-testable on its own, with the requests recorded rather than
/// written to a terminal.
@MainActor
internal final class TerminalColorRequester {

    /// Whether this is tmux, the one host with colours still to ask for once the
    /// app is drawing.
    private let isTmux: Bool

    /// Where a request goes. The terminal, in an app — written outside a frame,
    /// so it is one write of its own rather than bytes spliced into a frame's.
    private let send: @MainActor (String) -> Void

    /// Whether the slots have been asked for, so the question is asked once
    /// rather than after every frame.
    private var askedForSlots = false

    init(isTmux: Bool, send: @escaping @MainActor (String) -> Void) {
        self.isTmux = isTmux
        self.send = send
    }

    /// A frame has been written to the terminal.
    ///
    /// The first one under tmux asks for the sixteen ANSI slots; every frame
    /// after it asks for nothing, and off tmux no frame asks for anything.
    func noteFrameWritten() {
        guard isTmux, !askedForSlots else { return }
        askedForSlots = true
        send(TerminalColorQuery.slotsRequest)
    }
}
