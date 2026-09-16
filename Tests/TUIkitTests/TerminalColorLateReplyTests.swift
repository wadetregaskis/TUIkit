//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColorLateReplyTests.swift
//
//  Colour answers that arrive after the startup exchange has closed: too late for
//  its deadline (tmux held OSC 4 for half a second, measured), or volunteered by a
//  terminal whose theme changed. They arrive on stdin exactly as a keystroke does,
//  and the input parser used to drop them — it reads the keyboard, and none of
//  this is the keyboard.
//
//  The parser now siphons the ones that say something about the terminal's
//  colours (`Terminal.takeVolunteeredColorReplies`), and `TerminalColorRefresher`
//  publishes what they add to what was already known and asks for a repaint. The
//  wiring into the run loop is `RenderLoop.noteVolunteeredColorReplies`, called
//  once per drain.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitImage
@testable import TUIkitStyling
@testable import TUIkitView

@MainActor
@Suite("Colour answers that arrive after the startup exchange")
struct TerminalColorLateReplyTests {

    typealias RGB = TerminalColors.RGB

    /// Ghostty 1.3.1's default configuration, as it answered on 2026-09-14
    /// (Documentation/Terminal-compatibility.md).
    static let ghosttyBackground = RGB(red: 40, green: 44, blue: 52)
    static let ghosttyForeground = RGB(red: 255, green: 255, blue: 255)
    static let ghosttySlots = [
        RGB(red: 29, green: 31, blue: 33), RGB(red: 204, green: 102, blue: 102),
        RGB(red: 181, green: 189, blue: 104), RGB(red: 240, green: 198, blue: 116),
        RGB(red: 129, green: 162, blue: 190), RGB(red: 178, green: 148, blue: 187),
        RGB(red: 138, green: 190, blue: 183), RGB(red: 197, green: 200, blue: 198),
        RGB(red: 102, green: 102, blue: 102), RGB(red: 213, green: 78, blue: 83),
        RGB(red: 185, green: 202, blue: 74), RGB(red: 231, green: 197, blue: 71),
        RGB(red: 122, green: 166, blue: 218), RGB(red: 195, green: 151, blue: 216),
        RGB(red: 112, green: 192, blue: 177), RGB(red: 234, green: 234, blue: 234),
    ]

    /// An XParseColor spec as the measured hosts spelled it: `rgb:`, each channel
    /// as four hex digits, its byte repeated.
    static func spec(_ rgb: RGB) -> String {
        let channels = [rgb.red, rgb.green, rgb.blue].map { channel in
            let digits = String(channel, radix: 16)
            let byte = digits.count == 1 ? "0" + digits : digits
            return byte + byte
        }
        return "rgb:" + channels.joined(separator: "/")
    }

    /// One OSC reply, ended in ST as Ghostty mirrors the query's terminator.
    static func reply(_ code: String, _ rgb: RGB) -> String {
        "\u{1B}]\(code);\(spec(rgb))\u{1B}\\"
    }

    static func slotReplies(_ slots: ArraySlice<RGB>) -> String {
        slots.enumerated().map { reply("4;\($0.offset + slots.startIndex)", $0.element) }.joined()
    }

    // MARK: - A scripted terminal and a refresher whose publications are recorded

    /// Reference box so the read closure and the test share one byte queue.
    private final class ByteBox { var bytes: [UInt8] = [] }

    /// A terminal whose byte source hands over whatever the test has staged, as
    /// `TerminalInputParsingTests` drives the parser: no TTY, and the split
    /// between reads is the test's to choose.
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

    /// Everything `readEvent()` delivers while the buffer holds complete events.
    private func events(_ terminal: Terminal, pumps: Int = 8) -> [TerminalInput] {
        (0..<pumps).compactMap { _ in terminal.readEvent() }
    }

    /// What a refresher published, and how many repaints it asked for.
    private final class Sink {
        var published: [TerminalColors] = []
        var repaints = 0
    }

    /// A refresher that records rather than assigning the process-wide colours,
    /// which every other suite rendering beside this one would see.
    private func makeRefresher(
        known: TerminalColors = .unknown, environment: [String: String] = [:]
    ) -> (TerminalColorRefresher, Sink) {
        let sink = Sink()
        let refresher = TerminalColorRefresher(
            known: known, environment: environment,
            publish: { sink.published.append($0) },
            onChange: { sink.repaints += 1 })
        return (refresher, sink)
    }

