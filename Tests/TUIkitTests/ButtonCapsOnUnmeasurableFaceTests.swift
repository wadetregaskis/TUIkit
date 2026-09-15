//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonCapsOnUnmeasurableFaceTests.swift
//
//  A standard button's and a menu picker's `▐ … ▌` end caps on a face the terminal
//  decides. An unfocused cap is drawn in the control's face. Over a page with no RGB
//  that face is the page itself (Opacity as composition, rule 9), and the foreground
//  slot has no spelling for an unreported page: it emits 39, so the caps came out as
//  two half-blocks in the terminal's foreground, by accident. A focused cap breathed
//  from that face to the accent, so half its frames were the same accident. On such a
//  face the caps now rest in the tertiary tier and, focused, hold the accent.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// The terminal's page and ink, stated as roles, with an RGB accent and tertiary tier.
private struct TerminalPagePalette: Palette {
    let id = "terminal-page"
    let name = "Terminal page"
    let background = Color(value: .terminalBackground)
    let foreground = Color(value: .terminalForeground)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// An RGB page whose accent is the terminal's default, which never has RGB: the face
/// is the page, and the colour it would be tinted with cannot be measured.
private struct DefaultAccentPalette: Palette {
    let id = "default-accent"
    let name = "Default accent"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color.default
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@MainActor
@Suite("A button's end caps on a face the terminal decides")
struct ButtonCapsOnUnmeasurableFaceTests {

    /// The three places `ButtonCapCycle` draws caps.
    enum Control: CaseIterable, Sendable {
        case stringLabel, viewLabel, picker
    }

    /// One Dark's pair, as the carried-colour tests use.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    @ViewBuilder
    private func view(_ control: Control) -> some View {
        switch control {
        case .stringLabel:
            Button("Save") {}
        case .viewLabel:
            Button {} label: { Text("Save") }
        case .picker:
            Picker("Fruit", selection: .constant("a")) {
                Text("Apple").tag("a")
                Text("Banana").tag("b")
            }
        }
    }

    /// `control` drawn in 24-bit colour under `palette`; unless `focused`, a sentinel
    /// takes the focus first.
    private func render(
        _ control: Control, _ palette: some Palette, focused: Bool, disabled: Bool = false
    ) -> FrameBuffer {
        let context = makeRenderContext(width: 40, height: 3) { environment, _ in
            environment.palette = palette
        }
        if !focused {
            context.environment.focusManager!.register(FocusSentinel())
        }
        return ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(view(control).disabled(disabled), context: context)
        }
    }

