//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorRequestTests.swift
//
//  Asking the terminal for its colours after the startup exchange has closed.
//
//  The startup exchange asks once, before the first frame, and under tmux it
//  leaves the sixteen ANSI slots out: tmux forwards OSC 4 to one client and
//  holds the fence about half a second when that client is silent (measured,
//  tmux 3.7c). So under tmux the slots are asked for after the first frame
//  instead, where nothing that draws waits for the answer — which arrives as a
//  late reply, through the parser and `TerminalColorRefresher` (step 5a).
//
//  A screen thrown away — a resize, a resumed suspend — is the other moment
//  worth asking at: the terminal in front of the user may be a different one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitStyling

/// A terminal whose byte source hands over whatever the test has staged, as
/// `TerminalInputParsingTests` drives the parser: no TTY, and the split between
/// reads is the test's to choose.
@MainActor
private func makeScriptedTerminal() -> (Terminal, (String) -> Void) {
    final class ByteBox { var bytes: [UInt8] = [] }
    let terminal = Terminal()
    let box = ByteBox()
    terminal.readSource = { buffer in
        guard !box.bytes.isEmpty else { return 0 }
        let count = min(box.bytes.count, buffer.count)
        for index in 0..<count { buffer[index] = box.bytes[index] }
        box.bytes.removeFirst(count)
        return count
    }
    return (terminal, { box.bytes.append(contentsOf: Array($0.utf8)) })
}

/// Everything `readEvent()` delivers while the buffer holds complete events.
@MainActor
private func events(_ terminal: Terminal, pumps: Int = 8) -> [TerminalInput] {
    (0..<pumps).compactMap { _ in terminal.readEvent() }
}

/// What a requester asked the terminal for.
@MainActor
private final class RequestSink {
    var sent: [String] = []
}

/// The rule for when a request goes out, without a terminal: what
/// `TerminalColorRequester` decides, and what it sends when it decides to ask.
@MainActor
@Suite("Asking the terminal for its colours again")
struct TerminalColorRequesterTests {

    private func makeRequester(isTmux: Bool) -> (TerminalColorRequester, RequestSink) {
        let sink = RequestSink()
        let requester = TerminalColorRequester(
            isTmux: isTmux, fenceTimeoutNanos: 5_000_000, send: { sink.sent.append($0) })
        return (requester, sink)
    }

    @Test("Under tmux the sixteen slots are asked for after the first frame")
    func tmuxAsksAfterTheFirstFrame() {
        let (requester, sink) = makeRequester(isTmux: true)
        #expect(sink.sent.isEmpty, "nothing is asked before a frame is on screen")

        requester.noteFrameWritten()
        #expect(sink.sent == [TerminalColorQuery.slotsRequest])
    }

    @Test("The slots are asked for once, not after every frame")
    func tmuxAsksOnlyOnce() {
        let (requester, sink) = makeRequester(isTmux: true)
        for _ in 0..<5 { requester.noteFrameWritten() }
        #expect(sink.sent == [TerminalColorQuery.slotsRequest])
    }

    /// Off tmux the startup exchange asked for the slots itself, in the same
    /// round trip as the default pair, and waited for the answer.
    @Test("Off tmux no frame asks for anything: the startup exchange already did")
    func nativeHostAsksNothingAfterAFrame() {
        let (requester, sink) = makeRequester(isTmux: false)
        for _ in 0..<5 { requester.noteFrameWritten() }
        #expect(sink.sent.isEmpty)
    }
}

/// Asking again once the app is running: what a thrown-away screen asks for, on
/// which hosts, and what happens when the fence never comes back.
@MainActor
@Suite("Asking the terminal again when the screen is thrown away")
struct TerminalColorReQueryTests {

    private func makeRequester(isTmux: Bool) -> (TerminalColorRequester, RequestSink) {
        let sink = RequestSink()
        let requester = TerminalColorRequester(
            isTmux: isTmux, fenceTimeoutNanos: 5_000_000, send: { sink.sent.append($0) })
        return (requester, sink)
    }