    // MARK: - Told from the keyboard

    @Test("A colour answer that lands between keystrokes leaves both keystrokes alone")
    func replyAmongKeystrokes() {
        let (terminal, stage) = makeTerminal()
        stage("q" + Self.reply("11", Self.ghosttyBackground) + "j")
        #expect(events(terminal) == [.key(KeyEvent(character: "q")), .key(KeyEvent(character: "j"))])

        let (refresher, sink) = makeRefresher()
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(sink.published == [TerminalColors(background: Self.ghosttyBackground, prefersDark: true)])
        #expect(sink.repaints == 1)
    }

    @Test("A reply split across two reads is taken whole once its tail arrives")
    func splitReplyIsTakenWhole() {
        let (terminal, stage) = makeTerminal()
        let whole = Self.reply("11", Self.ghosttyBackground)
        let head = String(whole.prefix(9))
        stage("q" + head)
        // The `q`, and then nothing: the parser holds the unterminated reply
        // rather than typing its bytes out.
        #expect(events(terminal, pumps: 2) == [.key(KeyEvent(character: "q"))])
        #expect(terminal.takeVolunteeredColorReplies().isEmpty, "half a reply is not an answer")

        stage(String(whole.dropFirst(9)) + "j")
        #expect(events(terminal, pumps: 4) == [.key(KeyEvent(character: "j"))])
        let (refresher, sink) = makeRefresher()
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(sink.published.first?.background == Self.ghosttyBackground)
    }

    @Test("An appearance report is taken, not typed")
    func appearanceReportIsTaken() {
        let (terminal, stage) = makeTerminal()
        stage("\u{1B}[?997;1n" + "j")
        #expect(events(terminal) == [.key(KeyEvent(character: "j"))])

        let (refresher, sink) = makeRefresher()
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(sink.published == [TerminalColors(prefersDark: true)])
    }

    @Test("A graphics acknowledgement is not a colour answer, and is dropped as before")
    func graphicsAcknowledgementIsNotTaken() {
        let (terminal, stage) = makeTerminal()
        stage("\u{1B}_Gi=7;OK\u{1B}\\" + "j")
        #expect(events(terminal) == [.key(KeyEvent(character: "j"))])
        #expect(terminal.takeVolunteeredColorReplies().isEmpty)
    }

    // MARK: - What a late answer adds to what was known

    @Test("Fifteen of sixteen slots publish nothing; the sixteenth, a drain later, publishes once")
    func slotsSplitAcrossDrainsPublishOnce() {
        let (terminal, stage) = makeTerminal()
        let (refresher, sink) = makeRefresher()

        stage(Self.slotReplies(Self.ghosttySlots[0..<15]))
        _ = events(terminal)
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(sink.published.isEmpty, "fifteen slots cannot say what the sixteenth paints")

        stage(Self.slotReplies(Self.ghosttySlots[15..<16]))
        _ = events(terminal)
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())
        #expect(sink.published.count == 1, "the whole table published once: \(sink.published)")
        #expect(sink.published.first?.slots == TerminalColors.Slots(Self.ghosttySlots))
        #expect(sink.repaints == 1)
    }

    @Test("A late answer keeps what the startup exchange already knew")
    func lateAnswerKeepsWhatWasKnown() {
        let known = TerminalColors(
            foreground: Self.ghosttyForeground, background: Self.ghosttyBackground, prefersDark: true)
        let (terminal, stage) = makeTerminal()
        let (refresher, sink) = makeRefresher(known: known)

        stage(Self.slotReplies(Self.ghosttySlots[0..<16]))
        _ = events(terminal)
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())

        #expect(
            sink.published == [
                TerminalColors(
                    foreground: Self.ghosttyForeground, background: Self.ghosttyBackground,
                    slots: TerminalColors.Slots(Self.ghosttySlots), prefersDark: true)
            ])
    }

    @Test("A reply repeating the colours already in force publishes nothing and repaints nothing")
    func unchangedColoursPublishNothing() {
        let known = TerminalColors(background: Self.ghosttyBackground, prefersDark: true)
        let (terminal, stage) = makeTerminal()
        let (refresher, sink) = makeRefresher(known: known)

        stage(Self.reply("11", Self.ghosttyBackground))
        _ = events(terminal)
        refresher.noteReplies(terminal.takeVolunteeredColorReplies())

        #expect(sink.published.isEmpty)
        #expect(sink.repaints == 0, "a repaint nobody needs")
    }
}

