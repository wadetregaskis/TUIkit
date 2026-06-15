//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SliderRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Buffer-level render tests for Slider: asserts the rendered line is correct
//  across value positions, track styles, custom ranges, focus, disabled, and
//  width configurations. The slider draws as a single line:
//      ◀ <track> ▶ <NN%>
//  where the value field is padded to a fixed 4 columns so the track + arrows
//  hold a constant position as the value changes. (Mouse / wheel behaviour is
//  covered by SliderTests; this suite is about what lands in the FrameBuffer.)

import Testing

@testable import TUIkit

@MainActor
@Suite("Slider rendering")
struct SliderRenderTests {

    /// Renders WITHOUT a focus manager so no focus pulse is applied
    /// (matches the existing Slider test convention — see `makeBareRenderContext`).
    private func lines(_ v: some View, w: Int = 30, h: Int = 4) -> [String] {
        renderToBuffer(v, context: makeBareRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    /// Renders with a focus manager present (the slider auto-focuses).
    private func focusedLines(_ v: some View, w: Int = 30, h: Int = 4) -> [String] {
        renderToBuffer(v, context: makeRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    private func filled(_ line: String) -> Int { line.filter { $0 == "█" }.count }
    private func empty(_ line: String) -> Int { line.filter { $0 == "░" }.count }

    // MARK: - Structure

    @Test("A slider renders on exactly one line with both arrows and the value")
    func singleLineWithArrowsAndValue() {
        let out = lines(Slider(value: .constant(0.5)))
        #expect(out.count == 1, "exactly one line, got: \(out)")
        #expect(out[0].contains("◀"))
        #expect(out[0].contains("▶"))
        #expect(out[0].contains("50%"))
        #expect(out[0].hasPrefix("◀ "), "left arrow then a space leads the row: |\(out[0])|")
    }

    @Test("The string title is a description only — it is NOT drawn on the track (SwiftUI parity)")
    func titleNotDrawn() {
        // SwiftUI's Slider label is for accessibility, not display; TUIkit
        // matches that. The title text must not appear on the rendered track.
        let out = lines(Slider("Volume", value: .constant(0.5)))
        #expect(out.count == 1, "still a single line, got: \(out)")
        #expect(!out[0].contains("Volume"), "title must not be drawn: |\(out[0])|")
        #expect(out[0].hasPrefix("◀ "), "row leads with the arrow, not the title: |\(out[0])|")
        #expect(out[0].contains("50%"))
    }

    @Test("A default-width slider fills exactly the available width")
    func fillsAvailableWidth() {
        // chrome = 5 + 4 (value field) = 9; track = 30 - 9 = 21.
        let buffer = renderToBuffer(Slider(value: .constant(0.5)), context: makeBareRenderContext(width: 30, height: 4))
        #expect(buffer.width == 30, "slider should fill the available width, got \(buffer.width)")
        let line = buffer.lines[0].stripped
        #expect(filled(line) + empty(line) == 21, "track is 21 cells, got \(filled(line) + empty(line)): |\(line)|")
    }

    // MARK: - Value → fill proportion

    @Test("0% shows an entirely empty track and reads 0%")
    func zeroPercent() {
        let line = lines(Slider(value: .constant(0.0))).first ?? ""
        #expect(filled(line) == 0, "no filled cells at 0%, got \(filled(line)): |\(line)|")
        #expect(empty(line) == 21, "all 21 cells empty, got \(empty(line))")
        #expect(line.contains("0%"))
    }

    @Test("100% shows an entirely filled track and reads 100%")
    func hundredPercent() {
        let line = lines(Slider(value: .constant(1.0))).first ?? ""
        #expect(filled(line) == 21, "all 21 cells filled, got \(filled(line)): |\(line)|")
        #expect(empty(line) == 0, "no empty cells at 100%, got \(empty(line))")
        #expect(line.contains("100%"))
    }

    @Test("50% fills roughly half the track")
    func fiftyPercent() {
        let line = lines(Slider(value: .constant(0.5))).first ?? ""
        #expect(filled(line) == 11, "round(0.5*21)=11 filled, got \(filled(line)): |\(line)|")
        #expect(empty(line) == 10)
        #expect(line.contains("50%"))
    }

    @Test("Fill increases monotonically with the value")
    func fillMonotonic() {
        let f0 = filled(lines(Slider(value: .constant(0.0))).first ?? "")
        let f25 = filled(lines(Slider(value: .constant(0.25))).first ?? "")
        let f50 = filled(lines(Slider(value: .constant(0.5))).first ?? "")
        let f75 = filled(lines(Slider(value: .constant(0.75))).first ?? "")
        let f100 = filled(lines(Slider(value: .constant(1.0))).first ?? "")
        #expect(f0 < f25 && f25 < f50 && f50 < f75 && f75 < f100,
            "fill must grow with value: \(f0),\(f25),\(f50),\(f75),\(f100)")
    }

    // MARK: - Value field stays a fixed width

    @Test("The value field is padded so the track holds a constant position")
    func valueFieldFixedWidth() {
        // "7%" and "50%" are shorter than "100%"; the value field pads to 4
        // columns, so the track length is identical across all three values.
        let t7 = lines(Slider(value: .constant(0.07))).first ?? ""
        let t50 = lines(Slider(value: .constant(0.5))).first ?? ""
        let t100 = lines(Slider(value: .constant(1.0))).first ?? ""
        #expect(filled(t7) + empty(t7) == 21)
        #expect(filled(t50) + empty(t50) == 21)
        #expect(filled(t100) + empty(t100) == 21)
        #expect(t7.count == t50.count && t50.count == t100.count,
            "the whole row must be a constant width: \(t7.count),\(t50.count),\(t100.count)")
    }

    // MARK: - Custom range

    @Test("A custom 0...100 range maps the value to the same percentage")
    func customRange() {
        let line = lines(Slider(value: .constant(50.0), in: 0...100)).first ?? ""
        #expect(line.contains("50%"), "got: |\(line)|")
        #expect(filled(line) == 11, "got \(filled(line))")
    }

    @Test("An out-of-range value clamps to 0% / 100% (no overflow, no negative)")
    func clampsOutOfRange() {
        let high = lines(Slider(value: .constant(1.5))).first ?? ""
        #expect(high.contains("100%") && !high.contains("150%"), "got: |\(high)|")
        #expect(filled(high) == 21, "clamped-high track is full, got \(filled(high))")

        let low = lines(Slider(value: .constant(-0.5))).first ?? ""
        #expect(low.contains("0%") && !low.contains("-"), "got: |\(low)|")
        #expect(filled(low) == 0, "clamped-low track is empty, got \(filled(low))")
    }

    // MARK: - Track styles

    @Test("The dot style draws a single head marker at the fill boundary")
    func dotStyleHead() {
        let line = lines(Slider(value: .constant(0.5)).trackStyle(.dot)).first ?? ""
        #expect(line.filter { $0 == "●" }.count == 1, "exactly one dot head, got: |\(line)|")
        #expect(line.contains("▬") || line.contains("─"), "dot style uses ▬/─ track: |\(line)|")
        #expect(line.contains("50%"))
    }

    @Test("The shade style draws ▓ and ░ and still reads the value")
    func shadeStyle() {
        let line = lines(Slider(value: .constant(0.5)).trackStyle(.shade)).first ?? ""
        #expect(line.contains("▓"))
        #expect(line.contains("░"))
        #expect(line.contains("50%"))
    }

    // MARK: - Focus

    @Test("Focused and unfocused sliders render identical text (focus is colour-only)")
    func focusTextUnchanged() {
        let f = focusedLines(Slider(value: .constant(0.5)))
        let u = lines(Slider(value: .constant(0.5)))
        #expect(f == u, "focus must not change the stripped text; f=\(f) u=\(u)")
        #expect(f.count == 1)
    }

    // MARK: - Disabled

    @Test("A disabled slider still renders the full track, arrows and value")
    func disabledStillRenders() {
        // Disabled changes colours only; the stripped layout must be unchanged.
        let line = lines(Slider(value: .constant(0.5)).disabled()).first ?? ""
        #expect(line.contains("◀") && line.contains("▶"))
        #expect(line.contains("50%"))
        #expect(filled(line) + empty(line) == 21, "track unchanged when disabled: |\(line)|")
    }

    // MARK: - Width

    @Test("A wide slider expands the track to fill the width and still reads 50%")
    func wideExpandsTrack() {
        // chrome = 9; track = 60 - 9 = 51; round(0.5*51)=26 filled.
        let buffer = renderToBuffer(Slider(value: .constant(0.5)), context: makeBareRenderContext(width: 60, height: 4))
        #expect(buffer.width == 60, "got \(buffer.width)")
        let line = buffer.lines[0].stripped
        #expect(filled(line) + empty(line) == 51, "track is 51 cells, got \(filled(line) + empty(line))")
        #expect(line.contains("50%"))
    }

    @Test("At the minimum-fit width the slider stays one line and shows track, arrows and value")
    func minimumFitWidth() {
        // The track has a hard minimum of 10; with chrome 9 the smallest width
        // that fits everything is 19. At 19 the value must still be present.
        let line = lines(Slider(value: .constant(0.5)), w: 19).first ?? ""
        #expect(line.count <= 19, "must not exceed the available width, got \(line.count): |\(line)|")
        #expect(line.contains("◀") && line.contains("▶"), "both arrows present at min width: |\(line)|")
        #expect(line.contains("50%"), "value present at the minimum-fit width: |\(line)|")
        #expect(filled(line) + empty(line) == 10, "track at its 10-cell minimum, got \(filled(line) + empty(line))")
    }
}
