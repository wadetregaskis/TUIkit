//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ToggleRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Buffer-level render tests for Toggle: asserts the rendered line is correct
//  across on/off, labelled/unlabelled, focused/unfocused, disabled, custom
//  label and narrow-width configurations. (Behaviour — key/mouse handling — is
//  covered by ToggleTests; this suite is about what lands in the FrameBuffer.)

import Testing

@testable import TUIkit

@MainActor
@Suite("Toggle rendering")
struct ToggleRenderTests {
    /// The default checkbox marks: filled / empty squares, one cell wide.
    /// Deliberately non-emoji codepoints (no variation selector), so every
    /// terminal renders them monochrome, tintable, and one cell wide.
    private let on = "\u{25A0}"   // ■ checked
    private let off = "\u{25A1}"  // □ unchecked

    /// Renders with a focus manager present (the first focusable auto-focuses).
    private func lines(_ v: some View, w: Int = 30, h: Int = 4) -> [String] {
        renderToBuffer(v, context: makeRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    /// Renders WITHOUT a focus manager, so the control is unfocused.
    private func unfocusedLines(_ v: some View, w: Int = 30, h: Int = 4) -> [String] {
        renderToBuffer(v, context: makeBareRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    // MARK: - On / off indicator

    @Test("An OFF toggle renders □ then the label, on a single line")
    func offRendersEmptyBox() {
        let out = lines(Toggle("Wifi", isOn: .constant(false)))
        #expect(out.count == 1, "exactly one line, got: \(out)")
        #expect(out[0] == "\(off) Wifi", "got: |\(out[0])|")
    }

    @Test("An ON toggle renders ■ then the label, on a single line")
    func onRendersCheckedBox() {
        let out = lines(Toggle("Wifi", isOn: .constant(true)))
        #expect(out.count == 1, "exactly one line, got: \(out)")
        #expect(out[0] == "\(on) Wifi", "got: |\(out[0])|")
    }

    @Test("Flipping the binding flips the indicator glyph only")
    func indicatorTracksBinding() {
        let offLine = lines(Toggle("S", isOn: .constant(false))).first ?? ""
        let onLine = lines(Toggle("S", isOn: .constant(true))).first ?? ""
        #expect(offLine.hasPrefix(off))
        #expect(onLine.hasPrefix(on))
        // Only the leading glyph differs; the rest of the row is identical.
        #expect(offLine.dropFirst() == onLine.dropFirst())
    }

    @Test("The .ascii checkbox style restores the bracketed [x] / [ ] form")
    func asciiStyleRestoresBrackets() {
        let offLine = lines(Toggle("Wifi", isOn: .constant(false)).toggleCharacterSet(.ascii))
        let onLine = lines(Toggle("Wifi", isOn: .constant(true)).toggleCharacterSet(.ascii))
        #expect(offLine[0] == "[ ] Wifi", "got: |\(offLine[0])|")
        #expect(onLine[0] == "[x] Wifi", "got: |\(onLine[0])|")
    }

    @Test("The .switch style's knob is inset half blocks on the side the switch points to")
    func switchStyleRendersBlockKnob() {
        // Under the terminal-independent default (.unicode) the knob is built
        // from non-emoji, selector-free glyphs (▐▌: a one-cell knob centred
        // across two cells) so its SGR foreground applies and its width is
        // stable everywhere — same class as the checkbox marks (issue #9).
        // The half-cell of visible TRACK on each side of the knob is what
        // makes it read: the knob is drawn in the page-background colour,
        // and an edge-to-edge ██ knob melted into the page beside the
        // switch (found evaluating iTerm2).
        let offLine = lines(Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch)).first ?? ""
        let onLine = lines(Toggle("Wifi", isOn: .constant(true)).toggleStyle(.switch)).first ?? ""
        #expect(offLine.hasPrefix("▐▌ "), "off: knob left, blank right — got: |\(offLine)|")
        #expect(onLine.hasPrefix(" ▐▌"), "on: blank left, knob right — got: |\(onLine)|")
        #expect(offLine.contains("Wifi") && onLine.contains("Wifi"))
    }

    @Test("Under .emoji the switch knob is the seamless two-cell large square")
    func switchKnobFollowsEmojiStyle() {
        // Terminal.app draws visible seams between adjacent FULL BLOCK cells
        // but renders ⬛︎ as one seamless two-cell glyph, so the knob follows
        // the checkbox style's glyph repertoire. Both knobs are two cells —
        // the 3-cell track geometry is identical either way.
        let knob = "\u{2B1B}\u{FE0E}"
        let offLine = lines(
            Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch).toggleCharacterSet(.emoji)
        ).first ?? ""
        let onLine = lines(
            Toggle("Wifi", isOn: .constant(true)).toggleStyle(.switch).toggleCharacterSet(.emoji)
        ).first ?? ""
        #expect(offLine.hasPrefix(knob + " "), "off: knob left — got: |\(offLine)|")
        #expect(onLine.hasPrefix(" " + knob), "on: knob right — got: |\(onLine)|")

        #expect(SwitchIndicatorGlyphs.knob(for: .emoji) == knob)
        // Non-emoji knobs are the half-block pair ▐▌ — a one-cell knob
        // centred across two cells, leaving half a cell of TRACK visible on
        // each side. The knob is drawn in the page-background colour, so
        // without that visible track margin (as with edge-to-edge ██) it
        // melts into the page and the switch reads as a bare colour chip.
        #expect(SwitchIndicatorGlyphs.knob(for: .unicode) == "\u{2590}\u{258C}")
        #expect(SwitchIndicatorGlyphs.knob(for: .ascii) == "\u{2590}\u{258C}")
        #expect(SwitchIndicatorGlyphs.knob(for: .unicode).strippedLength == 2)
    }

    @Test("Under .ascii the switch is a bracketed track with a sliding knob")
    func switchFollowsAsciiStyle() {
        // `[o ]` off, `[ o]` on: the knob slides like the coloured-track
        // switch, inside the same bracket chrome as the `[x]` checkbox — no
        // block glyphs and no background colours, keeping the style honest for
        // terminals/fonts where those are the reason `.ascii` was chosen. The
        // knob is also state-coloured (accent when on), the checkbox's
        // two-tone convention.
        let offLine = lines(
            Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch).toggleCharacterSet(.ascii)
        ).first ?? ""
        let onLine = lines(
            Toggle("Wifi", isOn: .constant(true)).toggleStyle(.switch).toggleCharacterSet(.ascii)
        ).first ?? ""
        #expect(offLine.hasPrefix("[o ]"), "off: knob left — got: |\(offLine)|")
        #expect(onLine.hasPrefix("[ o]"), "on: knob right — got: |\(onLine)|")
        #expect(offLine.contains("Wifi") && onLine.contains("Wifi"))
    }

    @Test("The maximum-compatibility styles stay outside the emoji problem class")
    func checkboxMarksAreTerminalSafe() {
        // Emoji-presentation codepoints paint as fixed-colour emoji (ignoring
        // the theme tint), and variation selectors are mis-measured by some
        // terminals, shearing the row (issue #9). The .unicode and .ascii
        // styles must avoid both outright — .emoji is the deliberate,
        // documented exception, which is why `.automatic` gates it onto the
        // hosts verified to draw it correctly (Terminal.app and iTerm2).
        for style in [ToggleCharacterSet.unicode, .ascii] {
            for mark in [style.onMark, style.offMark, style.openBracket, style.closeBracket] {
                for scalar in mark.unicodeScalars {
                    #expect(
                        !(0xFE00...0xFE0F).contains(scalar.value),
                        "no variation selectors in '\(mark)' (U+\(String(scalar.value, radix: 16)))")
                    #expect(
                        !scalar.properties.isEmoji,
                        "no emoji codepoints in '\(mark)' (U+\(String(scalar.value, radix: 16)))")
                }
            }
        }
        // Every built-in's on/off marks are width-equal, so toggling never
        // shifts the label — including the two-cell emoji pair.
        for style in [ToggleCharacterSet.unicode, .emoji, .ascii] {
            #expect(style.onMark.strippedLength == style.offMark.strippedLength)
        }
    }

    @Test("The .emoji style is the large squares in text presentation, two cells wide")
    func emojiStyleMarks() {
        #expect(ToggleCharacterSet.emoji.onMark == "\u{2B1B}\u{FE0E}")
        #expect(ToggleCharacterSet.emoji.offMark == "\u{2B1C}\u{FE0E}")
        #expect(ToggleCharacterSet.emoji.onMark.strippedLength == 2)
        let out = lines(Toggle("Wifi", isOn: .constant(false)).toggleCharacterSet(.emoji))
        #expect(out.first == "\u{2B1C}\u{FE0E} Wifi", "got: |\(out.first ?? "")|")
    }

    @Test(".automatic is a marker, resolved against the terminal at render")
    func automaticStyleResolution() {
        #expect(ToggleCharacterSet.automatic(emojiChrome: true) == .emoji)
        #expect(ToggleCharacterSet.automatic(emojiChrome: false) == .unicode)
        // Both allowlisted hosts qualify: Terminal.app and iTerm2 (verified
        // by eye — see TerminalHost.supportsEmojiChrome).
        #expect(TerminalHost.detectAppleTerminal(
            environment: ["TERM_PROGRAM": "Apple_Terminal"]))
        #expect(TerminalHost.detectITerm2(environment: ["TERM_PROGRAM": "iTerm.app"]))
        #expect(!TerminalHost.detectITerm2(environment: ["TERM_PROGRAM": "Apple_Terminal"]))
        #expect(!TerminalHost.detectITerm2(environment: [:]))

        // `.automatic` does NOT bake in the host at construction. It used to —
        // it was literally `automatic(emojiChrome: TerminalHost.supportsEmojiChrome)`
        // — which froze whatever was true when the value was made, typically at
        // app-state init. Under tmux the right answer depends on the attached
        // CLIENT and changes on re-attach, so the decision has to be deferred.
        #expect(ToggleCharacterSet.automatic.resolvesFromTerminal)
        #expect(!ToggleCharacterSet.unicode.resolvesFromTerminal)
        #expect(!ToggleCharacterSet.emoji.resolvesFromTerminal)
        #expect(!ToggleCharacterSet.ascii.resolvesFromTerminal)
        #expect(!ToggleCharacterSet(onMark: "x", offMark: "o").resolvesFromTerminal)

        // It is its own value, distinct from the marks it falls back to —
        // which is what lets a caller match `case .automatic`.
        #expect(ToggleCharacterSet.automatic != .unicode)
        #expect(ToggleCharacterSet.automatic != .emoji)

        // The bare environment default stays terminal-independent (.unicode),
        // so headless renders and this suite are deterministic; the app run
        // loop injects the marker at its root instead.
        #expect(EnvironmentValues().toggleCharacterSet == .unicode)
    }

    @Test("An .automatic marker resolves to whatever the frame says the terminal is")
    func automaticResolvesFromTheEnvironment() {
        var environment = EnvironmentValues()
        environment.toggleCharacterSet = .automatic

        // Nothing resolved yet (headless): the deterministic .unicode fallback.
        #expect(environment.effectiveToggleCharacterSet == .unicode)

        // The run loop supplies the answer for the terminal in front of the user
        // this frame; the SAME marker now draws emoji.
        environment.resolvedAutomaticToggleCharacterSet = .emoji
        #expect(environment.effectiveToggleCharacterSet == .emoji)

        // …and follows it back when the client changes (a tmux re-attach from a
        // terminal whose font can't draw them).
        environment.resolvedAutomaticToggleCharacterSet = .unicode
        #expect(environment.effectiveToggleCharacterSet == .unicode)
    }

    @Test("An explicit style is never second-guessed by the terminal")
    func explicitStylesIgnoreTheResolvedAnswer() {
        for explicit in [ToggleCharacterSet.unicode, .emoji, .ascii] {
            var environment = EnvironmentValues()
            environment.toggleCharacterSet = explicit
            environment.resolvedAutomaticToggleCharacterSet = .emoji
            #expect(environment.effectiveToggleCharacterSet == explicit)
            environment.resolvedAutomaticToggleCharacterSet = .ascii
            #expect(environment.effectiveToggleCharacterSet == explicit)
        }
    }

    @Test("A Toggle draws the marker's resolved glyphs, not its fallback")
    func toggleRendersTheResolvedAutomaticStyle() {
        // The end-to-end shape of the fix: `.toggleCharacterSet(.automatic)` — what
        // TUIkitExample applies app-wide — must follow the resolved answer.
        var context = makeRenderContext(width: 20, height: 2)
        context.environment.resolvedAutomaticToggleCharacterSet = .emoji
        let buffer = renderToBuffer(
            Toggle("Wifi", isOn: .constant(false)).toggleCharacterSet(.automatic), context: context)
        #expect(
            buffer.lines.first?.stripped == "\u{2B1C}\u{FE0E} Wifi",
            "got: |\(buffer.lines.first?.stripped ?? "")|")
    }

    // MARK: - Empty / whitespace label (the "empty chrome" bug class)

    @Test("An unlabelled toggle is one line with the indicator, never a blank line")
    func emptyLabelHasNoBlankLine() {
        let out = lines(Toggle("", isOn: .constant(false)))
        #expect(out.count == 1, "unlabelled toggle must be a single line, got: \(out)")
        // The line must start with the indicator and not be blank.
        #expect(out[0].hasPrefix(off), "got: |\(out[0])|")
        #expect(!out[0].isEmpty, "must not be a blank line, got: |\(out[0])|")
    }

    @Test("An unlabelled ON toggle still shows the checked indicator")
    func emptyLabelOnShowsCheck() {
        let out = lines(Toggle("", isOn: .constant(true)))
        #expect(out.count == 1)
        #expect(out[0].hasPrefix(on), "got: |\(out[0])|")
    }

    @Test("A whitespace-only label does not add extra lines")
    func whitespaceLabelSingleLine() {
        let out = lines(Toggle("   ", isOn: .constant(false)))
        #expect(out.count == 1, "got: \(out)")
        #expect(out[0].hasPrefix(off))
    }

    // MARK: - Custom (ViewBuilder) label

    @Test("A ViewBuilder-label toggle renders the custom label after the box")
    func viewBuilderLabel() {
        let out = lines(Toggle(isOn: .constant(true)) { Text("Custom") })
        #expect(out.count == 1)
        #expect(out[0] == "\(on) Custom", "got: |\(out[0])|")
    }

    // MARK: - Focus

    @Test("Focused and unfocused toggles render identical text (focus is colour-only)")
    func focusDoesNotChangeText() {
        let focused = lines(Toggle("Net", isOn: .constant(false)))
        let unfocused = unfocusedLines(Toggle("Net", isOn: .constant(false)))
        #expect(focused == unfocused, "focus must not change the stripped text; f=\(focused) u=\(unfocused)")
        #expect(focused.first == "\(off) Net")
    }

    @Test("In a stack the second (unfocused) toggle still renders its box and label")
    func unfocusedInStack() {
        let out = lines(
            VStack(spacing: 0) {
                Toggle("First", isOn: .constant(false))
                Toggle("Second", isOn: .constant(true))
            })
        #expect(out.count == 2, "one row per toggle, got: \(out)")
        #expect(out[0].hasPrefix("\(off) First"))
        #expect(out[1].hasPrefix("\(on) Second"))
    }

    // MARK: - Disabled

    @Test("A disabled toggle still renders its indicator and label (no missing content)")
    func disabledStillRenders() {
        // Disabled changes colour only; the stripped text must be unchanged.
        let out = lines(Toggle("Wifi", isOn: .constant(true)).disabled())
        #expect(out.count == 1)
        #expect(out[0] == "\(on) Wifi", "got: |\(out[0])|")
    }

    @Test("A disabled OFF toggle still shows the empty box and label")
    func disabledOffRenders() {
        let out = lines(Toggle("Wifi", isOn: .constant(false)).disabled())
        #expect(out[0] == "\(off) Wifi", "got: |\(out[0])|")
    }

    // MARK: - Width / truncation

    @Test("A long label is hard-clipped to the available width on one line")
    func longLabelClipsToWidth() {
        // Toggle joins its (possibly wrapped) label into one line and clips to
        // the buffer width — it never spills onto extra lines.
        let out = lines(Toggle("A very long setting label here", isOn: .constant(true)), w: 12)
        #expect(out.count == 1, "must stay on a single line, got: \(out)")
        #expect(out[0].strippedLength <= 12, "must not exceed the available width, got: |\(out[0])|")
        #expect(out[0].hasPrefix("\(on) "), "indicator stays at the front, got: |\(out[0])|")
    }

    @Test("A wide toggle shows the full label with no padding artefacts")
    func wideShowsFullLabel() {
        let out = lines(Toggle("Short", isOn: .constant(false)), w: 40)
        #expect(out.count == 1)
        #expect(out[0] == "\(off) Short", "got: |\(out[0])|")
    }
}
