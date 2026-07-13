//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageRenderingControls.swift
//
//  The rendering-knob control strip shared by the image demo pages,
//  exposing the FUNDAMENTAL options directly rather than a list of
//  pre-combined modes: the charset (ascii / blocks / unicode / custom),
//  its size (glyph count, or block resolution), shape-awareness, the
//  colour and supersampling knobs, the shape-mode edge tracing (line
//  glyphs on/off + Sobel threshold), and a free-text custom brightness
//  ramp offered as a combo field with persistent recents.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Live controls for every image-rendering knob, driving the owning page's
/// state. The page applies the corresponding modifiers — see
/// ``ImageDemoHelpers/effectiveCharSet(charsetIndex:glyphCount:blockResolutionIndex:customRamp:)``
/// and friends.
struct ImageRenderingControls: View {
    @Binding var charsetIndex: Int

    /// How many glyphs the sizeable charsets use: 0 = the full repertoire.
    @Binding var glyphCount: Int

    /// Which ``ImageDemoHelpers/blockResolutions`` entry the blocks charset
    /// uses (while not shape-aware).
    @Binding var blockResolutionIndex: Int

    /// Whether glyphs are matched by in-cell ink distribution (shape) rather
    /// than mapped from cell luminance.
    @Binding var shapeAware: Bool

    @Binding var colorModeIndex: Int

    /// Supersampling factor: 0 = the default, 1–4 explicit.
    @Binding var supersampling: Int

    /// Whether shape-aware cells may draw directional line glyphs at edges.
    @Binding var edgeLines: Bool

    /// The Sobel gradient threshold for edge cells (used while ``edgeLines``).
    @Binding var edgeThreshold: Double

    /// A custom brightness ramp, darkest-pixel character first; applies
    /// while the custom charset is selected.
    @Binding var customRamp: String

    /// Recently used custom ramps, persisted app-wide (most recent first).
    @AppStorage("imageDemo.recentRamps") private var recentRampsJSON = "[]"

    /// Pre-defined ramps for the combo menu (darkest first, matching the
    /// converter's luminance-ascending mapping).
    private static let ramps = [" .:-=+*#%@", " ░▒▓█", " .oO@", " ._xX#"]

    var body: some View {
        // Each knob is enabled only while the selected configuration
        // actually consumes it, so what applies is always visible at a
        // glance (see ASCIIConverter.convert's dispatch).
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Picker(L("component.imageControls.characters"), selection: $charsetIndex) {
                    ForEach(0..<ImageDemoHelpers.Charset.allCases.count, id: \.self) { index in
                        Text(ImageDemoHelpers.charsetLabel(index)).tag(index)
                    }
                }
                // The blocks charset's discrete size; the other charsets
                // size by glyph count instead.
                Picker(L("component.imageControls.resolution"), selection: $blockResolutionIndex) {
                    ForEach(ImageDemoHelpers.blockResolutions.indices, id: \.self) { index in
                        Text(ImageDemoHelpers.blockResolutionLabel(index)).tag(index)
                    }
                }
                .disabled(
                    !ImageDemoHelpers.usesBlockResolution(
                        charsetIndex: charsetIndex, shapeAware: shapeAware))
                Picker(L("component.imageControls.colour"), selection: $colorModeIndex) {
                    ForEach(ImageDemoHelpers.colorModes.indices, id: \.self) { index in
                        Text(ImageDemoHelpers.colorModeLabel(index)).tag(index)
                    }
                }
                // Supersampling applies to every non-shape renderer: each
                // sample (cell tone, half-cell pixel, braille dot) becomes
                // an N×N area average.
                Picker(L("component.imageControls.supersampling"), selection: $supersampling) {
                    Text(L("component.imageControls.auto")).tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)\u{D7}").tag($0) }
                }
                .disabled(
                    !ImageDemoHelpers.usesSupersampling(
                        charsetIndex: charsetIndex, shapeAware: shapeAware))
                rampField
                    .disabled(ImageDemoHelpers.Charset(rawValue: charsetIndex) != .custom)
            }
            HStack(spacing: 2) {
                // Shape-awareness: match glyphs by their measured in-cell
                // ink distribution instead of overall luminance. Applies to
                // every charset except a custom ramp.
                Toggle(L("component.imageControls.shapeAware"), isOn: $shapeAware)
                    .disabled(!ImageDemoHelpers.usesShape(charsetIndex: charsetIndex))
                // Charset size: how many glyphs the ideal subset keeps
                // (0 = the full repertoire). Applies to ascii / unicode.
                Stepper(
                    L("component.imageControls.glyphs"), value: $glyphCount,
                    in: 0...200
                )
                .disabled(!ImageDemoHelpers.usesGlyphCount(charsetIndex: charsetIndex))
                if glyphCount == 0, ImageDemoHelpers.usesGlyphCount(charsetIndex: charsetIndex) {
                    Text(L("component.imageControls.allGlyphs")).dim()
                }
                // Edge tracing applies to the shape-aware ascii/unicode
                // charsets: cells on a clean light/dark boundary draw as
                // directional line glyphs; the threshold picks how strong a
                // gradient qualifies.
                Toggle(L("component.imageControls.edgeLines"), isOn: $edgeLines)
                    .disabled(
                        !ImageDemoHelpers.usesEdgeTracing(
                            charsetIndex: charsetIndex, shapeAware: shapeAware))
                if edgeLines,
                    ImageDemoHelpers.usesEdgeTracing(
                        charsetIndex: charsetIndex, shapeAware: shapeAware)
                {
                    Text(L("component.imageControls.edgeThreshold")).dim()
                    // The slider's own `%`-of-range read-out would mislead
                    // beside the raw threshold value shown after it.
                    Slider(value: $edgeThreshold, in: 0.3...2.0, step: 0.1)
                        .sliderShowsValue(false)
                        .frame(width: 20)
                    Text(String(format: "%.1f", edgeThreshold)).dim()
                }
            }
        }
    }

    /// The custom-ramp combo field: type any ramp (darkest character first),
    /// or pick a pre-defined or recent one. A genuinely custom ramp is
    /// recorded on Enter and when the field loses focus (it applies live, so
    /// tabbing away must not lose it); the pre-defined options are never
    /// recorded — they already have a home above the divider.
    @ViewBuilder private var rampField: some View {
        let recents = RecentValues.list(from: recentRampsJSON)
            .filter { !Self.ramps.contains($0) }
        let record = {
            guard !Self.ramps.contains(customRamp) else { return }
            recentRampsJSON = RecentValues.recording(customRamp, in: recentRampsJSON)
        }
        // Label above the field, matching the pickers' label-above shape.
        VStack(alignment: .leading, spacing: 0) {
            Text(L("component.imageControls.customRamp")).dim()
            TextField(L("component.imageControls.customRamp"), text: $customRamp)
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
