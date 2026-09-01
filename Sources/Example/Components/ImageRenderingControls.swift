//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageRenderingControls.swift
//
//  The image demos' control pane: every rendering knob, as a column beside the
//  picture rather than a strip above it.
//
//  Three things follow from the column. Radio buttons replace the pop-up
//  menus — every option is readable at once, which is what a demo is for, and
//  a pop-up that must be opened to see what is in it teaches nothing. Each
//  parameterised option CARRIES the control that parameterises it, as its own
//  content, so the two read as one thing and the group stays one list to arrow
//  down. And the pane scrolls, so a short terminal loses none of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Live controls for every image-rendering knob, driving the owning page's
/// ``ImageDemoSettings``.
struct ImageRenderingControls: View {
    @Binding var settings: ImageDemoSettings

    /// Whether the LUT editor is up.
    @State private var editingLUT = false

    /// Whether the per-channel curve editor is up.
    @State private var editingChannels = false

    /// Recently used custom ramps, persisted app-wide (most recent first).
    @AppStorage("imageDemo.recentRamps") private var recentRampsJSON = "[]"

    /// Pre-defined ramps for the combo menu (darkest first, matching the
    /// converter's luminance-ascending mapping).
    private static let ramps = [" .:-=+*#%@", " ░▒▓█", " .oO@", " ._xX#"]

    var body: some View {
        ScrollView {
            // In the order the renderer applies them: the image is sampled into
            // cells (how many samples per cell, and which glyph each becomes),
            // then re-mapped by the tone curve, then quantised to the colours
            // available. The pane used to read characters -> colour -> tone,
            // which put the last stage in the middle.
            VStack(alignment: .leading, spacing: 1) {
                characters
                sampling
                tone
                colour
            }
        }
        // A disabled control still ASSERTS the value it displays, so every
        // dependent knob snaps to what the configuration actually renders with
        // whenever a driver changes — a greyed-out "3×" supersampling under
        // shape matching would claim a sampling factor that isn't applied.
        .onAppear { settings.snap() }
        .onChange(of: settings.charset) { _, _ in settings.snap() }
        .onChange(of: settings.shapeAware) { _, _ in settings.snap() }
        // The engine's minimum sized subset is 2 glyphs (fewer isn't a
        // ramp/vocabulary), so 1 is unreachable: stepping up from 0 lands on 2,
        // stepping down from 2 lands on 0 (= the full repertoire).
        .onChange(of: settings.asciiGlyphs) { old, new in
            if new == 1 { settings.asciiGlyphs = new > old ? 2 : 0 }
        }
        .onChange(of: settings.unicodeGlyphs) { old, new in
            if new == 1 { settings.unicodeGlyphs = new > old ? 2 : 0 }
        }
        .modal(isPresented: $editingChannels) {
            ChannelCurveEditorPanel(
                "component.imageControls.toneChannels",
                channels: $settings.channelCurves,
                isPresented: $editingChannels)
        }
        .modal(isPresented: $editingLUT) {
            // The curve editor, not the gradient one. A gradient is colours at
            // even intervals; a look-up table is colours at tones you choose,
            // and the pane was showing the second as though it were the first.
            ToneCurveEditorPanel(
                "component.imageControls.lutTitle",
                stops: $settings.lutStops,
                isPresented: $editingLUT)
        }
    }

    // MARK: - Characters

