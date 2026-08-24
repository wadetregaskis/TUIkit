//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageRenderingControls.swift
//
//  The image demos' control pane: every rendering knob, as a column beside the
//  picture rather than a strip above it.
//
//  Three things follow from the column. Radio buttons replace the pop-up
//  menus — every option is readable at once, which is what a demo is for, and
//  a pop-up that must be opened to see what is in it teaches nothing. Each
//  parameterised option is followed IMMEDIATELY by the control that
//  parameterises it, disabled while another option is chosen, so the two read
//  as one thing (the same shape the Spinners page settled on). And the pane
//  scrolls, so a short terminal loses none of it.
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

    /// Recently used custom ramps, persisted app-wide (most recent first).
    @AppStorage("imageDemo.recentRamps") private var recentRampsJSON = "[]"

    /// Pre-defined ramps for the combo menu (darkest first, matching the
    /// converter's luminance-ascending mapping).
    private static let ramps = [" .:-=+*#%@", " ░▒▓█", " .oO@", " ._xX#"]

    /// How wide a slider in the pane is. Narrow enough that the pane stays a
    /// column rather than a second page.
    private static let sliderWidth = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                characters
                colour
                tone
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
        .onChange(of: settings.glyphCount) { old, new in
            if new == 1 { settings.glyphCount = new > old ? 2 : 0 }
        }
        .modal(isPresented: $editingLUT) {
            GradientEditorPanel(
                "component.imageControls.lutTitle",
                stops: $settings.lutStops,
                isPresented: $editingLUT)
        }
    }

    // MARK: - Characters

    @ViewBuilder private var characters: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.characters")
            RadioButtonGroup(selection: $settings.charset) {
                RadioButtonItem(ImageDemoHelpers.Charset.ascii, "component.imageControls.ascii")
                RadioButtonItem(ImageDemoHelpers.Charset.unicode, "component.imageControls.unicode")
                RadioButtonItem(ImageDemoHelpers.Charset.blocks, "component.imageControls.blocks")
                RadioButtonItem(ImageDemoHelpers.Charset.custom, "component.imageControls.custom")
            }
            // Charset size: how many glyphs the ideal subset keeps (0 = the
            // full repertoire). ASCII and Unicode, which are the two above it.
            HStack(spacing: 1) {
                Stepper(
                    "component.imageControls.glyphs", value: $settings.glyphCount,
                    in: 0...max(
                        2,
                        ImageDemoHelpers.maximumGlyphs(
                            settings.charset, shapeAware: settings.shapeAware)))
                if settings.glyphCount == 0 {
                    Text("component.imageControls.allGlyphs").dim()
                }
            }
            .disabled(!ImageDemoHelpers.usesGlyphCount(settings.charset))
            .padding(.leading, 2)
            // The blocks charset's discrete size, under the blocks radio.
            RadioButtonGroup(selection: $settings.blockStyleIndex, orientation: .horizontal) {
                RadioButtonItem(0, ImageDemoHelpers.blockStyleLabel(0))
                RadioButtonItem(1, ImageDemoHelpers.blockStyleLabel(1))
                RadioButtonItem(2, ImageDemoHelpers.blockStyleLabel(2))
                RadioButtonItem(3, ImageDemoHelpers.blockStyleLabel(3))
            }
            .disabled(
                !ImageDemoHelpers.usesBlockStyle(
                    settings.charset, shapeAware: settings.shapeAware))
            .padding(.leading, 2)
            rampField
                .disabled(settings.charset != .custom)
                .padding(.leading, 2)
            // Shape-awareness: match glyphs by their measured in-cell ink
            // distribution instead of overall luminance. Applies to every
            // charset except a custom ramp.
            Toggle("component.imageControls.shapeAware", isOn: $settings.shapeAware)
                .disabled(!ImageDemoHelpers.usesShape(settings.charset))
            // Edge tracing applies to the shape-aware ascii/unicode charsets:
            // cells on a clean light/dark boundary draw as directional line
            // glyphs; the threshold picks how strong a gradient qualifies.
            Toggle("component.imageControls.edgeLines", isOn: $settings.edgeLines)
                .disabled(
                    !ImageDemoHelpers.usesEdgeTracing(
                        settings.charset, shapeAware: settings.shapeAware))
            HStack(spacing: 1) {
                Text("component.imageControls.edgeThreshold").dim()
                // The slider's own `%`-of-range read-out would mislead beside
                // the raw threshold value shown after it.
                Slider(value: $settings.edgeThreshold, in: 0.3...2.0, step: 0.1)
                    .sliderShowsValue(false)
                    .frame(width: Self.sliderWidth)
                Text(String(format: "%.1f", settings.edgeThreshold)).dim()
            }
            .disabled(
                !settings.edgeLines
                    || !ImageDemoHelpers.usesEdgeTracing(
                        settings.charset, shapeAware: settings.shapeAware))
            .padding(.leading, 2)
        }
    }

    // MARK: - Colour

    @ViewBuilder private var colour: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("component.imageControls.colour")
            RadioButtonGroup(selection: $settings.colour) {
                RadioButtonItem(ImageDemoSettings.ColourMode.trueColor, "component.imageControls.trueColour")
                RadioButtonItem(ImageDemoSettings.ColourMode.ansi256, "component.imageControls.colours256")
                RadioButtonItem(ImageDemoSettings.ColourMode.grayscale, "component.imageControls.greyscale")
                RadioButtonItem(ImageDemoSettings.ColourMode.mono, "component.imageControls.mono")
                RadioButtonItem(ImageDemoSettings.ColourMode.themed, "component.imageControls.themed")
                RadioButtonItem(ImageDemoSettings.ColourMode.greys, "component.imageControls.greys")
                RadioButtonItem(ImageDemoSettings.ColourMode.sampled, "component.imageControls.sampled")
            }
            // Under "Greys" and "Sampled", in that order: each names how many.
            counted(
                "component.imageControls.levels", value: $settings.greyLevels, in: 2...16,
                enabled: settings.colour == .greys)
            counted(
                "component.imageControls.colours", value: $settings.sampledColours, in: 2...64,
                enabled: settings.colour == .sampled)
            // Supersampling applies to every non-shape renderer: each sample
            // (cell tone, half-cell pixel, braille dot) becomes an N×N area
            // average.
            Text("component.imageControls.supersampling").dim()
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
            .padding(.leading, 2)
            Toggle("component.imageControls.dithering", isOn: $settings.dithering)
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
                RadioButtonItem(ImageDemoSettings.Tone.negative, "component.imageControls.toneNegative")
                RadioButtonItem(ImageDemoSettings.Tone.accent, "component.imageControls.toneAccent")
                RadioButtonItem(ImageDemoSettings.Tone.duotone, "component.imageControls.toneDuotone")
                RadioButtonItem(ImageDemoSettings.Tone.lut, "component.imageControls.toneLUT")
            }
            // Duotone's two ends, under its own radio button.
            VStack(alignment: .leading, spacing: 0) {
                ColorPicker("component.imageControls.shadows", selection: $settings.duotoneShadow)
                    .colorPickerChannels(.hidden)
                    .colorPickerLabelWidth(10)
                ColorPicker(
                    "component.imageControls.highlights", selection: $settings.duotoneHighlight
                )
                .colorPickerChannels(.hidden)
                .colorPickerLabelWidth(10)
            }
            .disabled(settings.tone != .duotone)
            .padding(.leading, 2)
            // …and the LUT's, under its own: the ramp as it stands, and the way
            // in to editing it.
            HStack(spacing: 1) {
                lutPreview
                Button("component.imageControls.lutEdit") { editingLUT = true }
            }
            .disabled(settings.tone != .lut)
            .padding(.leading, 2)
        }
    }

    /// The LUT's ramp, drawn as it will be applied: the stops interpolated
    /// across the tone range, which is exactly what the curve does to the
    /// image. Not a row of swatches — that would show the stops and hide the
    /// thing they define.
    private var lutPreview: some View {
        let width = 12
        return HStack(spacing: 0) {
            ForEach(0..<width, id: \.self) { cell in
                Text(verbatim: "\u{2588}")
                    .foregroundStyle(
                        Color.interpolate(
                            stops: settings.lutStops,
                            phase: Double(cell) / Double(max(1, width - 1))))
            }
        }
    }

    // MARK: - Pieces

    private func heading(_ key: LocalizedStringKey) -> some View {
        Text(key).bold().foregroundStyle(.palette.accent)
    }

    /// A "how many" row: a slider and the number it is at, indented under the
    /// option it belongs to and inert while another option is chosen.
    private func counted(
        _ key: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>, enabled: Bool
    ) -> some View {
        HStack(spacing: 1) {
            Text(key).dim()
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            .sliderShowsValue(false)
            .frame(width: Self.sliderWidth)
            Text(verbatim: "\(value.wrappedValue)").dim()
        }
        .disabled(!enabled)
        .padding(.leading, 2)
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
        VStack(alignment: .leading, spacing: 0) {
            Text("component.imageControls.customRamp").dim()
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
}