    @Test("A screen thrown away on a terminal that has answered asks it everything again")
    func answeringTerminalIsAskedAgain() {
        let (requester, sink) = makeRequester(isTmux: false)
        requester.screenInvalidated(terminalHasAnswered: true)
        #expect(
            sink.sent == [TerminalColorQuery.nativeRequest],
            "the pair as well as the slots: this may be a different terminal now")
    }

    @Test("A terminal that has never answered is left alone")
    func silentTerminalIsLeftAlone() {
        let (requester, sink) = makeRequester(isTmux: false)
        requester.screenInvalidated(terminalHasAnswered: false)
        requester.screenInvalidated(terminalHasAnswered: false)
        #expect(sink.sent.isEmpty, "a host that answers nothing was asked \(sink.sent.count) times")
    }

    @Test("Under tmux even a pane that has heard nothing is asked again")
    func tmuxPaneIsAlwaysAskedAgain() {
        let (requester, sink) = makeRequester(isTmux: true)
        requester.screenInvalidated(terminalHasAnswered: false)
        #expect(
            sink.sent == [TerminalColorQuery.nativeRequest],
            "the client that was silent may not be the client attached now")
    }

    @Test("A burst of invalidations is one request, and exactly one resend when the fence lands")
    func burstCoalescesIntoOneResend() {
        let (requester, sink) = makeRequester(isTmux: false)
        for _ in 0..<4 { requester.screenInvalidated(terminalHasAnswered: true) }
        #expect(sink.sent.count == 1, "a resize drag asked \(sink.sent.count) times")

        requester.noteStatusFence()
        #expect(sink.sent.count == 2, "the invalidations that arrived mid-flight asked for nothing")

        requester.noteStatusFence()
        #expect(sink.sent.count == 2, "asked again with nothing left to ask for")
    }

    @Test("The first frame's own request is what a later invalidation waits behind")
    func theFirstFrameRequestIsOutstandingToo() {
        let (requester, sink) = makeRequester(isTmux: true)
        requester.noteFrameWritten()
        #expect(sink.sent == [TerminalColorQuery.slotsRequest])

        requester.screenInvalidated(terminalHasAnswered: true)
        #expect(sink.sent.count == 1, "asked while the first frame's request was still outstanding")

        requester.noteStatusFence()
        #expect(sink.sent == [TerminalColorQuery.slotsRequest, TerminalColorQuery.nativeRequest])
    }

    @Test("A fence that never comes is asked for again once, and then given up")
    func lostFenceIsAskedAgainOnce() async throws {
        let (requester, sink) = makeRequester(isTmux: false)
        requester.screenInvalidated(terminalHasAnswered: true)
        #expect(sink.sent.count == 1)

        try await waitUntilSettled(requester)
        #expect(
            sink.sent == [TerminalColorQuery.nativeRequest, TerminalColorQuery.nativeRequest],
            "a lost fence was never asked for again: \(sink.sent.count) request(s)")

        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(sink.sent.count == 2, "a terminal that answers no fence must not be polled")

        // Given up, not wedged: the next thrown-away screen asks again.
        requester.screenInvalidated(terminalHasAnswered: true)
        #expect(sink.sent.count == 3)
    }

    /// Twice tmux's own wait: a silent client holds the fence 503–552 ms
    /// (measured, tmux 3.7c), so a second says lost rather than slow.
    @Test("The wait for a fence is one second")
    func fenceTimeoutIsOneSecond() {
        #expect(TerminalColorRequester.defaultFenceTimeoutNanos == 1_000_000_000)
    }

    private func waitUntilSettled(_ requester: TerminalColorRequester) async throws {
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 5_000_000)
            if requester.isIdleForTesting { return }
        }
        Issue.record("the requester never settled")
    }
}