    @ViewBuilder private var characters: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.characters")
            // One group, and each option carries the control that parameterises
            // IT — see ``RadioButtonItem``. It was four groups sharing a
            // binding for a while, which put each control under the right
            // option at the cost of the arrow keys that walk them: four groups
            // are four Tab stops where the reader sees one list.
            RadioButtonGroup(selection: $settings.charset) {
                RadioButtonItem(ImageDemoHelpers.Charset.ascii, "component.imageControls.ascii") {
                    glyphStepper(.ascii, value: $settings.asciiGlyphs)
                }
                RadioButtonItem(
                    ImageDemoHelpers.Charset.unicode, "component.imageControls.unicode"
                ) {
                    glyphStepper(.unicode, value: $settings.unicodeGlyphs)
                }
                RadioButtonItem(ImageDemoHelpers.Charset.blocks, "component.imageControls.blocks") {
                    // The blocks charset's discrete size. Disabled on its own
                    // account as well as by the group: shape matching draws
                    // blocks by ink coverage, and no style is chosen then.
                    RadioButtonGroup(selection: $settings.blockStyleIndex, orientation: .horizontal)
                    {
                        RadioButtonItem(0, ImageDemoHelpers.blockStyleLabel(0))
                        RadioButtonItem(1, ImageDemoHelpers.blockStyleLabel(1))
                        RadioButtonItem(2, ImageDemoHelpers.blockStyleLabel(2))
                        RadioButtonItem(3, ImageDemoHelpers.blockStyleLabel(3))
                        RadioButtonItem(4, ImageDemoHelpers.blockStyleLabel(4))
                    }
                    .disabled(
                        !ImageDemoHelpers.usesBlockStyle(
                            settings.charset, shapeAware: settings.shapeAware))
                }
                RadioButtonItem(ImageDemoHelpers.Charset.custom, "component.imageControls.custom") {
                    rampField
                }
            }
            // Off the ramp field and onto its own footing: what follows applies
            // to the charset CHOICE above rather than to the custom ramp it
            // would otherwise appear to continue.
            Text("")
            // Shape-awareness: match glyphs by their measured in-cell ink
            // distribution instead of overall luminance. Applies to every
            // charset except a custom ramp.
            Toggle("component.imageControls.shapeAware", isOn: $settings.shapeAware)
                .disabled(!ImageDemoHelpers.usesShape(settings.charset))

            // Edge tracing sits BESIDE shape-awareness rather than under it.
            // The two are orthogonal: one asks where the picture has an edge,
            // the other how a cell's ink is chosen, and either can be had
            // without the other. Each renderer takes the gradient from what it
            // already has — the shape one from six regions inside the cell,
            // the luminance one from the eight cells around it — so the
            // threshold means the same thing either way.
            //
            // It used to be nested inside the shape toggle, because the edge
            // test could only be asked of the shape sampling.
            Toggle("component.imageControls.edgeLines", isOn: $settings.edgeLines)
                .toggleContent {
                    // Cells on a clean light/dark boundary draw as directional
                    // line glyphs; the threshold picks how strong a gradient
                    // qualifies, so it is the edge toggle's content.
                    HStack(spacing: 1) {
                        Text("component.imageControls.edgeThreshold").dim()
                        // The slider's own `%`-of-range read-out would mislead
                        // beside the raw value shown after it.
                        Slider(value: $settings.edgeThreshold, in: 0.3...2.0, step: 0.1)
                            .sliderShowsValue(false)
                            .frame(maxWidth: .infinity)
                        Text(String(format: "%.1f", settings.edgeThreshold)).dim()
                    }
                }
                // The block repertoire carries its own directional glyphs and a
                // custom ramp has no vocabulary to borrow, so neither traces
                // edges — whether or not they shape-match.
                .disabled(
                    !ImageDemoHelpers.usesEdgeTracing(
                        settings.charset, shapeAware: settings.shapeAware))

