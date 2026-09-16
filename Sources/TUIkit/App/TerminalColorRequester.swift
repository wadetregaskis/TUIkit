//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorRequester.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// When the terminal is asked what colours it paints, after the startup
/// exchange has closed.
///
/// `TerminalClient.detectColors(using:)` asks once, before the first frame, and
/// waits for its fence. Two things are left for this:
///
/// **The slots tmux would have made us wait for.** Under tmux the startup
/// request leaves the sixteen ANSI slots out, because tmux forwards OSC 4 to
/// exactly one client and holds the fence about half a second when that client
/// does not answer: 516–539 ms for a single slot and 515–542 ms for the whole
/// startup batch, over 312 exchanges (measured, tmux 3.7c —
/// `Documentation/Terminal-compatibility.md`). Half a second spent there is half
/// a second before anything is on screen. So they are asked for after the first
/// frame instead, by ``noteFrameWritten()``.
///
/// **The terminal may be a different one.** The screen is thrown away on a
/// resize, on a resumed suspend, and on the tmux client change our hooks turn
/// into a SIGWINCH — each of them a moment when the colours on screen may
/// belong to a terminal that is no longer there. ``screenInvalidated(terminalHasAnswered:)``
/// asks again, for everything: the default pair belongs to whichever client
/// answers now, not to the one that answered at startup.
///
/// **The user may have changed it while they were away.** A window that has
/// just taken the focus back (``focusRegained(terminalHasAnswered:)``) is a
/// window somebody was looking at something else in: a profile switched, a
/// theme flipped with the system's, the tab closed and another opened in its
/// place. None of that throws our screen away, and a host that would say so
/// unprompted is a host that reports its own theme — which most do not. So
/// focus coming back is the moment to ask, and it asks for everything, for the
/// reason a thrown-away screen does.
///
/// Nothing waits for any of these answers:
/// - a request is written and forgotten, never read back, so tmux's wait is
///   tmux's own — and it holds no output of ours (measured: a line printed
///   straight after each batch reached the client in 0.15–0.9 ms while the fence
///   was still outstanding);
/// - what comes back arrives as a late reply. The input parser keeps it
///   (`Terminal.noteVolunteeredColorReply`) where it would have dropped it with
///   everything else nobody typed, and ``TerminalColorRefresher`` publishes what
///   it adds to what was known, repainting the screen.
///
/// **What is not asked, and why.** A terminal that has never said anything of
/// its own about its colours is not asked again: it answered nothing when it was
/// asked properly, and a resize is no reason to believe it has learned how. The
/// two exceptions are tmux, where the silent client may not be the client
/// attached now, and a terminal that has reported its own theme with a
/// `CSI ? 997` — that one speaks this protocol, and has just said its colours
/// changed. `TerminalColorRefresher.hasAnsweredAboutColors` is that fact.
///
/// Separate from `RenderLoop` for the reason ``ClientCapabilityRefresher`` gives:
/// the rule is unit-testable on its own, with the requests recorded rather than
/// written to a terminal.
@MainActor
internal final class TerminalColorRequester {

    /// How long a request waits for its fence before it is sent once more: one
    /// second.
    ///
    /// Twice tmux's own wait, which is the longest measured anywhere: a silent
    /// client holds the fence 503–552 ms (median 522 over 312 exchanges, tmux
    /// 3.7c), where every host that answers is back in under 40 ms. So a fence
    /// that has not arrived in a second was lost rather than delayed.
    static let defaultFenceTimeoutNanos: UInt64 = 1_000_000_000

    /// Whether this is tmux, the one host with colours still to ask for once the
    /// app is drawing, and the one whose silence says nothing about the terminal
    /// the user is actually looking at.
    private let isTmux: Bool

    /// Where a request goes. The terminal, in an app — written outside a frame,
    /// so it is one write of its own rather than bytes spliced into a frame's.
    private let send: @MainActor (String) -> Void

    /// How long ``defaultFenceTimeoutNanos`` says to wait. Injectable so a test
    /// does not spend a real second per case.
    private let fenceTimeoutNanos: UInt64

    /// Whether the slots have been asked for after a frame, so that question is
    /// asked once rather than after every frame.
    private var askedForSlots = false

    /// The request that has gone out and whose fence has not come back.
    private var outstanding: String?

    /// A request made while another was outstanding, waiting for it to finish.
    /// At most one, which is what makes a burst one resend.
    private var queued: String?

    /// Whether ``outstanding`` has already been sent a second time.
    private var retried = false

    /// At most one request in flight, and one made mid-flight re-runs exactly
    /// once — the rule ``ClientCapabilityRefresher`` coalesces its probes by,
    /// for the same reason: the answer in flight was asked for before this
    /// request's cause happened, so it cannot satisfy it. A resize drag is
    /// therefore one request and one resend, not one per SIGWINCH.
    private var coalescer = ProbeCoalescer()

    /// Bumped whenever the request a deadline belongs to is answered, given up
    /// or replaced, so a timer sleeping toward a request that is already settled
    /// wakes up and finds it is talking about nothing.
    private var deadlineGeneration = 0

    /// Deadlines still sleeping. Tracked so a test can tell "settled" from
    /// "about to resend", as `ClientCapabilityRefresher.sleepingRetries` is.
    private var sleepingDeadlines = 0