/// Whether the terminal has ever said anything of its own about its colours,
/// which is what decides whether it is worth asking again.
@MainActor
@Suite("What counts as the terminal having answered")
struct TerminalColorAnsweredTests {

    typealias RGB = TerminalColors.RGB

    private func refresher(known: TerminalColors) -> TerminalColorRefresher {
        TerminalColorRefresher(
            known: known, environment: [:], publish: { _ in }, onChange: {})
    }

    @Test("A terminal that said nothing has not answered")
    func silenceIsNoAnswer() {
        #expect(refresher(known: .unknown).hasAnsweredAboutColors == false)
    }

    /// `prefersDark` can come from `COLORFGBG`, which is the environment
    /// talking about a terminal that may not even be attached any more.
    @Test("A dark-mode hint alone is not the terminal answering")
    func environmentHintIsNoAnswer() {
        #expect(refresher(known: TerminalColors(prefersDark: false)).hasAnsweredAboutColors == false)
    }

    @Test("A colour the startup exchange heard is an answer")
    func startupColourIsAnAnswer() {
        let known = TerminalColors(background: RGB(red: 40, green: 44, blue: 52), prefersDark: true)
        #expect(refresher(known: known).hasAnsweredAboutColors)
    }

    @Test("A colour named since, or a theme report, is an answer too")
    func lateReplyIsAnAnswer() {
        let named = refresher(known: .unknown)
        let reply = TerminalColorLateReplyTests.reply("11", RGB(red: 40, green: 44, blue: 52))
        named.noteReplies(Array(reply.utf8))
        #expect(named.hasAnsweredAboutColors)

        let reported = refresher(known: .unknown)
        reported.noteReplies(Array("\u{1B}[?997;1n".utf8))
        #expect(reported.hasAnsweredAboutColors, "a 997 is the terminal speaking for itself")
    }
}

/// The fence, `CSI 0 n`: the terminal saying a request has been answered.
@MainActor
@Suite("The fence of a request made after the startup exchange")
struct TerminalStatusFenceTests {

    @Test("The fence is kept for the requester, and not typed at the app")
    func fenceIsKeptAndNotTyped() {
        let (terminal, stage) = makeScriptedTerminal()
        stage("q\u{1B}[0nj")
        #expect(events(terminal) == [.key(KeyEvent(character: "q")), .key(KeyEvent(character: "j"))])
        #expect(terminal.takeStatusFence(), "the fence was dropped with the rest of what nobody typed")
        #expect(!terminal.takeStatusFence(), "taking it does not leave it behind")
        #expect(
            terminal.takeVolunteeredColorReplies().isEmpty,
            "the fence says nothing about a colour, so it is not one of the replies")
    }

    /// Why the fence is kept apart from the replies rather than among them:
    /// `TerminalColorQuery.parse` stops at a fence, so a fence in the middle of
    /// a drain's bytes would hide every reply behind it.
    @Test("A reply that lands behind a fence in one drain is still taken")
    func replyBehindTheFenceSurvives() {
        let (terminal, stage) = makeScriptedTerminal()
        let reply = TerminalColorLateReplyTests.reply(
            "11", TerminalColors.RGB(red: 40, green: 44, blue: 52))
        stage("\u{1B}[0n" + reply)
        _ = events(terminal)
        #expect(terminal.takeStatusFence())

        let sink = ColourSink()
        let refresher = TerminalColorRefresher(
            known: .unknown, environment: [:],
            publish: { sink.published.append($0) }, onChange: { sink.repaints += 1 })
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(sink.published.first?.background == TerminalColors.RGB(red: 40, green: 44, blue: 52))
    }
}

/// What a refresher published, and how many repaints it asked for.
@MainActor
private final class ColourSink {
    var published: [TerminalColors] = []
    var repaints = 0
}

/// A scene with nothing animating, so a frame's bytes are the frame's alone.
private struct FrameProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
        }
    }
}