    /// The SGR state each end cap of `line` is drawn in, in row order.
    private func capStates(_ line: String) -> [SGRState] {
        var state = SGRState()
        var caps: [SGRState] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, _):
                state.apply(sequence)
            case .visible(let character):
                if character == TerminalSymbols.openCap || character == TerminalSymbols.closeCap {
                    caps.append(state)
                }
            }
        }
        return caps
    }

    /// Whether `state`'s foreground is `colour`, spelled in 24-bit colour: stating that
    /// colour again changes nothing.
    private func draws(_ state: SGRState, in colour: Color) -> Bool {
        let codes = colour.foregroundCodes(depth: .truecolor)
        var restated = state
        // A parsed 39 is no foreground at all, where the parameter list 39 is a named
        // colour; the parse is what the state went through.
        restated.setForeground(parameters: codes == ["39"] ? nil : codes)
        return restated == state
    }

    private func expectCaps(
        _ buffer: FrameBuffer, in colour: Color, _ what: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let line = buffer.lines[0]
        let caps = capStates(line)
        #expect(caps.count == 2, "\(what): \(line.debugDescription)", sourceLocation: sourceLocation)
        #expect(
            caps.allSatisfy { draws($0, in: colour) }, "\(what): \(line.debugDescription)",
            sourceLocation: sourceLocation)
    }

    @Test("At rest on the terminal's unreported page the caps are the tertiary tier",
        arguments: Control.allCases)
    func restingCapsAreTertiary(_ control: Control) {
        TerminalColors.withCurrent(.unknown) {
            let palette = TerminalPagePalette()
            expectCaps(
                render(control, palette, focused: false), in: palette.foregroundTertiary,
                "\(control) at rest")
            expectCaps(
                render(control, palette, focused: true, disabled: true),
                in: palette.foregroundTertiary, "\(control) disabled")
        }
    }

    @Test("Focused on the terminal's unreported page the caps hold the accent",
        arguments: Control.allCases)
    func focusedCapsAreTheAccent(_ control: Control) {
        TerminalColors.withCurrent(.unknown) {
            let palette = TerminalPagePalette()
            let drawn = render(control, palette, focused: true)
            expectCaps(drawn, in: palette.accent, "\(control) focused")
            // No breath: its dim end is the face, which is the accident at rest.
            #expect(drawn.animatedCells.isEmpty, "\(control): \(drawn.animatedCells)")
        }
    }

    /// Keyed on the accent too: tinting a face with a colour that has no RGB leaves
    /// the page, and a breath toward it has no RGB between its ends. The environment
    /// stores a palette's `Color.default` accent as the terminal's foreground (Opacity
    /// as composition §80), which has no RGB until the terminal reports it.
    @Test("An accent with no RGB gives the same caps on an RGB page", arguments: Control.allCases)
    func unmeasurableAccentOnAnRGBPage(_ control: Control) {
        TerminalColors.withCurrent(.unknown) {
            let palette = DefaultAccentPalette()
            let seen = GroundedPalette.grounding(palette)
            expectCaps(
                render(control, palette, focused: false), in: palette.foregroundTertiary,
                "\(control) at rest")
            let focused = render(control, palette, focused: true)
            expectCaps(focused, in: seen.accent, "\(control) focused")
            #expect(focused.animatedCells.isEmpty, "\(control): \(focused.animatedCells)")
        }
    }

    /// Once the terminal reports its foreground, that stored accent measures: the face is
    /// a tint again and the caps are drawn in it, breathing.
    @Test("A Color.default accent measures once the terminal reports its foreground",
        arguments: Control.allCases)
    func defaultAccentMeasuresOnceReported(_ control: Control) {
        TerminalColors.withCurrent(Self.reported) {
            let palette = DefaultAccentPalette()
            let seen = GroundedPalette.grounding(palette)
            #expect(seen.restingControlFace.rgbComponents != nil, "the fixture: a measurable face")
            expectCaps(
                render(control, palette, focused: false), in: seen.restingControlFace,
                "\(control) at rest")
            #expect(render(control, palette, focused: true).animatedCells.count == 2)
        }
    }

    /// Keyed on what can be measured, not on the palette: once the terminal reports its
    /// page, the face is a tint again and the caps are drawn in it.
    @Test("Over a reported page the caps are the face again, and breathe", arguments: Control.allCases)
    func reportedPageKeepsTheFace(_ control: Control) {
        TerminalColors.withCurrent(Self.reported) {
            let palette = TerminalPagePalette()
            #expect(palette.restingControlFace.rgbComponents != nil, "the fixture: a measurable face")
            expectCaps(
                render(control, palette, focused: false), in: palette.restingControlFace,
                "\(control) at rest")
            #expect(render(control, palette, focused: true).animatedCells.count == 2)
        }
    }

    /// Every built-in palette states RGB roles, so on a silent terminal its caps are
    /// what they were: the face at rest, a breath when focused.
    @Test("An RGB palette's caps rest in its face on a silent terminal", arguments: Control.allCases)
    func rgbPalettesKeepTheirFace(_ control: Control) {
        TerminalColors.withCurrent(.unknown) {
            for palette in PaletteRegistry.all {
                expectCaps(
                    render(control, palette, focused: false), in: palette.restingControlFace,
                    "\(control) at rest under \(palette.id)")
                #expect(
                    render(control, palette, focused: true).animatedCells.count == 2,
                    "\(control) under \(palette.id)")
            }
        }
    }

    /// The hovered face is the resting one wherever the accent or page has no RGB
    /// (`hoveredControlFace`'s guard), so a hovered cap rests in the tier too.
    @Test("A hovered face on the unreported page rests its caps in the tertiary tier")
    func hoveredFaceCapsAreTertiary() {
        TerminalColors.withCurrent(.unknown) {
            let palette = TerminalPagePalette()
            let context = makeRenderContext(width: 20, height: 3)
            let caps = ButtonCapCycle(
                isFocused: false, background: palette.hoveredControlFace, palette: palette,
                context: context)
            #expect(caps.colorNow == palette.foregroundTertiary)
            #expect(!caps.isAnimating)
        }
    }
}
