//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SteadyBreathCopiesOnUnmeasurableColourTests.swift
//
//  The focus breaths that do not go through `Color.breathEnds(dimmedTo:over:)`: a
//  switch's track, a tab's active label, a navigation crumb, a scroll view's bar, a
//  list's "N more" line and a swatch grid's cursor mark. Each breathes between two
//  colours of its own, and where one of them has no RGB the cycle's blend snaps
//  (Opacity as composition §75), so the breath was a hard blink between its two ends.
//  Held at the bright end instead, as `breathEnds` holds its own (§79).
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
private struct CopiesInkAccentPalette: Palette {
    let id = "steady-breath-copies-terminal-ink-accent"
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
private struct CopiesPagePalette: Palette {
    let id = "steady-breath-copies-terminal-page"
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

/// An RGB page and ink whose accent is a terminal slot, which has no RGB until the
/// terminal reports its sixteen.
private struct CopiesSlotAccentPalette: Palette {
    let id = "steady-breath-copies-slot-accent"
    let name = "Slot accent"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color.ansi(.blue)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@MainActor
@Suite("A focus breath between two colours, one with no RGB, holds still")
struct SteadyBreathCopiesOnUnmeasurableColourTests {

    /// The breaths that pick their two ends themselves.
    enum Copy: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// `SwitchTrackBreath.ends`, on: the track dimmed over the page, to the accent.
        case switchOn
        /// `SwitchTrackBreath.ends`, off: the off track dimmed, to it lifted.
        case switchOff
        /// `ActiveChipCycle`: the active tab's resting label, to the accent.
        case tabChip
        /// `_NavigationCrumbButtonStyle`: the resting rung, to the accent.
        case crumb
        /// `ScrollbarPulse`: the separated accent, to its lift.
        case scrollbar
        /// `scrollIndicatorBreath`: the tertiary tier, to the accent.
        case scrollIndicator
        /// `_SwatchGridCore.markEnds`: the swatch, to the ink that reads on it.
        case swatchMark
        /// `_Color256GridCore.cursorMarkEnds`: the cursor on slot 4, to the ink that reads
        /// on it. A slot has no RGB until the terminal reports its sixteen.
        case color256Mark

        var testDescription: String { rawValue }