/// The run loop's half: the request follows the frame it comes after, a thrown
/// away screen asks again, and the fence the parser kept reaches the requester.
///
/// Serialized because it drives whole frames through `AppState.shared`, as
/// `RunLoopFoldTests` does.
@MainActor
@Suite("The run loop asks after its first frame", .serialized)
struct TerminalColorRequestWiringTests {

    @Test("Under tmux the first frame is followed by the slots request, and later frames by nothing")
    func firstFrameIsFollowedByTheRequest() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(FrameProbeApp(), isTmux: true)

        loop.render()
        #expect(
            harness.terminal.writtenOutput.last == TerminalColorQuery.slotsRequest,
            "the request must follow the frame, not precede it")
        let afterFirstFrame = harness.terminal.writtenOutput.count

        loop.render()
        loop.render()
        #expect(
            harness.terminal.writtenOutput[afterFirstFrame...]
                .allSatisfy { $0 != TerminalColorQuery.slotsRequest },
            "asked again after a later frame")
    }

    @Test("Off tmux a frame asks the terminal for nothing")
    func nativeHostFramesAskNothing() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(FrameProbeApp(), isTmux: false)
        loop.render()
        loop.render()
        #expect(
            !harness.terminal.allOutput.contains("\u{1B}]4;"),
            "a frame asked for a slot on a host whose startup exchange already had them")
    }

    @Test("A screen thrown away asks the terminal everything again")
    func invalidatedScreenAsksAgain() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(FrameProbeApp(), isTmux: true)
        loop.render()
        loop.noteVolunteeredColorReplies([], sawStatusFence: true)

        loop.invalidateDiffCache()
        #expect(harness.terminal.writtenOutput.last == TerminalColorQuery.nativeRequest)
    }

    @Test("The fence the parser kept releases the request waiting behind it")
    func fenceFromTheDrainReleasesTheQueuedRequest() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(FrameProbeApp(), isTmux: true)
        loop.render()
        #expect(harness.terminal.writtenOutput.last == TerminalColorQuery.slotsRequest)

        loop.invalidateDiffCache()
        #expect(
            harness.terminal.writtenOutput.last == TerminalColorQuery.slotsRequest,
            "asked while the first frame's request was still outstanding")

        loop.noteVolunteeredColorReplies([], sawStatusFence: true)
        #expect(harness.terminal.writtenOutput.last == TerminalColorQuery.nativeRequest)
    }

    @Test("Off tmux a thrown-away screen on a terminal that has said nothing asks it nothing")
    func invalidatedScreenAsksNothingOnASilentHost() {
        TerminalColors.withCurrent(.unknown) {
            let harness = RenderLoopHarness()
            let loop = harness.loop(FrameProbeApp(), isTmux: false)
            loop.render()
            let afterFrame = harness.terminal.writtenOutput.count

            loop.invalidateDiffCache()
            #expect(
                harness.terminal.writtenOutput.count == afterFrame,
                "a host that has answered nothing was asked again anyway")
        }
    }
}

/// What the request is for: tmux's answer, which arrives long after the frame
/// that asked for it, publishes the sixteen slots and repaints the screen.
///
/// The parser and the refresher are 5a's; this drives them with the reply tmux
/// sends to the request the first frame now makes.
@MainActor
@Suite("tmux's late answer to the request after the first frame")
struct TerminalColorLateSlotsTests {

    typealias RGB = TerminalColors.RGB

