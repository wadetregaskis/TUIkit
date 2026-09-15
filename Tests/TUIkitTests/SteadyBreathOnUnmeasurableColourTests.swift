//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SteadyBreathOnUnmeasurableColourTests.swift
//
//  A focus breath whose colour, or the ground under it, has no RGB. A breath's dim end
//  is a composite toward its ground, and a composite with such a side snaps to one end
//  (Opacity as composition §75): the dim end was the ground and the bright end the
//  colour. So a focused control's breath was a hard blink between the page and the
//  accent, handed to the run loop as a run that kept a clock ticking. On such a colour
//  the breath is its bright end, held still: no run, and no tick.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// An RGB page and ink whose accent is the terminal's own foreground, which has no RGB
/// until the terminal reports it.
private struct TerminalInkAccentPalette: Palette {
    let id = "steady-breath-terminal-ink-accent"
    let name = "Terminal ink accent"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color(value: .terminalForeground)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// The terminal's own page, which has no RGB until the terminal reports it, with an RGB
/// ink and accent.
private struct TerminalPagePalette: Palette {
    let id = "steady-breath-terminal-page"
    let name = "Terminal page"
    let background = Color(value: .terminalBackground)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// One control under one of the palettes above, as a whole app, for the run loop.
private struct SteadyBreathApp: App {
    var control = SteadyBreathOnUnmeasurableColourTests.Control.button
    var fixture = SteadyBreathOnUnmeasurableColourTests.Fixture.accent

    init() {}

    init(
        control: SteadyBreathOnUnmeasurableColourTests.Control,
        fixture: SteadyBreathOnUnmeasurableColourTests.Fixture
    ) {
        self.control = control
        self.fixture = fixture
    }

    var body: some Scene {
        WindowGroup { control.view.palette(fixture.palette) }
    }
}

@MainActor
@Suite("A focus breath over a colour with no RGB holds still")
struct SteadyBreathOnUnmeasurableColourTests {

    /// The controls whose focus breathes: a list's cursor row is a fill, the rest are
    /// marks, caps and a caret.
    enum Control: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case list, button, plainButton, toggle, radioButton, stepper, slider, textField

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        var view: some View {
            switch self {
            case .list:
                List(selection: .constant(Set([0]))) {
                    ForEach(0..<3, id: \.self) { Text("row \($0)") }
                }
            case .button:
                Button("Save") {}
            case .plainButton:
                Button("Save") {}.buttonStyle(.plain)
            case .toggle:
                Toggle("On", isOn: .constant(true))
            case .radioButton:
                RadioButtonGroup(selection: .constant("a")) {
                    RadioButtonItem("a", "Alpha")
                    RadioButtonItem("b", "Bravo")
                }
            case .stepper:
                Stepper("Count", value: .constant(3), in: 0...10)
            case .slider:
                Slider(value: .constant(0.5), in: 0...1)
            case .textField:
                TextField("Name", text: .constant("Ada"))
            }
        }
    }

    /// Which side of the breath has no RGB.
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// The colour that breathes: the accent is the terminal's foreground.
        case accent
        /// The ground it breathes over: the page is the terminal's background.
        case page

        var testDescription: String { rawValue }

        var palette: any Palette {
            switch self {
            case .accent: TerminalInkAccentPalette()
            case .page: TerminalPagePalette()
            }
        }
    }

    /// One Dark's pair, as the carried-colour tests use.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    /// The middle of each 50 ms frame of the focus breath, over two cycles and more,
    /// so a caret's slower pulse is covered too.
    private static let instants: [UInt64] = (0..<32).map { UInt64($0) * 50_000_000 + 25_000_000 }

