//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ButtonRowRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Buffer-level render tests for ButtonRow: buttons laid out horizontally from
//  the leading edge with `spacing` columns between them, on a single line, each
//  with its own focus identity (only the focused one pulses). Asserts the
//  composed line, the inter-button gaps, the empty-row case, and that exactly
//  one focus indicator appears across the row.

import Testing

@testable import TUIkit

@MainActor
@Suite("ButtonRow rendering")
struct ButtonRowRenderTests {

    private func makeContext(width: Int = 40, height: Int = 8) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext())
    }

    private func lines(_ view: some View, width: Int = 40, height: Int = 8) -> [String] {
        renderToBuffer(view, context: makeContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    private let openCap = "\u{2590}"
    private let closeCap = "\u{258C}"

    // MARK: - Empty

    @Test("An empty ButtonRow renders an empty buffer (no lines)")
    func emptyRow() {
        let buffer = renderToBuffer(ButtonRow {}, context: makeContext())
        #expect(buffer.isEmpty, "no buttons → empty buffer")
        #expect(buffer.lines.isEmpty)
    }

    // MARK: - Single button

    @Test("A one-button row renders exactly that button, hugging its label")
    func singleButton() {
        let out = lines(ButtonRow { Button("Only") {} })
        #expect(out.count == 1)
        #expect(out[0] == "\(openCap) Only \(closeCap)", "got: '\(out[0])'")
    }

    // MARK: - Default spacing (2)

    @Test("Two default buttons sit side by side with two spaces between them")
    func twoButtonsDefaultSpacing() {
        let out = lines(ButtonRow { Button("Cancel") {}; Button("OK") {} })
        #expect(out.count == 1, "single line: \(out)")
        #expect(out[0] == "\(openCap) Cancel \(closeCap)  \(openCap) OK \(closeCap)",
            "got: '\(out[0])'")
        // `▐ Cancel ▌`(10) + 2 spaces + `▐ OK ▌`(6) = 18.
        #expect(out[0].strippedLength == 18)
    }

    @Test("Three buttons are laid out left to right with a 2-space gap each")
    func threeButtons() {
        let out = lines(ButtonRow { Button("A") {}; Button("B") {}; Button("C") {} })
        #expect(out.count == 1)
        #expect(out[0] == "\(openCap) A \(closeCap)  \(openCap) B \(closeCap)  \(openCap) C \(closeCap)",
            "got: '\(out[0])'")
    }

    // MARK: - Custom spacing

    @Test("Custom spacing inserts exactly that many columns between buttons")
    func customSpacing() {
        let out = lines(ButtonRow(spacing: 5) { Button("A") {}; Button("B") {} })
        #expect(out.count == 1)
        // `▐ A ▌`(5) + 5 spaces + `▐ B ▌`(5) = 15.
        #expect(out[0] == "\(openCap) A \(closeCap)     \(openCap) B \(closeCap)", "got: '\(out[0])'")
        #expect(out[0].strippedLength == 15)
    }

    // MARK: - Empty-label member

    @Test("A row with an empty-label button keeps that button's caps and the gap")
    func rowWithEmptyLabelButton() {
        let out = lines(ButtonRow { Button("") {}; Button("OK") {} })
        #expect(out.count == 1, "single line: \(out)")
        // Empty button stays `▐  ▌` (caps + padding), 2-space gap, then `▐ OK ▌`.
        #expect(out[0] == "\(openCap)  \(closeCap)  \(openCap) OK \(closeCap)", "got: '\(out[0])'")
        #expect(out[0].hasPrefix(openCap))
        #expect(out[0].hasSuffix(closeCap))
    }

    // MARK: - Focus distribution

    @Test("Only the first button in the row carries the focus indicator")
    func onlyFirstButtonFocused() {
        // Each button gets its own focus identity; the first focusable to
        // register against a fresh manager is auto-focused. In a plain-style
        // row that surfaces as a single `●` (the focus dot) on button one.
        let out = lines(ButtonRow { Button("Cancel") {}; Button("OK") {} }.buttonStyle(.plain))
        #expect(out.count == 1)
        let dots = out[0].filter { $0 == "\u{25CF}" }.count
        #expect(dots == 1, "exactly one focus dot across the row: '\(out[0])'")
        // The composed line: `● Cancel` + 2-space row gap + `  OK` (2-cell
        // unfocused prefix on button two) → "● Cancel    OK".
        #expect(out[0] == "\u{25CF} Cancel    OK", "got: '\(out[0])'")
    }
}