    /// Apple Terminal 455.1's "Basic" sixteen, as a tmux client reported them
    /// on 2026-09-14 (Documentation/Terminal-compatibility.md), in slot order.
    private static let appleBasic = [
        RGB(red: 0, green: 0, blue: 0), RGB(red: 153, green: 0, blue: 0),
        RGB(red: 0, green: 166, blue: 0), RGB(red: 153, green: 153, blue: 0),
        RGB(red: 0, green: 0, blue: 179), RGB(red: 179, green: 0, blue: 179),
        RGB(red: 0, green: 166, blue: 179), RGB(red: 191, green: 191, blue: 191),
        RGB(red: 102, green: 102, blue: 102), RGB(red: 230, green: 0, blue: 0),
        RGB(red: 0, green: 217, blue: 0), RGB(red: 230, green: 230, blue: 0),
        RGB(red: 0, green: 0, blue: 255), RGB(red: 230, green: 0, blue: 230),
        RGB(red: 0, green: 230, blue: 230), RGB(red: 230, green: 230, blue: 230),
    ]

    /// What the startup exchange heard under tmux: the default pair from tmux's
    /// own record, and no slot.
    private static let tmuxPair = TerminalColors(
        foreground: RGB(red: 0, green: 0, blue: 0),
        background: RGB(red: 255, green: 255, blue: 255), prefersDark: false)

    @Test("The sixteen slots arrive a frame later, publish once over the pair, and repaint")
    func lateSlotsPublishAndRepaint() {
        let sink = RequestSink()
        let requester = TerminalColorRequester(isTmux: true, send: { sink.sent.append($0) })
        requester.noteFrameWritten()
        #expect(sink.sent == [TerminalColorQuery.slotsRequest], "the frame asked for the slots")

        let colours = ColourSink()
        let refresher = TerminalColorRefresher(
            known: Self.tmuxPair, environment: [:],
            publish: { colours.published.append($0) }, onChange: { colours.repaints += 1 })

        // tmux's client answers half a second later, among the keystrokes of
        // whoever kept typing while it did.
        let (terminal, stage) = makeScriptedTerminal()
        let replies = Self.appleBasic.enumerated()
            .map { TerminalColorLateReplyTests.reply("4;\($0.offset)", $0.element) }.joined()
        stage("j" + replies + "k")
        #expect(events(terminal) == [.key(KeyEvent(character: "j")), .key(KeyEvent(character: "k"))])

        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(
            colours.published == [
                TerminalColors(
                    foreground: Self.tmuxPair.foreground, background: Self.tmuxPair.background,
                    slots: TerminalColors.Slots(Self.appleBasic), prefersDark: false)
            ],
            "the table published once, over the pair the startup exchange knew")
        #expect(colours.repaints == 1)
    }
}

/// The window coming back: what the terminal is asked then, and who is skipped.
///
/// A terminal the user left is one they may have changed while they were gone —
/// a profile switched, a theme flipped, the whole window closed and another put
/// in its place. The hosts that would say so unprompted are the ones that report
/// their own theme; on the rest, focus-in is the moment worth asking at.
@MainActor
@Suite("Asking the terminal again when its window comes back")
struct TerminalColorFocusReQueryTests {

    private func makeRequester(isTmux: Bool) -> (TerminalColorRequester, RequestSink) {
        let sink = RequestSink()
        let requester = TerminalColorRequester(
            isTmux: isTmux, fenceTimeoutNanos: 5_000_000, send: { sink.sent.append($0) })
        return (requester, sink)
    }