    /// `control` under `fixture` in 24-bit colour, at `nanos` on the clocks, and how often
    /// its second pass read a clock. Two passes, counted on the second, as
    /// `IdleClockReadTests` does: a control takes the focus during its first.
    ///
    /// - Parameter still: Drawn with no animation at all, the focus emphasis and the
    ///   caret alike, which is the bright end of every breath.
    private func render(
        _ control: Control, _ fixture: Fixture, atNanos nanos: UInt64 = 25_000_000,
        still: Bool = false
    ) -> (buffer: FrameBuffer, clockReads: Int) {
        let tracker = VolatileReadTracker()
        let timer = CursorTimer(renderNotifier: AppState())
        // The cursor clock counts from the first instant its timer sees, so the zero is
        // shown first: seen alone, `nanos` would be the zero, and every render step 0.
        timer.observe(nowNanos: 0)
        timer.observe(nowNanos: nanos)
        let context = makeRenderContext(width: 40, height: 8) { environment, _ in
            environment.palette = fixture.palette
            environment.cursorTimer = timer
            environment.frameNowNanos = Int64(nanos)
            environment.volatileReadTracker = tracker
        }
        let view = control.view
            .selectionIndicatorStyle(still ? .none : .pulse)
            .textCursor(TextCursorStyle(shape: .block, animation: still ? .none : .pulse))
        return ColorDepth.withCurrent(.truecolor) {
            _ = renderToBuffer(view, context: context)
            let before = tracker.reads
            let buffer = renderToBuffer(view, context: context)
            return (buffer, tracker.reads - before)
        }
    }

    /// Two frames of `app` through the run loop, and what the second asked of it.
    private func activity(of app: SteadyBreathApp) -> RenderActivity {
        let harness = RenderLoopHarness()
        let loop = harness.loop(app)
        let timer = CursorTimer(renderNotifier: harness.appState)
        timer.beginFrameReadTracking()
        _ = loop.render(cursorTimer: timer)
        timer.beginFrameReadTracking()
        return loop.render(cursorTimer: timer)
    }

    @Test("Focused over a colour with no RGB, a control leaves no run and reads no clock",
        arguments: Control.allCases, Fixture.allCases)
    func leavesNoRun(_ control: Control, _ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let drawn = render(control, fixture)
            #expect(
                drawn.buffer.animatedCells.isEmpty,
                "\(control), \(fixture): \(drawn.buffer.animatedCells)")
            #expect(drawn.clockReads == 0, "\(control), \(fixture)")
        }
    }

    @Test("Focused over a colour with no RGB, a control draws its bright end at every step",
        arguments: Control.allCases, Fixture.allCases)
    func drawsTheBrightEndAtEveryStep(_ control: Control, _ fixture: Fixture) {
        TerminalColors.withCurrent(.unknown) {
            let bright = render(control, fixture, still: true).buffer.lines
            let off = Self.instants.filter {
                !paintsIdentically(render(control, fixture, atNanos: $0).buffer.lines, bright)
            }
            #expect(
                off.isEmpty,
                "\(control), \(fixture): off the bright end at \(off.map { $0 / 1_000_000 }) ms")
        }
    }

    /// Keyed on what measures, not on the palette: the same two palettes breathe once the
    /// terminal has reported its colours. Also what makes the two tests above able to
    /// fail: these are the runs they find none of.
    @Test("Once the terminal reports its colours, the same control breathes",
        arguments: Control.allCases, Fixture.allCases)
    func reportedColoursBreathe(_ control: Control, _ fixture: Fixture) {
        TerminalColors.withCurrent(Self.reported) {
            let runs = render(control, fixture).buffer.animatedCells
            #expect(!runs.isEmpty && runs.allSatisfy(\.isAnimating), "\(control), \(fixture): \(runs)")
            // The clock moves the drawn frame off the bright end somewhere in the cycle.
            let bright = render(control, fixture, still: true).buffer.lines
            #expect(
                Self.instants.contains {
                    !paintsIdentically(render(control, fixture, atNanos: $0).buffer.lines, bright)
                },
                "\(control), \(fixture): every instant drew the bright end")
        }
    }

    @Test("The run loop is asked for no tick", arguments: Control.allCases)
    func loopHasNothingToWakeFor(_ control: Control) {
        TerminalColors.withCurrent(.unknown) {
            for fixture in Fixture.allCases {
                let activity = activity(of: SteadyBreathApp(control: control, fixture: fixture))
                #expect(activity.animatedClocks.isEmpty, "\(control), \(fixture)")
                #expect(!activity.usesPulse && !activity.usesCursor, "\(control), \(fixture)")
            }
        }
        TerminalColors.withCurrent(Self.reported) {
            let activity = activity(of: SteadyBreathApp(control: control, fixture: .accent))
            #expect(!activity.animatedClocks.isEmpty, "the premise: \(control) breathes once reported")
        }
    }
}