    /// - Parameter fenceTimeoutNanos: How long a request waits for its fence
    ///   before it is sent once more; ``defaultFenceTimeoutNanos`` when `nil`.
    ///   Optional rather than a defaulted argument because a default argument
    ///   expression cannot name a class's own `Self`.
    init(
        isTmux: Bool,
        fenceTimeoutNanos: UInt64? = nil,
        send: @escaping @MainActor (String) -> Void
    ) {
        self.isTmux = isTmux
        self.fenceTimeoutNanos = fenceTimeoutNanos ?? Self.defaultFenceTimeoutNanos
        self.send = send
    }

    /// Whether no request is outstanding, queued, or sleeping toward a resend —
    /// the moment a test can assert without racing a deadline.
    var isIdleForTesting: Bool {
        coalescer.isIdle && sleepingDeadlines == 0 && queued == nil
    }

    /// A frame has been written to the terminal.
    ///
    /// The first one under tmux asks for the sixteen slots; every frame after it
    /// asks for nothing, and off tmux no frame asks for anything, because the
    /// startup exchange asked for the slots itself and waited for them.
    func noteFrameWritten() {
        guard isTmux, !askedForSlots else { return }
        askedForSlots = true
        ask(TerminalColorQuery.slotsRequest)
    }

    /// The screen has been thrown away and is about to be drawn again — a
    /// resize, a resumed suspend, a tmux client change.
    ///
    /// - Parameter terminalHasAnswered: Whether the terminal has ever said
    ///   anything of its own about its colours
    ///   (`TerminalColorRefresher.hasAnsweredAboutColors`). One that has not is
    ///   left alone unless this is tmux.
    func screenInvalidated(terminalHasAnswered: Bool) {
        askEverything(terminalHasAnswered: terminalHasAnswered)
    }

    /// The terminal's window, tab or pane has the focus again, and the scene was
    /// inactive until now.
    ///
    /// Only when the focus actually moved. A terminal may report focus in as
    /// reporting is enabled (`Terminal.enableRawMode`), with the scene already
    /// active and the startup exchange a moment old, and that must not cost a
    /// second 170-byte request; `AppRunner.terminalFocusChanged` is where that
    /// is decided, because it is what knows the phase.
    ///
    /// - Parameter terminalHasAnswered: As ``screenInvalidated(terminalHasAnswered:)``
    ///   takes it, and skipping for the same reason: a terminal that answered
    ///   nothing when it was asked properly has not learned how while the user
    ///   was in another window.
    func focusRegained(terminalHasAnswered: Bool) {
        askEverything(terminalHasAnswered: terminalHasAnswered)
    }

    /// The whole request, for a moment when the terminal may be a different one
    /// or may have been changed: the default pair as well as the slots.
    ///
    /// Skipped for a terminal that has never said anything of its own about its
    /// colours, unless this is tmux — see the type's discussion.
    private func askEverything(terminalHasAnswered: Bool) {
        guard isTmux || terminalHasAnswered else { return }
        ask(TerminalColorQuery.nativeRequest)
    }

    /// The terminal reported its own theme, `CSI ? 997 ; Ps n` — which it does
    /// unprompted while mode 2031 is set (`Terminal.enableRawMode`).
    ///
    /// Asked without the skip rule the other two apply, because the terminal has
    /// just spoken: `hasAnsweredAboutColors` is true by the time this is
    /// reached, so a guard on it would only restate that. The report names light
    /// or dark and no colour at all, so everything it implies has to be asked
    /// for — and it is the only notice most hosts give that anything changed.
    func terminalReportedTheme() {
        ask(TerminalColorQuery.nativeRequest)
    }

    /// The terminal answered a request's fence, `CSI 0 n`, which the input
    /// parser kept out of the keystrokes.
    ///
    /// That is the whole of what the fence is for here: it says the request has
    /// been answered as far as it is going to be, so the one waiting behind it
    /// may go out. What the answers SAID is the refresher's business, not this.
    func noteStatusFence() {
        guard outstanding != nil else { return }
        finishOutstanding()
    }

    /// Sends `request` now, or remembers it for when the outstanding one is
    /// answered.
    private func ask(_ request: String) {
        queued = request
        guard coalescer.requestProbe() else { return }
        sendQueued()
    }

    private func sendQueued() {
        guard let request = queued else { return }
        queued = nil
        outstanding = request
        retried = false
        send(request)
        armDeadline()
    }

    /// The outstanding request is done with, answered or given up: anything that
    /// arrived while it was in flight goes out now.
    private func finishOutstanding() {
        outstanding = nil
        deadlineGeneration &+= 1
        if coalescer.probeCompleted() { sendQueued() }
    }

    private func armDeadline() {
        deadlineGeneration &+= 1
        let generation = deadlineGeneration
        let timeout = fenceTimeoutNanos
        sleepingDeadlines += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard let self else { return }
            self.sleepingDeadlines -= 1
            self.deadlinePassed(generation)
        }
    }

    /// A request's fence never came. It is sent once more, and if that goes
    /// unanswered too the request is given up — not retried forever, because a
    /// terminal that answers no `CSI 5n` never will, and this must not become a
    /// poll loop. Giving up leaves nothing outstanding, so the next thrown-away
    /// screen asks again from a clean start.
    private func deadlinePassed(_ generation: Int) {
        guard generation == deadlineGeneration, let request = outstanding else { return }
        guard !retried else {
            finishOutstanding()
            return
        }
        retried = true
        send(request)
        armDeadline()
    }
}
