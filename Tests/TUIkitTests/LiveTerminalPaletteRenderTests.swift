//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveTerminalPaletteRenderTests.swift
//
//  What the palette that follows the terminal's own colours actually draws. Its
//  spellings are pinned in `LiveTerminalPaletteTests`; this is the palette as the
//  ENVIRONMENT stores it — grounded on the terminal's page (Opacity as composition
//  §80) — and the frames drawn with it. While the terminal has said nothing there is
//  no colour of the palette's own anywhere in a frame: the page is 49, the text 39,
//  the slots are slots, a control's face shows nothing, and the highlights that cannot
//  be measured are reverse video (§86, §87). Once the terminal reports its colours the
//  tiers dim for real and the surfaces step off the page it reported.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("What the terminal's own palette draws")
struct LiveTerminalPaletteRenderTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal "Basic" as it reports itself (Terminal-compatibility.md, measured
    /// 2026-09-14): black on white, and its sixteen.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255),
        slots: TerminalColors.Slots(UnreportedANSISlotTests.appleBasic))

    /// Ghostty 1.3.1's default configuration as it reports itself (measured the same
    /// day): white on #282c34, and its sixteen.
    private static let ghostty = TerminalColors(
        foreground: rgb(255, 255, 255), background: rgb(40, 44, 52),
        slots: TerminalColors.Slots([
            rgb(29, 31, 33), rgb(204, 102, 102), rgb(181, 189, 104), rgb(240, 198, 116),
            rgb(129, 162, 190), rgb(178, 148, 187), rgb(138, 190, 183), rgb(197, 200, 198),
            rgb(102, 102, 102), rgb(213, 78, 83), rgb(185, 202, 74), rgb(231, 197, 71),
            rgb(122, 166, 218), rgb(195, 151, 216), rgb(112, 192, 177), rgb(234, 234, 234),
        ]))

    /// Both hosts that answered all sixteen, as a palette that follows them must work on
    /// a light terminal and a dark one alike.
    private static let reported = [("Apple Terminal Basic", appleTerminal), ("Ghostty", ghostty)]

    private static let page = Color(value: .terminalBackground)
    private static let ink = Color(value: .terminalForeground)

    /// The palette as the registry hands it out.
    private func live() throws -> any Palette {
        try #require(
            PaletteRegistry.palette(withId: "terminal.live"),
            "the registry has no palette that follows the terminal's own colours")
    }

    /// `palette` as the environment stores it: grounded on the terminal's own colours.
    private func stored(_ palette: any Palette) -> any Palette {
        var environment = EnvironmentValues()
        environment.palette = palette
        return environment.palette
    }

    /// The fifteen roles a palette states, as opposed to the two it derives.
    private func statedRoles(_ palette: any Palette) -> [(String, Color)] {
        [
            ("background", palette.background),
            ("statusBarBackground", palette.statusBarBackground),
            ("appHeaderBackground", palette.appHeaderBackground),
            ("overlayBackground", palette.overlayBackground),
            ("foreground", palette.foreground),
            ("foregroundSecondary", palette.foregroundSecondary),
            ("foregroundTertiary", palette.foregroundTertiary),
            ("foregroundQuaternary", palette.foregroundQuaternary),
            ("accent", palette.accent),
            ("success", palette.success),
            ("warning", palette.warning),
            ("error", palette.error),
            ("info", palette.info),
            ("border", palette.border),
            ("cursorColor", palette.cursorColor),
        ]
    }

    /// Each visible cell of `line` with the SGR state in force on it.
    private func cells(_ line: String) -> [(character: Character, state: SGRState)] {
        var state = SGRState()
        var result: [(character: Character, state: SGRState)] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character): result.append((character, state))
            }
        }
        return result
    }

    // MARK: - Stored, while the terminal has said nothing

    /// The whole point of the palette. A role of the palette's OWN would be painted
    /// whatever the user set their terminal to, which is the one thing this palette
    /// exists not to do.
    @Test("Stored, no role is a colour of the palette's own")
    func noStoredRoleIsRGB() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = stored(try live())
            for (role, colour) in statedRoles(palette) {
                if case .rgb = colour.value {
                    Issue.record("\(role) is \(colour), a colour of the palette's own")
                }
                #expect(colour.isTerminalDefined, "\(role) is \(colour)")
                #expect(colour.rgbComponents == nil, "\(role) measured as \(colour)")
            }
        }
    }

    @Test("Stored, the grounds are the terminal's page and every tier its plain foreground")
    func groundsAndTiersAreTheTerminals() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = stored(try live())
            #expect(palette.background == Self.page)
            #expect(palette.statusBarBackground == Self.page)
            #expect(palette.appHeaderBackground == Self.page)
            #expect(palette.overlayBackground == Self.page)
            // Full strength, not dimmed: over a page with no RGB there is no dimmer
            // colour to show, and the blend rule would make a tier below half the page
            // itself (Opacity as composition §80).
            for tier in [
                palette.foreground, palette.foregroundSecondary,
                palette.foregroundTertiary, palette.foregroundQuaternary,
            ] {
                #expect(tier == Self.ink, "\(tier)")
                #expect(tier.foregroundCodes(depth: .truecolor) == ["39"], "\(tier)")
            }
            // Both derived surfaces have nowhere to step to, so they are the page.
            #expect(palette.focusBackground == Self.page)
            #expect(palette.fieldBackground == Self.page)
        }
    }

    /// A control's face is a tint of the accent over the page, and a hover a further
    /// tint. With neither end measurable every share is one end or the other, so the
    /// face is the page and the hover is the face (Opacity as composition §75, §82).
    @Test("Stored, a control's face shows nothing and its hover shows nothing more")
    func noFaceAndNoHoverFill() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = stored(try live())
            #expect(!palette.accentTintIsMeasurable)
            #expect(palette.restingControlFace == Self.page)
            #expect(palette.hoveredControlFace == palette.restingControlFace)
            // The ink lifts instead, up the ladder of names: the accent's bright twin.
            #expect(palette.hoveredForeground(palette.accent) == .ansi(.brightBlue))
            #expect(palette.hoveredLabel(palette.foreground).isTerminalDefined)
        }
    }

    /// The caps of a button whose face is the page would otherwise be drawn in that
    /// page, which the foreground slot spells as 39: two bright half blocks, by
    /// accident (Opacity as composition §78).
    @Test("Stored, a button's end caps rest in the tertiary tier")
    func restingCapsAreTheTertiaryTier() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = stored(try live())
            let context = makeRenderContext(width: 20, height: 3)
            let caps = ButtonCapCycle(
                isFocused: false, background: palette.restingControlFace, palette: palette,
                context: context)
            #expect(caps.colorNow == palette.foregroundTertiary)
            #expect(!caps.isAnimating)
        }
    }

    // MARK: - A frame drawn with it

    /// Everything a page of the Example's kind draws: a bordered box, a button, a list
    /// and text in three tiers.
    @ViewBuilder
    private func sampler() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("title").foregroundStyle(.palette.foreground)
            Text("detail").foregroundStyle(.palette.foregroundSecondary)
            Button("Save") {}
            List(selection: .constant(Set([0]))) {
                ForEach(0..<2, id: \.self) { Text("row \($0)") }
            }
        }
        .border(.palette.border)
    }

    /// The claim in one line of bytes: with the terminal silent, a frame names no
    /// colour at all — every ink is a slot or 39, every ground 49.
    @Test("A frame names no colour of the palette's own while the terminal is silent")
    func frameNamesNoColourOfItsOwn() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = try live()
            let context = makeRenderContext(width: 30, height: 10) { environment, _ in
                environment.palette = palette
            }
            let drawn = ColorDepth.withCurrent(.truecolor) {
                _ = renderToBuffer(sampler(), context: context)
                return renderToBuffer(sampler(), context: context)
            }
            let bytes = drawn.lines.joined()
            for spelling in ["38;2", "48;2", "38;5", "48;5"] {
                #expect(!bytes.contains(spelling), "\(spelling) in \(bytes.debugDescription)")
            }
        }
    }

    /// A focused cursor row's fill is a tint of the accent over the page; neither can be
    /// measured, so the row reverses the palette's own pair instead (§86).
    @Test("A focused list's cursor row is reverse video")
    func cursorRowReverses() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = try live()
            let context = makeRenderContext(width: 24, height: 8) { environment, _ in
                environment.palette = palette
            }
            let view = List(selection: .constant(Set([0]))) {
                ForEach(0..<3, id: \.self) { Text("row \($0)") }
            }
            let drawn = ColorDepth.withCurrent(.truecolor) {
                _ = renderToBuffer(view, context: context)
                return renderToBuffer(view, context: context)
            }
            let line = try #require(drawn.lines.first { $0.stripped.contains("row 0") })
            let text = cells(line).filter { $0.character == "r" || $0.character == "w" }
            #expect(!text.isEmpty, "\(line.debugDescription)")
            #expect(text.allSatisfy { $0.state.reversesVideo }, "\(line.debugDescription)")
            // A steady reversal, so nothing is left for the run loop to animate.
            #expect(drawn.animatedCells.isEmpty, "\(drawn.animatedCells)")
        }
    }

    /// A text input's selection is a share of the accent over its well, which is the
    /// page here: nothing to measure, so it reverses the cell's own pair (§87).
    @Test("A text input's selection is reverse video")
    func textSelectionReverses() throws {
        try TerminalColors.withCurrent(.unknown) {
            let palette = stored(try live())
            let renderer = TextFieldContentRenderer(
                prompt: nil, isDisabled: false, displayCharacter: { $0 },
                surface: palette.fieldBackground.resolve(with: palette), contentForeground: nil)
            let content = ColorDepth.withCurrent(.truecolor) {
                renderer.buildContent(
                    text: "abcdef", cursorPosition: 0, selectionRange: 1..<4, isFocused: true,
                    palette: palette, cursorStyle: TextCursorStyle(shape: .bar, animation: .none),
                    cursorTimer: nil, contentWidth: 12)
            }
            let selected = cells(content.line).filter { "bcd".contains($0.character) }
            #expect(selected.count == 3, "\(content.line.debugDescription)")
            // The `allSatisfy` closures are hoisted out of their `#expect`s on purpose. A
            // closure inside a macro expansion and one in ordinary source, in the same
            // enclosing closure, are lowered to a SINGLE SIL function — so one of the two
            // bodies never runs. Do not fold them back in; see
            // Tools/CompilerBugs/MacroClosureDiscriminatorCollision.
            let selectionIsReversed = selected.allSatisfy { $0.state.reversesVideo }
            #expect(selectionIsReversed, "\(content.line.debugDescription)")
            let others = cells(content.line).filter { "aef".contains($0.character) }
            let othersAreNotReversed = others.allSatisfy { !$0.state.reversesVideo }
            #expect(othersAreNotReversed, "\(content.line.debugDescription)")
        }
    }

    // MARK: - Once the terminal has reported its colours

    @Test("Reported, its slots and its page are still the terminal's own spellings")
    func reportedFrameKeepsTheTerminalsSpellings() throws {
        for (host, terminal) in Self.reported {
            try TerminalColors.withCurrent(terminal) {
                let palette = stored(try live())
                #expect(palette.background.backgroundCodes(depth: .truecolor) == ["49"], "\(host)")
                #expect(palette.foreground.foregroundCodes(depth: .truecolor) == ["39"], "\(host)")
                #expect(palette.accent.foregroundCodes(depth: .truecolor) == ["34"], "\(host)")
                #expect(palette.success.foregroundCodes(depth: .truecolor) == ["32"], "\(host)")
                #expect(palette.warning.foregroundCodes(depth: .truecolor) == ["33"], "\(host)")
                #expect(palette.error.foregroundCodes(depth: .truecolor) == ["31"], "\(host)")
                #expect(palette.info.foregroundCodes(depth: .truecolor) == ["36"], "\(host)")
                #expect(palette.border.foregroundCodes(depth: .truecolor) == ["90"], "\(host)")
            }
        }
    }

    /// The tiers are a real dimming once there is a page to dim toward, and both derived
    /// surfaces become a step off the page the terminal reported.
    @Test("Reported, the tiers dim and the surfaces step off the page")
    func reportedTiersDimAndSurfacesStep() throws {
        for (host, terminal) in Self.reported {
            try TerminalColors.withCurrent(terminal) {
                let palette = stored(try live())
                let tiers = [
                    palette.foregroundSecondary, palette.foregroundTertiary,
                    palette.foregroundQuaternary,
                ]
                for tier in tiers {
                    #expect(tier.rgbComponents != nil, "\(host): \(tier) still measures as nothing")
                    #expect(tier != Self.ink, "\(host): \(tier) is the plain foreground")
                }
                let page = palette.background.resolve(with: palette)
                for (role, surface) in [
                    ("fieldBackground", palette.fieldBackground),
                    ("focusBackground", palette.focusBackground),
                ] {
                    let step = surface.resolve(with: palette).lightnessDifference(from: page)
                    #expect(
                        step >= SystemPalette.planeSeparation,
                        "\(host): \(role) is ΔL* \(String(format: "%.1f", step)) off the page")
                }
            }
        }
    }

    /// A tint of the accent over the reported page can be measured, so the controls the
    /// silent terminal left plain get their fills back.
    @Test("Reported, a control's face is a tint again")
    func reportedFaceIsATintAgain() throws {
        for (host, terminal) in Self.reported {
            try TerminalColors.withCurrent(terminal) {
                let palette = stored(try live())
                #expect(palette.accentTintIsMeasurable, "\(host)")
                #expect(palette.restingControlFace != palette.background, "\(host)")
                #expect(palette.hoveredControlFace != palette.restingControlFace, "\(host)")
            }
        }
    }

    /// Keyed on what can be measured, not on the palette: with the colours reported, a
    /// cursor row is a fill that breathes, exactly as every other palette's is.
    @Test("Reported, the cursor row is a fill again")
    func reportedCursorRowIsAFill() throws {
        try TerminalColors.withCurrent(Self.appleTerminal) {
            let palette = try live()
            let context = makeRenderContext(width: 24, height: 8) { environment, _ in
                environment.palette = palette
            }
            let view = List(selection: .constant(Set([0]))) {
                ForEach(0..<3, id: \.self) { Text("row \($0)") }
            }
            let drawn = ColorDepth.withCurrent(.truecolor) {
                _ = renderToBuffer(view, context: context)
                return renderToBuffer(view, context: context)
            }
            let line = try #require(drawn.lines.first { $0.stripped.contains("row 0") })
            let text = cells(line).filter { $0.character == "r" || $0.character == "w" }
            #expect(!text.isEmpty, "\(line.debugDescription)")
            #expect(text.allSatisfy { !$0.state.reversesVideo }, "\(line.debugDescription)")
            #expect(text.allSatisfy { $0.state.namesBackground }, "\(line.debugDescription)")
        }
    }
}