    @Test("Focus coming back to a terminal that has answered asks it everything again")
    func answeringTerminalIsAskedOnFocusIn() {
        let (requester, sink) = makeRequester(isTmux: false)
        requester.focusRegained(terminalHasAnswered: true)
        #expect(
            sink.sent == [TerminalColorQuery.nativeRequest],
            "the pair as well as the slots: the theme may have changed while we were away")
    }

    @Test("A terminal that has never answered is left alone on focus-in")
    func silentTerminalIsLeftAloneOnFocusIn() {
        let (requester, sink) = makeRequester(isTmux: false)
        requester.focusRegained(terminalHasAnswered: false)
        requester.focusRegained(terminalHasAnswered: false)
        #expect(sink.sent.isEmpty, "a host that answers nothing was asked \(sink.sent.count) times")
    }

    @Test("Under tmux even a pane that has heard nothing is asked on focus-in")
    func tmuxPaneIsAskedOnFocusIn() {
        let (requester, sink) = makeRequester(isTmux: true)
        requester.focusRegained(terminalHasAnswered: false)
        #expect(sink.sent == [TerminalColorQuery.nativeRequest])
    }

    /// Alt-tabbing back and forth is the focus equivalent of a resize drag, and
    /// it coalesces the same way: one request outstanding, one waiting.
    @Test("Flicking focus back and forth is one request, and one resend when the fence lands")
    func focusBurstCoalesces() {
        let (requester, sink) = makeRequester(isTmux: false)
        for _ in 0..<4 { requester.focusRegained(terminalHasAnswered: true) }
        #expect(sink.sent.count == 1, "alt-tabbing asked \(sink.sent.count) times")

        requester.noteStatusFence()
        #expect(sink.sent.count == 2)

        requester.noteStatusFence()
        #expect(sink.sent.count == 2, "asked again with nothing left to ask for")
    }
}

/// The run loop's half of focus-in: the report the parser turns into a scene
/// phase is also what asks the terminal again.
///
/// Serialized with the suites above because `AppRunner` binds itself to
/// `AppState.shared`.
@MainActor
@Suite("A focus report asks the terminal again", .serialized)
struct TerminalColorFocusWiringTests {

    private func freshRunner() -> AppRunner<FrameProbeApp> {
        AppState.shared.didRender()
        _ = AppState.shared.consumePendingAnimationClocks()
        // `Terminal.init()` only reserves a buffer, so this touches no TTY.
        return AppRunner(app: FrameProbeApp())
    }

    private var timer: CursorTimer { CursorTimer(renderNotifier: AppState.shared) }

    @Test("Focus coming back asks the terminal what it paints now")
    func focusInAsksAgain() {
        let runner = freshRunner()
        let harness = RenderLoopHarness()
        let loop = harness.loop(FrameProbeApp(), isTmux: true)
        let timer = timer

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        let afterFocusOut = harness.terminal.writtenOutput.count

        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        #expect(
            harness.terminal.writtenOutput.count > afterFocusOut,
            "focus came back and the terminal was asked nothing")
        #expect(harness.terminal.writtenOutput.last == TerminalColorQuery.nativeRequest)
        AppState.shared.didRender()
    }

    @Test("Focus going away asks for nothing")
    func focusOutAsksNothing() {
        let runner = freshRunner()
        let harness = RenderLoopHarness()
        let loop = harness.loop(FrameProbeApp(), isTmux: true)

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        #expect(
            !harness.terminal.allOutput.contains("\u{1B}]11;?"),
            "the window we just left was asked what it paints")
        AppState.shared.didRender()
    }

    /// A terminal may report focus in as reporting is enabled, and the scene is
    /// already active then: the startup exchange has just asked, so asking again
    /// would be a second 170-byte request for nothing.
    @Test("A report of the focus the scene already has asks for nothing")
    func duplicateFocusInAsksNothing() {
        let runner = freshRunner()
        let harness = RenderLoopHarness()
        let loop = harness.loop(FrameProbeApp(), isTmux: true)

        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        #expect(harness.terminal.writtenOutput.isEmpty)
        AppState.shared.didRender()
    }

    @Test("Off tmux a terminal that has said nothing is asked nothing when focus comes back")
    func silentHostIsAskedNothingOnFocusIn() {
        TerminalColors.withCurrent(.unknown) {
            let runner = freshRunner()
            let harness = RenderLoopHarness()
            let loop = harness.loop(FrameProbeApp(), isTmux: false)
            let timer = timer

            runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
            let afterFocusOut = harness.terminal.writtenOutput.count

            runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
            #expect(
                harness.terminal.writtenOutput.count == afterFocusOut,
                "a host that has answered nothing was asked again anyway")
            AppState.shared.didRender()
        }
    }
}
