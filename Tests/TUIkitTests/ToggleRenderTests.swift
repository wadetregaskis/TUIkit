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
        let offLine = lines(Toggle("Wifi", isOn: .constant(false)).checkboxStyle(.ascii))
        let onLine = lines(Toggle("Wifi", isOn: .constant(true)).checkboxStyle(.ascii))
        #expect(offLine[0] == "[ ] Wifi", "got: |\(offLine[0])|")
        #expect(onLine[0] == "[x] Wifi", "got: |\(onLine[0])|")
    }

    @Test("The .switch style's knob is FULL BLOCKs on the side the switch points to")
    func switchStyleRendersBlockKnob() {
        // Under the terminal-independent default (.unicode) the knob is built
        // from non-emoji, selector-free glyphs (██) so its SGR foreground
        // applies and its width is stable everywhere — same class as the
        // checkbox marks (issue #9).
        let offLine = lines(Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch)).first ?? ""
        let onLine = lines(Toggle("Wifi", isOn: .constant(true)).toggleStyle(.switch)).first ?? ""
        #expect(offLine.hasPrefix("██ "), "off: knob left, blank right — got: |\(offLine)|")
        #expect(onLine.hasPrefix(" ██"), "on: blank left, knob right — got: |\(onLine)|")
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
            Toggle("Wifi", isOn: .constant(false)).toggleStyle(.switch).checkboxStyle(.emoji)
        ).first ?? ""
        let onLine = lines(
            Toggle("Wifi", isOn: .constant(true)).toggleStyle(.switch).checkboxStyle(.emoji)
        ).first ?? ""
        #expect(offLine.hasPrefix(knob + " "), "off: knob left — got: |\(offLine)|")
        #expect(onLine.hasPrefix(" " + knob), "on: knob right — got: |\(onLine)|")

        #expect(SwitchIndicatorGlyphs.knob(for: .emoji) == knob)
        #expect(SwitchIndicatorGlyphs.knob(for: .unicode) == "\u{2588}\u{2588}")
        #expect(SwitchIndicatorGlyphs.knob(for: .ascii) == "\u{2588}\u{2588}")
    }

    @Test("The maximum-compatibility styles stay outside the emoji problem class")
    func checkboxMarksAreTerminalSafe() {
        // Emoji-presentation codepoints paint as fixed-colour emoji (ignoring
        // the theme tint), and variation selectors are mis-measured by some
        // terminals, shearing the row (issue #9). The .unicode and .ascii
        // styles must avoid both outright — .emoji is the deliberate,
        // documented exception, which is why `.automatic` gates it onto
        // Terminal.app (whose output path carries the emoji workarounds).
        for style in [CheckboxStyle.unicode, .ascii] {
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
        for style in [CheckboxStyle.unicode, .emoji, .ascii] {
            #expect(style.onMark.strippedLength == style.offMark.strippedLength)
        }
    }

    @Test("The .emoji style is the large squares in text presentation, two cells wide")
    func emojiStyleMarks() {
        #expect(CheckboxStyle.emoji.onMark == "\u{2B1B}\u{FE0E}")
        #expect(CheckboxStyle.emoji.offMark == "\u{2B1C}\u{FE0E}")
        #expect(CheckboxStyle.emoji.onMark.strippedLength == 2)
        let out = lines(Toggle("Wifi", isOn: .constant(false)).checkboxStyle(.emoji))
        #expect(out.first == "\u{2B1C}\u{FE0E} Wifi", "got: |\(out.first ?? "")|")
    }

    @Test(".automatic resolves to .emoji under Apple's Terminal.app, .unicode elsewhere")
    func automaticStyleResolution() {
        #expect(CheckboxStyle.automatic(isAppleTerminal: true) == .emoji)
        #expect(CheckboxStyle.automatic(isAppleTerminal: false) == .unicode)
        // The live property agrees with the live detection, whatever hosts
        // the suite.
        #expect(CheckboxStyle.automatic
            == CheckboxStyle.automatic(isAppleTerminal: TerminalHost.isAppleTerminal))
        // The bare environment default stays terminal-independent (.unicode),
        // so headless renders and this suite are deterministic; the app run
        // loop injects .automatic at its root instead.
        #expect(EnvironmentValues().checkboxStyle == .unicode)
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
