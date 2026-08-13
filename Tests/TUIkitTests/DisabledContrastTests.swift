//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DisabledContrastTests.swift
//
//  A disabled control still has to be READABLE. It had not been: the label
//  colour was faded against the page background and then painted on the
//  control's accent-tinted face, skipping the contrast floor its sibling
//  branches apply — 1.05–1.62:1 on every built-in palette, and on five of them
//  the 256-colour cube quantised foreground and background to the SAME entry,
//  so a disabled button rendered as an empty box. (`Tools/Smoke/tui_screens.py`
//  caught it as "invisible text (fg==bg==005f00)".)
//
//  These read the colours back out of the emitted SGR rather than recomputing
//  the formula, so they fail if the wiring changes as well as if the arithmetic
//  does — and they sweep every registered palette, because the defect was
//  invisible on eleven of the sixteen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("Disabled controls stay readable")
struct DisabledContrastTests {

    /// A rendered control's first explicit foreground/background pair.
    private struct Painted {
        let foreground: Color
        let background: Color

        /// What the terminal actually shows on a 256-colour host. The floor is
        /// computed in truecolor, so this is where a colour that only just
        /// cleared it can collapse back onto its own background.
        var quantised: (foreground: Color, background: Color) {
            (foreground.downsampledToPalette256(), background.downsampledToPalette256())
        }
    }

    /// Renders `view` under `palette` and pulls out the colours of the run
    /// that actually contains `label`.
    ///
    /// Not simply the first `38;2;` in the line: a button opens with a
    /// half-block end cap whose FOREGROUND is the button's face colour, so
    /// pairing that with the label's background compares a colour with itself
    /// and every palette looks broken.
    private func paint(_ view: some View, label: String, palette: any Palette) -> Painted? {
        withColorDepth(.truecolor) {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            environment.palette = palette
            let context = RenderContext(
                availableWidth: 40, availableHeight: 4, environment: environment, tuiContext: tui)
            let raw = renderToBuffer(view, context: context).lines.joined()
            guard let text = raw.range(of: label) else { return nil }
            let preceding = String(raw[raw.startIndex..<text.lowerBound])
            guard let fg = lastColor(in: preceding, prefix: "38;2;"),
                let bg = lastColor(in: preceding, prefix: "48;2;")
            else { return nil }
            return Painted(foreground: fg, background: bg)
        }
    }

    /// The last `prefix`-introduced colour before the label — i.e. the one in
    /// force when the label's own characters are emitted.
    private func lastColor(in raw: String, prefix: String) -> Color? {
        guard let start = raw.range(of: prefix, options: .backwards) else { return nil }
        let digits = raw[start.upperBound...].prefix { $0.isNumber || $0 == ";" }
        let parts = digits.split(separator: ";").compactMap { UInt8($0) }
        guard parts.count >= 3 else { return nil }
        return .rgb(parts[0], parts[1], parts[2])
    }

    /// The two controls that paint a label on an accent-tinted face — the
    /// surface the disabled colour was not being measured against.
    private func disabledControls() -> [(name: String, label: String, view: AnyView)] {
        [
            ("Button", "Disabled", AnyView(Button("Disabled") {}.disabled(true))),
            (
                "Picker", "fine",
                AnyView(
                    Picker("Mode", selection: .constant(0)) {
                        Text(verbatim: "fine").tag(0)
                    }.disabled(true))
            ),
        ]
    }

    /// The defect exactly as the render lint sees it: two colours that are one
    /// colour by the time they reach the screen.
    @Test("no palette paints a disabled label in its own background colour")
    func neverInvisible() throws {
        for palette in PaletteRegistry.all {
            for control in disabledControls() {
                let painted = try #require(
                    paint(control.view, label: control.label, palette: palette),
                    "\(control.name) under \(palette.name) painted no explicit colours")
                let shown = painted.quantised
                #expect(
                    shown.foreground != shown.background,
                    """
                    \(control.name) is invisible under \(palette.name): \
                    foreground and background both quantise to the same \
                    256-colour entry
                    """)
            }
        }
    }

    @Test("a disabled label clears the contrast floor on every palette")
    func clearsTheFloor() throws {
        for palette in PaletteRegistry.all {
            for control in disabledControls() {
                let painted = try #require(
                    paint(control.view, label: control.label, palette: palette))
                let ratio = painted.foreground.contrastRatio(against: painted.background)
                #expect(
                    ratio >= ViewConstants.labelContrastFloor - 0.01,
                    """
                    \(control.name) under \(palette.name) is at \
                    \(String(format: "%.2f", ratio)):1, below the \
                    \(ViewConstants.labelContrastFloor):1 floor
                    """)
            }
        }
    }

    /// The floor must not be raised so far that "disabled" out-shouts
    /// "enabled" — which is what ruled a 4:1 disabled floor out, where eight of
    /// the sixteen palettes inverted by a whole ratio point. A future bump has
    /// to keep this true.
    ///
    /// The tolerance is deliberately loose. On a dim palette BOTH labels get
    /// pinned to the same floor and land within a hundredth of each other,
    /// which is not an inversion — it is two colours meeting the same minimum.
    /// What this catches is the real thing: disabled clearing the floor by a
    /// margin enabled does not.
    @Test("a disabled label is never materially more contrasty than an enabled one")
    func disabledStaysRecessive() throws {
        let tolerance = 0.25
        for palette in PaletteRegistry.all {
            let off = try #require(
                paint(Button("Label") {}.disabled(true), label: "Label", palette: palette))
            let on = try #require(paint(Button("Label") {}, label: "Label", palette: palette))
            let offRatio = off.foreground.contrastRatio(against: off.background)
            let onRatio = on.foreground.contrastRatio(against: on.background)
            #expect(
                offRatio <= onRatio + tolerance,
                """
                \(palette.name) inverts the states: disabled \
                \(String(format: "%.2f", offRatio)):1 vs enabled \
                \(String(format: "%.2f", onRatio)):1
                """)
        }
    }
}
