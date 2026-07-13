//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageRenderingControls.swift
//
//  The rendering-knob control strip shared by the image demo pages: the
//  character-set and colour pickers, the supersampling factor, the shape-mode
//  edge tracing (line glyphs on/off + Sobel threshold), and a free-text
//  custom brightness ramp offered as a combo field with persistent recents.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Live controls for every image-rendering knob, driving the owning page's
/// state. The page applies the corresponding modifiers — see
/// ``ImageDemoHelpers/effectiveCharSet(index:customRamp:)`` and friends.
struct ImageRenderingControls: View {
    @Binding var charSetIndex: Int
    @Binding var colorModeIndex: Int

    /// Supersampling factor: 0 = each character set's own default, 1–4 explicit.
    @Binding var supersampling: Int

    /// Whether shape-mode cells may draw directional line glyphs at edges.
    @Binding var edgeLines: Bool

    /// The Sobel gradient threshold for edge cells (used while ``edgeLines``).
    @Binding var edgeThreshold: Double

    /// A custom brightness ramp, darkest-pixel character first; empty uses
    /// the picked character set instead.
    @Binding var customRamp: String

    /// Recently used custom ramps, persisted app-wide (most recent first).
    @AppStorage("imageDemo.recentRamps") private var recentRampsJSON = "[]"

    /// Pre-defined ramps for the combo menu (darkest first, matching the
    /// converter's luminance-ascending mapping).
    private static let ramps = [" .:-=+*#%@", " ░▒▓█", " .oO@", " ._xX#"]

    var body: some View {
        // Each knob is enabled only while the selected character mode
        // actually consumes it, so what applies is always visible at a
        // glance (see ASCIIConverter.convert's per-set dispatch).
        let selected = ImageDemoHelpers.selectedCharSet(index: charSetIndex)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                // "custom" is an explicit mode in this picker — the ramp
                // field below only applies (and is only enabled) while it is
                // selected, so the active mode is never an implicit override.
                Picker(L("component.imageControls.characters"), selection: $charSetIndex) {
                    ForEach(0...ImageDemoHelpers.charSets.count, id: \.self) { index in
                        Text(ImageDemoHelpers.charSetLabel(index)).tag(index)
                    }
                }
                Picker(L("component.imageControls.colour"), selection: $colorModeIndex) {
                    ForEach(ImageDemoHelpers.colorModes.indices, id: \.self) { index in
                        Text(ImageDemoHelpers.colorModeLabel(index)).tag(index)
                    }
                }
                // Supersampling applies to the brightness-mapping sets
                // (ascii / ascii+ / coarseBlocks / custom ramps).
                Picker(L("component.imageControls.supersampling"), selection: $supersampling) {
                    Text(L("component.imageControls.auto")).tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)\u{D7}").tag($0) }
                }
                .disabled(!ImageDemoHelpers.usesSupersampling(selected))
                rampField
                    .disabled(charSetIndex != ImageDemoHelpers.customCharSetIndex)
            }
            HStack(spacing: 2) {
                // Edge tracing applies to the shape sets (shape / shape+uni /
                // unicode+): cells on a clean light/dark boundary draw as
                // directional line glyphs; the threshold picks how strong a
                // gradient qualifies.
                Toggle(L("component.imageControls.edgeLines"), isOn: $edgeLines)
                    .disabled(!ImageDemoHelpers.usesEdgeTracing(selected))
                if edgeLines && ImageDemoHelpers.usesEdgeTracing(selected) {
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

extension ImageDemoHelpers {
    /// The Characters picker tag for the explicit "custom ramp" mode (one
    /// past the built-in sets).
    static var customCharSetIndex: Int { charSets.count }

    /// The character set the controls currently describe. "Custom" is an
    /// explicit picker choice (no implicit ramp-overrides-picker rule): only
    /// while it is selected does the ramp field apply. An empty custom ramp
    /// falls back to plain ascii so the demo never renders blank.
    static func effectiveCharSet(index: Int, customRamp: String) -> ASCIICharacterSet {
        guard index == customCharSetIndex else { return charSets[min(index, charSets.count - 1)] }
        return customRamp.isEmpty ? .ascii : .customRamp(customRamp)
    }

    /// The set the picker row `index` denotes, for the applicability checks
    /// (the custom mode reports as a custom ramp regardless of its text).
    static func selectedCharSet(index: Int) -> ASCIICharacterSet {
        index == customCharSetIndex
            ? .customRamp("") : charSets[min(index, charSets.count - 1)]
    }

    /// Whether `set` consumes the supersampling factor — the
    /// brightness-mapping renderers (see `ASCIIConverter.convert`).
    static func usesSupersampling(_ set: ASCIICharacterSet) -> Bool {
        switch set {
        case .ascii, .asciiDetailed, .coarseBlocks, .customRamp: return true
        default: return false
        }
    }

    /// Whether `set` consumes the edge-tracing knobs — the shape-aware
    /// renderers.
    static func usesEdgeTracing(_ set: ASCIICharacterSet) -> Bool {
        switch set {
        case .shapeBased, .shapeUnicode, .unicodeDetailed: return true
        default: return false
        }
    }
}
