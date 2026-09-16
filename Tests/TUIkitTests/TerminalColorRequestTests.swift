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
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitStyling

/// The rule for when a request goes out, without a terminal: what
/// `TerminalColorRequester` decides, and what it sends when it decides to ask.
@MainActor
@Suite("Asking the terminal for its colours again")
struct TerminalColorRequesterTests {

    /// A requester whose requests are recorded rather than written to a
    /// terminal.
    private final class Sink {
        var sent: [String] = []
    }

    private func makeRequester(isTmux: Bool) -> (TerminalColorRequester, Sink) {
        let sink = Sink()
        let requester = TerminalColorRequester(isTmux: isTmux, send: { sink.sent.append($0) })
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

/// A scene with nothing animating, so a frame's bytes are the frame's alone.
private struct FrameProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
        }
    }
}

/// The run loop's half: the request follows the frame it comes after, and it is
/// the terminal's own bytes, written once.
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

    private final class ByteBox { var bytes: [UInt8] = [] }

    private func makeTerminal() -> (Terminal, (String) -> Void) {
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

    /// What the refresher published, and how many repaints it asked for.
    private final class Sink {
        var published: [TerminalColors] = []
        var repaints = 0
    }

    @Test("The sixteen slots arrive a frame later, publish once over the pair, and repaint")
    func lateSlotsPublishAndRepaint() {
        var asked: [String] = []
        let requester = TerminalColorRequester(isTmux: true, send: { asked.append($0) })
        requester.noteFrameWritten()
        #expect(asked == [TerminalColorQuery.slotsRequest], "the frame asked for the slots")

        let sink = Sink()
        let refresher = TerminalColorRefresher(
            known: Self.tmuxPair, environment: [:],
            publish: { sink.published.append($0) }, onChange: { sink.repaints += 1 })

        // tmux's client answers half a second later, among the keystrokes of
        // whoever kept typing while it did.
        let (terminal, stage) = makeTerminal()
        let replies = Self.appleBasic.enumerated()
            .map { TerminalColorLateReplyTests.reply("4;\($0.offset)", $0.element) }.joined()
        stage("j" + replies + "k")
        let typed = (0..<8).compactMap { _ in terminal.readEvent() }
        #expect(typed == [.key(KeyEvent(character: "j")), .key(KeyEvent(character: "k"))])

        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(
            sink.published == [
                TerminalColors(
                    foreground: Self.tmuxPair.foreground, background: Self.tmuxPair.background,
                    slots: TerminalColors.Slots(Self.appleBasic), prefersDark: false)
            ],
            "the table published once, over the pair the startup exchange knew")
        #expect(sink.repaints == 1)
    }
}
