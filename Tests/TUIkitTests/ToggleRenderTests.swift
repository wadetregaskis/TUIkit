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

    /// Renders with a focus manager present (the first focusable auto-focuses).
    private func lines(_ v: some View, w: Int = 30, h: Int = 4) -> [String] {
        renderToBuffer(v, context: makeRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    /// Renders WITHOUT a focus manager, so the control is unfocused.
    private func unfocusedLines(_ v: some View, w: Int = 30, h: Int = 4) -> [String] {
        renderToBuffer(v, context: makeBareRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    // MARK: - On / off indicator

    @Test("An OFF toggle renders [ ] then the label, on a single line")
    func offRendersEmptyBox() {
        let out = lines(Toggle("Wifi", isOn: .constant(false)))
        #expect(out.count == 1, "exactly one line, got: \(out)")
        #expect(out[0] == "[ ] Wifi", "got: |\(out[0])|")
    }

    @Test("An ON toggle renders [x] then the label, on a single line")
    func onRendersCheckedBox() {
        let out = lines(Toggle("Wifi", isOn: .constant(true)))
        #expect(out.count == 1, "exactly one line, got: \(out)")
        #expect(out[0] == "[x] Wifi", "got: |\(out[0])|")
    }

    @Test("Flipping the binding flips the indicator glyph only")
    func indicatorTracksBinding() {
        let off = lines(Toggle("S", isOn: .constant(false))).first ?? ""
        let on = lines(Toggle("S", isOn: .constant(true))).first ?? ""
        #expect(off.hasPrefix("[ ]"))
        #expect(on.hasPrefix("[x]"))
        // Only the in-bracket glyph differs; the rest of the row is identical.
        #expect(off.dropFirst(3) == on.dropFirst(3))
    }

    // MARK: - Empty / whitespace label (the "empty chrome" bug class)

    @Test("An unlabelled toggle is one line with the indicator, never a blank line")
    func emptyLabelHasNoBlankLine() {
        let out = lines(Toggle("", isOn: .constant(false)))
        #expect(out.count == 1, "unlabelled toggle must be a single line, got: \(out)")
        // The line must start with the indicator and not be blank.
        #expect(out[0].hasPrefix("[ ]"), "got: |\(out[0])|")
        #expect(out[0].first == "[", "must not be a blank line, got: |\(out[0])|")
    }

    @Test("An unlabelled ON toggle still shows the checked indicator")
    func emptyLabelOnShowsCheck() {
        let out = lines(Toggle("", isOn: .constant(true)))
        #expect(out.count == 1)
        #expect(out[0].hasPrefix("[x]"), "got: |\(out[0])|")
    }

    @Test("A whitespace-only label does not add extra lines")
    func whitespaceLabelSingleLine() {
        let out = lines(Toggle("   ", isOn: .constant(false)))
        #expect(out.count == 1, "got: \(out)")
        #expect(out[0].hasPrefix("[ ]"))
    }

    // MARK: - Custom (ViewBuilder) label

    @Test("A ViewBuilder-label toggle renders the custom label after the box")
    func viewBuilderLabel() {
        let out = lines(Toggle(isOn: .constant(true)) { Text("Custom") })
        #expect(out.count == 1)
        #expect(out[0] == "[x] Custom", "got: |\(out[0])|")
    }

    // MARK: - Focus

    @Test("Focused and unfocused toggles render identical text (focus is colour-only)")
    func focusDoesNotChangeText() {
        let focused = lines(Toggle("Net", isOn: .constant(false)))
        let unfocused = unfocusedLines(Toggle("Net", isOn: .constant(false)))
        #expect(focused == unfocused, "focus must not change the stripped text; f=\(focused) u=\(unfocused)")
        #expect(focused.first == "[ ] Net")
    }

    @Test("In a stack the second (unfocused) toggle still renders its box and label")
    func unfocusedInStack() {
        let out = lines(
            VStack(spacing: 0) {
                Toggle("First", isOn: .constant(false))
                Toggle("Second", isOn: .constant(true))
            })
        #expect(out.count == 2, "one row per toggle, got: \(out)")
        #expect(out[0].hasPrefix("[ ] First"))
        #expect(out[1].hasPrefix("[x] Second"))
    }

    // MARK: - Disabled

    @Test("A disabled toggle still renders its indicator and label (no missing content)")
    func disabledStillRenders() {
        // Disabled changes colour only; the stripped text must be unchanged.
        let out = lines(Toggle("Wifi", isOn: .constant(true)).disabled())
        #expect(out.count == 1)
        #expect(out[0] == "[x] Wifi", "got: |\(out[0])|")
    }

    @Test("A disabled OFF toggle still shows the empty box and label")
    func disabledOffRenders() {
        let out = lines(Toggle("Wifi", isOn: .constant(false)).disabled())
        #expect(out[0] == "[ ] Wifi", "got: |\(out[0])|")
    }

    // MARK: - Width / truncation

    @Test("A long label is hard-clipped to the available width on one line")
    func longLabelClipsToWidth() {
        // Toggle joins its (possibly wrapped) label into one line and clips to
        // the buffer width — it never spills onto extra lines.
        let out = lines(Toggle("A very long setting label here", isOn: .constant(true)), w: 12)
        #expect(out.count == 1, "must stay on a single line, got: \(out)")
        #expect(out[0].count <= 12, "must not exceed the available width, got len \(out[0].count): |\(out[0])|")
        #expect(out[0].hasPrefix("[x] "), "indicator stays at the front, got: |\(out[0])|")
    }

    @Test("A wide toggle shows the full label with no padding artefacts")
    func wideShowsFullLabel() {
        let out = lines(Toggle("Short", isOn: .constant(false)), w: 40)
        #expect(out.count == 1)
        #expect(out[0] == "[ ] Short", "got: |\(out[0])|")
    }
}
