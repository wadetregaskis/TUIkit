//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ButtonRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Buffer-level render tests for Button across its configurations (default /
//  plain / destructive styles, empty label, disabled, focused vs unfocused,
//  narrow truncation, wide), asserting the rendered lines look correct: a
//  single-line bracketed control that hugs its label, with ellipsis
//  truncation that keeps the caps aligned and never overflows the cell.

import Testing

@testable import TUIkit

@MainActor
@Suite("Button rendering")
struct ButtonRenderTests {

    /// A render context with a fresh `FocusManager`. The first focusable to
    /// render against a fresh manager is auto-focused (so screens open with a
    /// focused element) — the very Button under test, unless a sentinel claims
    /// focus first.
    private func makeContext(width: Int = 30, height: Int = 8) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext())
    }

    /// Renders `view` and returns its visible (ANSI-stripped) lines.
    private func lines(_ view: some View, width: Int = 30, height: Int = 8) -> [String] {
        renderToBuffer(view, context: makeContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    /// Renders `view` and returns the joined lines *with* ANSI escapes intact.
    private func ansi(_ view: some View, width: Int = 30, height: Int = 8) -> String {
        renderToBuffer(view, context: makeContext(width: width, height: height))
            .lines.joined(separator: "\n")
    }

    // U+2590 ▐ opening cap, U+258C ▌ closing cap (TerminalSymbols.openCap/closeCap).
    private let openCap = "\u{2590}"
    private let closeCap = "\u{258C}"

    // MARK: - Default (bracketed) style

    @Test("A default button renders one bracketed line that hugs its label")
    func defaultBracketed() {
        let out = lines(Button("OK") {})
        #expect(out.count == 1, "single line: \(out)")
        #expect(out[0] == "\(openCap) OK \(closeCap)", "got: '\(out[0])'")
        // It hugs the label: 2 caps + 2 padding + 2 label = 6, not the full width.
        #expect(out[0].strippedLength == 6)
    }

    @Test("A wide proposal does not stretch the button — it still hugs the label")
    func wideHugsLabel() {
        let narrow = lines(Button("Hi") {}, width: 12)
        let wide = lines(Button("Hi") {}, width: 60)
        #expect(narrow == wide, "button width must not depend on the proposal: \(narrow) vs \(wide)")
        #expect(wide[0] == "\(openCap) Hi \(closeCap)")
    }

    // MARK: - Empty label

    @Test("An empty-label button is a single line, not a blank line")
    func emptyLabelSingleLine() {
        let out = lines(Button("") {})
        #expect(out.count == 1, "single line: \(out)")
        // Caps stay continuous around the (empty) label + its padding: `▐  ▌`.
        // The line is NOT blank and NOT a border gap (cf. the Panel empty-title class).
        #expect(out[0] == "\(openCap)  \(closeCap)", "got: '\(out[0])'")
        #expect(out[0].hasPrefix(openCap), "starts with the opening cap")
        #expect(out[0].hasSuffix(closeCap), "ends with the closing cap")
        let isBlank = out[0].allSatisfy { $0 == " " }
        #expect(!isBlank, "the row is not blank")
    }

    // MARK: - Roles & alternate styles

    @Test("A destructive-role button renders its label bracketed")
    func destructiveRole() {
        let out = lines(Button("Delete", role: .destructive) {})
        #expect(out.count == 1)
        #expect(out[0] == "\(openCap) Delete \(closeCap)", "got: '\(out[0])'")
    }

    @Test("A plain-style button drops the brackets and shows the focus dot when focused")
    func plainFocused() {
        // First (only) focusable → auto-focused → pulsing `● ` prefix, no caps.
        let out = lines(Button("OK") {}.buttonStyle(.plain))
        #expect(out.count == 1)
        #expect(out[0] == "\u{25CF} OK", "got: '\(out[0])'")  // ● + space + label
        #expect(!out[0].contains(openCap) && !out[0].contains(closeCap), "no caps in plain style")
    }

    @Test("An unfocused plain-style button shows a 2-cell blank prefix, no dot")
    func plainUnfocused() {
        // Park focus on a directly-registered sentinel so the button under
        // test renders un-focused. (Registering via a prior render does not
        // work: each render pass re-collects focusables, so the next button
        // becomes "first" again and re-claims auto-focus — hence the sentinel
        // is registered straight onto the manager, the pattern ButtonTests
        // uses for its hover cases.)
        let context = makeContext()
        context.environment.focusManager.register(FocusHolder())
        let out = renderToBuffer(Button("Second") {}.buttonStyle(.plain), context: context)
            .lines.map { $0.stripped }
        #expect(out.count == 1)
        #expect(out[0] == "  Second", "unfocused plain prefix is 2 spaces: '\(out[0])'")
        #expect(!out[0].contains("\u{25CF}"), "no focus dot when unfocused")
    }

    // MARK: - Disabled

    @Test("A disabled button still renders its label on one bracketed line")
    func disabledStillRenders() {
        let out = lines(Button("OK") {}.disabled())
        #expect(out.count == 1)
        #expect(out[0] == "\(openCap) OK \(closeCap)", "got: '\(out[0])'")
    }

    @Test("A disabled button renders visually distinct (dimmed) from a focused one")
    func disabledDiffersFromFocused() {
        // Same stripped glyphs, different ANSI styling: focused pulses/bolds,
        // disabled dims. The ANSI strings must differ.
        let focused = ansi(Button("OK") {})
        let disabled = ansi(Button("OK") {}.disabled())
        #expect(focused != disabled, "disabled and focused must not render identically")
    }

    @Test("A disabled button registers no hit-test region")
    func disabledNoHitRegion() {
        let buffer = renderToBuffer(Button("OK") {}.disabled(), context: makeContext())
        #expect(buffer.hitTestRegions.isEmpty, "disabled buttons take no hit region")
    }

    // MARK: - Truncation (narrow width)

    @Test("A too-long label is ellipsis-truncated and never overflows the cell")
    func narrowTruncatesWithEllipsis() {
        // Standard chrome = 2 caps + 2 padding = 4 cells; width 8 → 4 for label.
        let out = lines(Button("Submit Form Now") {}, width: 8)
        #expect(out.count == 1)
        #expect(out[0] == "\(openCap) Sub\u{2026} \(closeCap)", "got: '\(out[0])'")  // ▐ Sub… ▌
        #expect(out[0].contains("\u{2026}"), "truncation shows an ellipsis")
        #expect(out[0].strippedLength <= 8, "never overflows the available width")
        #expect(out[0].hasPrefix(openCap))
        #expect(out[0].hasSuffix(closeCap))
    }

    @Test("A plain-style label also truncates with an ellipsis when squeezed")
    func plainNarrowTruncates() {
        // Plain chrome = 2-cell focus prefix; width 5 → 3 cells for label.
        let out = lines(Button("Submit Form Now") {}.buttonStyle(.plain), width: 5)
        #expect(out.count == 1)
        #expect(out[0] == "\u{25CF} Su\u{2026}", "got: '\(out[0])'")  // ● Su…
        #expect(out[0].strippedLength <= 5, "never overflows the available width")
    }
}

/// A minimal focusable used to claim auto-focus before the button under test
/// renders, so that button renders in its un-focused state.
private final class FocusHolder: Focusable {
    let focusID = "button-render-tests-focus-holder"
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}