            // The third of the three, and the only one about the PICTURE: an
            // unsharp mask run before any character is chosen, so both of the
            // toggles above read an image whose boundaries have already been
            // pulled apart. Never disabled — every charset is drawn from
            // pixels, so every charset can be drawn from sharper ones.
            Toggle("component.imageControls.edgeContrast", isOn: $settings.edgeContrast)
                .toggleContent {
                    HStack(spacing: 1) {
                        Text("component.imageControls.edgeContrastAmount").dim()
                        Slider(value: $settings.edgeContrastAmount, in: 0.1...2.0, step: 0.1)
                            .sliderShowsValue(false)
                            .frame(maxWidth: .infinity)
                        Text(String(format: "%.1f", settings.edgeContrastAmount)).dim()
                    }
                }
        }
    }

    /// One charset's glyph-count stepper. `0` is the whole repertoire.
    ///
    /// It carries no `disabled` of its own: it is an option's content, so the
    /// group disables it whenever that option is not the one chosen.
    @ViewBuilder private func glyphStepper(
        _ charset: ImageDemoHelpers.Charset, value: Binding<Int>
    ) -> some View {
        HStack(spacing: 1) {
            Stepper(
                "component.imageControls.glyphs", value: value,
                in: 0...max(
                    2,
                    ImageDemoHelpers.maximumGlyphs(charset, shapeAware: settings.shapeAware)))
            if value.wrappedValue == 0 {
                Text("component.imageControls.allGlyphs").dim()
            }
        }
    }

    // MARK: - Colour

    @ViewBuilder private var colour: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.colour")
            RadioButtonGroup(selection: $settings.colour) {
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.trueColor, "component.imageControls.trueColour")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.ansi256, "component.imageControls.colours256")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.ansi16, "component.imageControls.colours16")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.grayscale, "component.imageControls.greyscale")
                RadioButtonItem(ImageDemoSettings.ColourMode.mono, "component.imageControls.mono") {
                    // Mono's own knob. It emits no colour codes, so by default
                    // its cells take the page's — which is the theme's, and is
                    // what it has always drawn in. Off, the two are stated.
                    Toggle(
                        "component.imageControls.monoThemeColours",
                        isOn: $settings.monoThemeColours)
                }
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.themed, "component.imageControls.themed")
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.greys, "component.imageControls.greys"
                ) {
                    counted("component.imageControls.levels", value: $settings.greyLevels, in: 2...16)
                }
                RadioButtonItem(
                    ImageDemoSettings.ColourMode.sampled, "component.imageControls.sampled"
                ) {
                    counted(
                        "component.imageControls.colours", value: $settings.sampledColours,
                        in: 2...64)
                }
            }
            Toggle("component.imageControls.dithering", isOn: $settings.dithering)
        }
    }

    // MARK: - Sampling

    /// Supersampling is not a colour knob — it decides how many pixels each
    /// SAMPLE is averaged from, before anything has been mapped to a glyph or a
    /// colour at all. It sat under "Colour" as a dim caption, which read as one
    /// more of that section's rows rather than as a stage of its own.
    @ViewBuilder private var sampling: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.supersampling")
            // Applies to every non-shape renderer: each sample (cell tone,
            // half-cell pixel, braille dot) becomes an N x N area average.
            RadioButtonGroup(selection: $settings.supersampling, orientation: .horizontal) {
                RadioButtonItem(0, "component.imageControls.auto")
                RadioButtonItem(1, "1\u{D7}")
                RadioButtonItem(2, "2\u{D7}")
                RadioButtonItem(3, "3\u{D7}")
                RadioButtonItem(4, "4\u{D7}")
            }
            .disabled(
                !ImageDemoHelpers.usesSupersampling(
                    settings.charset, shapeAware: settings.shapeAware))
        }
    }

    // MARK: - Tone

    /// The recolouring, which had a keyboard shortcut and a status-bar label
    /// and no control at all — the gap this pane was asked for.
    @ViewBuilder private var tone: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.tone")
            RadioButtonGroup(selection: $settings.tone) {
                RadioButtonItem(ImageDemoSettings.Tone.off, "component.imageControls.toneOff")
                RadioButtonItem(
                    ImageDemoSettings.Tone.negative, "component.imageControls.toneNegative")
                RadioButtonItem(
                    ImageDemoSettings.Tone.accent, "component.imageControls.toneAccent")
                RadioButtonItem(
                    ImageDemoSettings.Tone.duotone, "component.imageControls.toneDuotone"
                ) {
                    // Duotone's two ends.
                    VStack(alignment: .leading, spacing: 0) {
                        ColorPicker(
                            "component.imageControls.shadows", selection: $settings.duotoneShadow
                        )
                        .colorPickerChannels(.hidden)
                        .colorPickerLabelWidth(10)
                        ColorPicker(
                            "component.imageControls.highlights",
                            selection: $settings.duotoneHighlight
                        )
                        .colorPickerChannels(.hidden)
                        .colorPickerLabelWidth(10)
                    }
                }
                RadioButtonItem(ImageDemoSettings.Tone.lut, "component.imageControls.toneLUT") {
                    // The ramp as it stands, and the way in to editing it.
                    HStack(spacing: 1) {
                        curveStrip(ASCIIToneCurve(settings.lutStops))
                        Button("component.imageControls.lutEdit") { editingLUT = true }
                    }
                }
                RadioButtonItem(
                    ImageDemoSettings.Tone.channels, "component.imageControls.toneChannels"
                ) {
                    // The three curves' effect on the grey ramp — which is
                    // where a colour cast shows, and the reason to reach for
                    // channels rather than a tone curve in the first place.
                    HStack(spacing: 1) {
                        curveStrip(ASCIIToneCurve(settings.channelCurves))
                        Button("component.imageControls.lutEdit") { editingChannels = true }
                    }
                }
            }
        }
    }

    /// A recolouring's output across the whole tone range, as a strip — the
    /// same thing the curve editors' lower strip shows, at a size that fits the
    /// pane. Shared by the LUT and the channel curves: both answer
    /// `color(atTone:)`, and both are worth seeing before you open an editor.
    ///
    /// Straight through the curve, cell by cell, rather than through
    /// `Color.quantisedRamp`: that helper repairs a GRADIENT into a monotone
    /// one, and a curve is not required to be monotone.
    private func curveStrip(_ curve: ASCIIToneCurve) -> some View {
        let width = 12
        // Over the COLOURS, not over `0..<width`: an `Equatable` element wraps
        // each cell in the element-keyed render memo, which cannot see the
        // curve the cell captured, so the strip freezes at whatever it drew
        // first. (It was `ForEach(ramp.indices, …)` before, with the same
        // hazard.)
        let cells = (0..<width).map { curve.color(atTone: Double($0) / Double(width - 1)) }
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, color in
                Text(verbatim: "\u{2588}").foregroundStyle(color)
            }
        }
    }

    // MARK: - Pieces

    private func heading(_ key: LocalizedStringKey) -> some View {
        Text(key).bold().foregroundStyle(.palette.accent)
    }

    /// A "how many" row: a slider and the number it is at.
    ///
    /// Neither indented nor disabled here — it is an option's content, and the
    /// group does both on its behalf.
    private func counted(
        _ key: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 1) {
            Text(key).dim()
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            // The slider's own `%`-of-range read-out would mislead beside the
            // count shown after it — 4 greys of 2...16 is not "14%" of
            // anything the reader is choosing.
            .sliderShowsValue(false)
            // The pane is a fixed width, so "as wide as it can be" is a width:
            // a 14-cell track gave two greys per cell of travel where the row
            // has room for one.
            .frame(maxWidth: .infinity)
            Text(verbatim: "\(value.wrappedValue)").dim()
        }
    }

    /// The custom-ramp combo field: type any ramp (darkest character first), or
    /// pick a pre-defined or recent one. A genuinely custom ramp is recorded on
    /// Enter and when the field loses focus (it applies live, so tabbing away
    /// must not lose it); the pre-defined options are never recorded — they
    /// already have a home above the divider.
    @ViewBuilder private var rampField: some View {
        let recents = RecentValues.list(from: recentRampsJSON)
            .filter { !Self.ramps.contains($0) }
        let record = {
            guard !Self.ramps.contains(settings.customRamp) else { return }
            recentRampsJSON = RecentValues.recording(settings.customRamp, in: recentRampsJSON)
        }
        // No caption of its own: the radio button it sits under already says
        // "Custom ramp", and repeating it read as two rows about two things.
        TextField("component.imageControls.customRamp", text: $settings.customRamp)
                .onSubmit(record)
                .onEditingChanged { began in
                    if !began { record() }
                }
                .textInputSuggestions {
                    ForEach(Self.ramps, id: \.self) { Text($0) }
                    if !recents.isEmpty {
                        Divider()
                        ForEach(recents, id: \.self) { Text($0) }
                    }
                }
            .frame(width: 16)
    }
}
