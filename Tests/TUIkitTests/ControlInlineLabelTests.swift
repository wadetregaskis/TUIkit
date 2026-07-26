//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ControlInlineLabelTests.swift
//
//  Slider and Picker draw their label to the LEFT, on the same line, and
//  reserve nothing at all when there is no label.
//
//  This is measured macOS SwiftUI behaviour, not a guess. Real `Slider`s and
//  `Picker`s were hosted in an `NSHostingView` and the drawn AppKit controls
//  captured with `cacheDisplay` (`ImageRenderer` is useless here — it renders
//  AppKit-backed controls as placeholder glyphs). What that showed:
//
//      Slider(value: $a) { Text("Volume") }  ->  "Volume  ▬▬▬▬●▬▬▬▬"
//      Slider(value: $b)                     ->  "▬▬▬▬▬▬▬●▬▬▬▬▬▬▬"
//      Picker("Theme", …)                    ->  "Theme  [ Dark ⌄ ]"
//      Picker("", …)                         ->  "[ Dark ⌄ ]"
//
//  i.e. the label shares the control's line and the control shrinks to fit;
//  an absent label costs nothing, not even a leading space. Before this,
//  Slider dropped its label on the floor entirely and Picker put it on a line
//  of its own.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Controls draw their label inline, to the left")
struct ControlInlineLabelTests {

    /// Renders `view` and returns its non-empty stripped lines.
    private func lines(of view: some View, width: Int = 40, height: Int = 6) -> [String] {
        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Slider

    @Test("a Slider's label is drawn, to the left of the track")
    func sliderDrawsItsLabel() {
        let rendered = lines(of: Slider(value: .constant(0.5)) { Text("Volume") })
        #expect(rendered.count == 1, "the label shares the track's line: \(rendered)")
        let line = rendered[0]
        #expect(line.contains("Volume"), "the label must be drawn at all: \(line)")
        let labelAt = line.range(of: "Volume").map { line.distance(from: line.startIndex, to: $0.lowerBound) }
        let arrowAt = line.range(of: "◀").map { line.distance(from: line.startIndex, to: $0.lowerBound) }
        #expect(labelAt == 0, "the label leads the line: \(line)")
        if let labelAt, let arrowAt {
            #expect(labelAt < arrowAt, "the label precedes the track: \(line)")
        }
    }

    @Test("a labelled Slider shortens its track rather than overflowing")
    func sliderShortensItsTrack() {
        let width = 40
        let plain = lines(of: Slider(value: .constant(0.5)), width: width)[0]
        let labelled = lines(of: Slider(value: .constant(0.5)) { Text("Volume") }, width: width)[0]
        // Both fill the same available width — the label eats into the track,
        // it does not push the trailing chrome off the end.
        #expect(
            labelled.strippedLength <= width,
            "a labelled slider must not overflow its width: \(labelled.strippedLength) > \(width)")
        let plainTrack = plain.filter { $0 == "━" || $0 == "─" }.count
        let labelledTrack = labelled.filter { $0 == "━" || $0 == "─" }.count
        #expect(
            labelledTrack < plainTrack,
            "the label must come out of the track: \(labelledTrack) vs \(plainTrack)")
    }

    @Test("an unlabelled Slider reserves nothing — no leading gap")
    func unlabelledSliderHasNoLeadingGap() {
        let line = lines(of: Slider(value: .constant(0.5)))[0]
        #expect(line.hasPrefix("◀"), "the track starts at column 0: \(line)")
    }

    // MARK: - Picker

    @Test("a Picker's label sits on the control's line, not above it")
    func pickerLabelIsInline() {
        let rendered = lines(
            of: Picker("Theme", selection: .constant(1)) {
                Text("Light").tag(0)
                Text("Dark").tag(1)
            })
        #expect(rendered.count == 1, "label and control share one line: \(rendered)")
        let line = rendered[0]
        #expect(line.hasPrefix("Theme"), "the label leads the line: \(line)")
        #expect(line.contains("Dark"), "the selected option is on the same line: \(line)")
    }

    @Test("an unlabelled Picker reserves nothing — no leading gap, no blank line")
    func unlabelledPickerHasNoLeadingGap() {
        let rendered = lines(
            of: Picker("", selection: .constant(1)) {
                Text("Light").tag(0)
                Text("Dark").tag(1)
            })
        #expect(rendered.count == 1, "no stray label line: \(rendered)")
        #expect(
            !rendered[0].hasPrefix(" "),
            "an absent label must not leave a leading space: '\(rendered[0])'")
    }

    @Test("a radio-group Picker's label leads the FIRST option's line")
    func radioGroupPickerLabelIsTopAligned() {
        // macOS SwiftUI top-aligns the label with the first radio button,
        // rather than centring it against the group.
        let rendered = lines(
            of: Picker("Theme", selection: .constant(1)) {
                Text("Light").tag(0)
                Text("Dark").tag(1)
                Text("Auto").tag(2)
            }
            .pickerStyle(.radioGroup))
        #expect(rendered.count == 3, "one line per option, label folded in: \(rendered)")
        #expect(rendered[0].hasPrefix("Theme"), "label leads the first option: \(rendered)")
        #expect(rendered[0].contains("Light"), "first option shares the label's line: \(rendered)")
    }
}