        @MainActor @ViewBuilder
        func view(_ fixture: Fixture) -> some View {
            switch self {
            case .switchOn:
                Toggle("On", isOn: .constant(true)).toggleStyle(.switch)
            case .switchOff:
                Toggle("Off", isOn: .constant(false)).toggleStyle(.switch)
            case .tabChip:
                TabView(selection: .constant(0)) {
                    Tab("One", value: 0) { Text("first") }
                    Tab("Two", value: 1) { Text("second") }
                }
                .tabViewStyle(.bordered)
            case .crumb:
                Button("Library") {}.buttonStyle(_NavigationCrumbButtonStyle())
            case .scrollbar:
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(0..<30, id: \.self) { Text("row \($0)") }
                    }
                }
                .scrollIndicators(.visible)
            case .scrollIndicator:
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(0..<30, id: \.self) { Text("row \($0)") }
                    }
                }
                .scrollIndicators(.visible)
                .scrollIndicatorStyle(.text)
            case .swatchMark:
                _SwatchGridCore(
                    entries: [fixture.unmeasuredSwatch, .rgb(200, 40, 40)],
                    columns: 2,
                    selection: .constant(fixture.unmeasuredSwatch))
            case .color256Mark:
                _Color256GridCore(selection: .constant(.palette(4)), showNumbers: false)
            }
        }

        /// Whether one of this breath's two ends has no RGB under `fixture` while the
        /// terminal has reported nothing. A breath between two RGB inks drawn over a
        /// page with none is a measured breath: the page is not blended into either end.
        func hasAnUnmeasuredEnd(under fixture: Fixture) -> Bool {
            switch (self, fixture) {
            // The on track is the accent, dimmed over the page.
            case (.switchOn, _): true
            // The swatch under the cursor has no RGB, whatever the palette: the fixture's
            // unmeasured colour, or slot 4.
            case (.swatchMark, _), (.color256Mark, _): true
            // The off track dims over the page, and lifts toward the foreground: both RGB
            // unless the page has none.
            case (.switchOff, .page): true
            case (.switchOff, .accent), (.switchOff, .ansiAccent): false
            // The accent is one end. A slot accent has no RGB exactly where the terminal's
            // foreground has none.
            case (.tabChip, .accent), (.crumb, .accent), (.scrollbar, .accent), (.scrollIndicator, .accent),
                (.tabChip, .ansiAccent), (.crumb, .ansiAccent), (.scrollbar, .ansiAccent),
                (.scrollIndicator, .ansiAccent):
                true
            case (.tabChip, .page), (.crumb, .page), (.scrollbar, .page), (.scrollIndicator, .page): false
            }
        }
    }

    /// Which colour has no RGB.
    enum Fixture: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// The accent is the terminal's foreground.
        case accent
        /// The page is the terminal's background.
        case page
        /// The accent is a terminal slot, `.ansi(.blue)`.
        case ansiAccent

        var testDescription: String { rawValue }

        var palette: any Palette {
            switch self {
            case .accent: CopiesInkAccentPalette()
            case .page: CopiesPagePalette()
            case .ansiAccent: CopiesSlotAccentPalette()
            }
        }

        /// The swatch under a swatch grid's cursor: a colour with no RGB until the
        /// terminal reports it, whatever the palette. The terminal's own foreground, or
        /// a slot beside a slot accent.
        var unmeasuredSwatch: Color {
            self == .ansiAccent ? .ansi(.blue) : Color(value: .terminalForeground)
        }
    }

    /// One Dark's pair, as the carried-colour tests use, and Apple Terminal "Basic"'s
    /// sixteen slots, so a slot measures too.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52),
        slots: TerminalColors.Slots(UnreportedANSISlotTests.appleBasic))

    /// The middle of each 50 ms frame of the focus breath, over two cycles and more.
    private static let instants: [UInt64] = (0..<32).map { UInt64($0) * 50_000_000 + 25_000_000 }

    /// `copy` under `fixture` in 24-bit colour, at `nanos` on the clocks, and how often its
    /// second pass read a clock. Two passes, counted on the second: a control takes the
    /// focus during its first.
    ///
    /// - Parameter still: Drawn with the focus emphasis still, which is the bright end
    ///   of every breath.
    private func render(
        _ copy: Copy, _ fixture: Fixture, atNanos nanos: UInt64 = 25_000_000, still: Bool = false
    ) -> (buffer: FrameBuffer, clockReads: Int) {
        let tracker = VolatileReadTracker()
        let timer = CursorTimer(renderNotifier: AppState())
        // The cursor clock counts from the first instant its timer sees, so the zero is
        // shown first: seen alone, `nanos` would be the zero, and every render step 0.
        timer.observe(nowNanos: 0)
        timer.observe(nowNanos: nanos)
        // Wide and tall enough for the 256-colour grid, whose swatches do not shrink.
        let context = makeRenderContext(width: 80, height: 24) { environment, _ in
            environment.palette = fixture.palette
            environment.cursorTimer = timer
            environment.frameNowNanos = Int64(nanos)
            environment.volatileReadTracker = tracker
        }
        let view = copy.view(fixture).selectionIndicatorStyle(still ? .none : .pulse)
        return ColorDepth.withCurrent(.truecolor) {
            _ = renderToBuffer(view, context: context)
            let before = tracker.reads
            let buffer = renderToBuffer(view, context: context)
            return (buffer, tracker.reads - before)
        }
    }

    /// The instants whose frame is not the bright end.
    private func instantsOffTheBrightEnd(_ copy: Copy, _ fixture: Fixture) -> [UInt64] {
        let bright = render(copy, fixture, still: true).buffer.lines
        return Self.instants.filter {
            !paintsIdentically(render(copy, fixture, atNanos: $0).buffer.lines, bright)
        }
    }

    @Test("With an end that has no RGB, a focused breath leaves no run and reads no clock",
        arguments: Copy.allCases, Fixture.allCases)
    func leavesNoRun(_ copy: Copy, _ fixture: Fixture) {
        guard copy.hasAnUnmeasuredEnd(under: fixture) else { return }
        TerminalColors.withCurrent(.unknown) {
            let drawn = render(copy, fixture)
            #expect(drawn.buffer.animatedCells.isEmpty, "\(copy), \(fixture): \(drawn.buffer.animatedCells)")
            #expect(drawn.clockReads == 0, "\(copy), \(fixture)")
        }
    }

    @Test("With an end that has no RGB, a focused breath draws its bright end at every step",
        arguments: Copy.allCases, Fixture.allCases)
    func drawsTheBrightEndAtEveryStep(_ copy: Copy, _ fixture: Fixture) {
        guard copy.hasAnUnmeasuredEnd(under: fixture) else { return }
        TerminalColors.withCurrent(.unknown) {
            let off = instantsOffTheBrightEnd(copy, fixture)
            #expect(off.isEmpty, "\(copy), \(fixture): off the bright end at \(off.map { $0 / 1_000_000 }) ms")
        }
    }

    /// Keyed on the two ends, not on the palette: an RGB breath drawn over a page with no
    /// RGB, or beside an accent with none, still breathes.
    @Test("With two RGB ends, the breath still moves while the terminal has reported nothing",
        arguments: Copy.allCases, Fixture.allCases)
    func rgbEndsStillBreathe(_ copy: Copy, _ fixture: Fixture) {
        guard !copy.hasAnUnmeasuredEnd(under: fixture) else { return }
        TerminalColors.withCurrent(.unknown) {
            let runs = render(copy, fixture).buffer.animatedCells
            #expect(!runs.isEmpty && runs.allSatisfy(\.isAnimating), "\(copy), \(fixture): \(runs)")
            #expect(
                !instantsOffTheBrightEnd(copy, fixture).isEmpty,
                "\(copy), \(fixture): every instant drew the bright end")
        }
    }

    /// The premise the tests above need to be able to fail: the same breath moves once
    /// the terminal has reported its colours.
    @Test("Once the terminal reports its colours, the same breath moves",
        arguments: Copy.allCases, Fixture.allCases)
    func reportedColoursBreathe(_ copy: Copy, _ fixture: Fixture) {
        TerminalColors.withCurrent(Self.reported) {
            let runs = render(copy, fixture).buffer.animatedCells
            #expect(!runs.isEmpty && runs.allSatisfy(\.isAnimating), "\(copy), \(fixture): \(runs)")
            #expect(
                !instantsOffTheBrightEnd(copy, fixture).isEmpty,
                "\(copy), \(fixture): every instant drew the bright end")
        }
    }
}