/// A scene with nothing animating, so the only thing that can change a frame's
/// bytes here is the report.
private struct LateReplyProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
        }
    }
}

/// The run loop's half of the wiring: it owns the refresher, and a report that
/// changes the record repaints the whole screen rather than waiting for a
/// keypress.
///
/// Serialized because it assigns the process-wide colours and reads
/// `AppState.shared`, which `AppRunner` binds itself to — the same reason
/// `RunLoopFoldTests` is.
@MainActor
@Suite("The run loop applies what the parser siphoned", .serialized)
struct TerminalColorReplyWiringTests {

    @Test("A reply handed to the loop is published, and the next frame is a full repaint")
    func loopPublishesAndRepaints() {
        let saved = TerminalColors.current
        defer { TerminalColors.current = saved }
        AppState.shared.didRender()

        let harness = RenderLoopHarness()
        let loop = harness.loop(LateReplyProbeApp())
        loop.render()
        let firstFrame = harness.terminal.writtenOutput.joined().count
        loop.render()
        let unchangedFrame = harness.terminal.writtenOutput.joined().count - firstFrame
        #expect(
            unchangedFrame < firstFrame,
            "the fixture: an unchanged frame writes less than the first: \(unchangedFrame) of \(firstFrame)")

        let reply = TerminalColorLateReplyTests.reply("11", TerminalColorLateReplyTests.ghosttyBackground)
        loop.noteVolunteeredColorReplies(Array(reply.utf8), sawStatusFence: false)
        #expect(TerminalColors.current.background == TerminalColorLateReplyTests.ghosttyBackground)
        #expect(AppState.shared.needsRender, "the loop was not asked for a frame")

        let beforeRepaint = harness.terminal.writtenOutput.joined().count
        loop.render()
        let repaint = harness.terminal.writtenOutput.joined().count - beforeRepaint
        #expect(
            repaint > unchangedFrame,
            "the screen was not invalidated: \(repaint) bytes, where an unchanged frame writes \(unchangedFrame)")
    }
}

/// The one test that assigns the PROCESS-wide colours, so it is serialized, as
/// `TerminalColorsProcessTests` is. It restores them at once: what is kept from
/// the terminal's colours is dropped by the assignment, and every suite rendering
/// beside this one reads the same record.
@MainActor
@Suite("A late report reaches what was kept from the colours before it", .serialized)
struct TerminalColorLatePublicationTests {

    typealias RGB = TerminalColors.RGB

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> RGB {
        RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them
    /// on 2026-09-14 (Documentation/Terminal-compatibility.md), in slot order.
    private static let appleBasic = [
        rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
        rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
        rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
        rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
    ]

    /// (220, 0, 0) is nearer xterm's red (205, 0, 0) than its bright red, and nearer
    /// Apple Terminal "Basic"'s bright red (230, 0, 0) than its red (153, 0, 0).
    private static let pixel = RGBA(r: 220, g: 0, b: 0)

    @Test("Publishing a late report drops a memoised buffer and the sixteen matched before it")
    func latePublicationReachesWhatWasKept() throws {
        let saved = TerminalColors.current
        defer { TerminalColors.current = saved }

        let cache = RenderCache()
        cache.store(
            identity: ViewIdentity(path: "late-reply"), view: 1, buffer: FrameBuffer(text: "a"),
            contextWidth: 80, contextHeight: 24)
        #expect(
            ASCIIPalette.ansi16.nearestIndex(to: Self.pixel) == 1,
            "the fixture: an unreported terminal matches xterm's table")

        nonisolated(unsafe) var repaints = 0
        let refresher = TerminalColorRefresher(
            known: .unknown, environment: [:], onChange: { repaints += 1 })
        let replies = Self.appleBasic.enumerated()
            .map { TerminalColorLateReplyTests.reply("4;\($0.offset)", $0.element) }.joined()
        refresher.noteReplies(Array(replies.utf8))

        #expect(TerminalColors.current.slots == TerminalColors.Slots(Self.appleBasic))
        #expect(repaints == 1)
        cache.beginRenderPass()
        #expect(cache.isEmpty, "a buffer rendered under the colours before the report was kept")
        #expect(
            ASCIIPalette.ansi16.nearestIndex(to: Self.pixel) == 9,
            "the sixteen-colour palette still matched against the table before the report")
    }
}
