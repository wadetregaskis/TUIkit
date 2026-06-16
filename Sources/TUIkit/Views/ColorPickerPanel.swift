//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorPickerPanel.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Color Picker Panel

/// The full, modal colour editor — the terminal analogue of macOS's colour
/// panel. Where ``ColorPicker`` is a compact inline editor, this is the rich
/// surface: a live preview, tabs for the RGB / HSL / HSB / CMYK colour models
/// (one labelled ``Slider`` per channel), a tab of the palette's **semantic**
/// roles, and a tab showing the whole **256-colour** terminal palette as a
/// grid.
///
/// Like SwiftUI's colour panel it edits the bound ``Color`` **live** — every
/// change writes straight through `selection`, so a preview elsewhere updates
/// as you drag. "Done" (or `Esc`) dismisses it via `isPresented`.
///
/// TUIkit modals are page-hosted (a `.modal` centres on the space available
/// where it is attached), so present the panel from a full-screen subtree
/// rather than from deep inside a layout:
///
/// ```swift
/// @State private var colour: Color = .rgb(80, 160, 255)
/// @State private var editing = false
///
/// PageRoot {
///     Button("Edit colour…") { editing = true }
/// }
/// .modal(isPresented: $editing) {
///     ColorPickerPanel("Accent", selection: $colour, isPresented: $editing)
/// }
/// ```
///
/// Each channel edit rewrites `selection` as the corresponding concrete colour
/// (`.rgb`, or `.hsl` / `.hsb` / `.cmyk`, which all resolve to RGB). A non-RGB
/// input (an ANSI or 256-palette colour) is read through ``Color/rgbComponents``;
/// a semantic colour has no fixed RGB and reads as black until edited.
public struct ColorPickerPanel: View {
    private let title: String
    private let selection: Binding<Color>
    private let isPresented: Binding<Bool>

    /// Which tab is currently showing.
    @State private var mode: Mode = .rgb

    /// Resolves a semantic ``selection`` to concrete RGB for the read-out.
    @Environment(\.palette) private var palette

    /// The editor tabs. `rawValue` doubles as the tab's button label.
    public enum Mode: String, CaseIterable, Sendable {
        case rgb = "RGB"
        case hsl = "HSL"
        case hsb = "HSB"
        case cmyk = "CMYK"
        case semantic = "Semantic"
        case palette256 = "256"

        /// The channels of this colour model: a one-letter label and the
        /// slider's upper bound (the lower bound is always 0). Empty for tabs
        /// that aren't channel editors (``semantic``, ``palette256``).
        var channels: [(label: String, upperBound: Double)] {
            switch self {
            case .rgb: [("R", 255), ("G", 255), ("B", 255)]
            case .hsl: [("H", 360), ("S", 100), ("L", 100)]
            case .hsb: [("H", 360), ("S", 100), ("B", 100)]
            case .cmyk: [("C", 100), ("M", 100), ("Y", 100), ("K", 100)]
            case .semantic, .palette256: []
            }
        }
    }

    /// Creates a colour-picker panel over a colour binding.
    ///
    /// - Parameters:
    ///   - title: The dialog title (default `"Colour"`).
    ///   - selection: The colour to edit. Rewritten live on every change.
    ///   - isPresented: Bound to the presenting `.modal`; "Done" sets it false.
    public init(
        _ title: String = "Colour",
        selection: Binding<Color>,
        isPresented: Binding<Bool>
    ) {
        self.title = title
        self.selection = selection
        self.isPresented = isPresented
    }

    public var body: some View {
        Dialog(title: title, titleColor: .palette.accent) {
            VStack(alignment: .leading, spacing: 1) {
                previewRow
                // A TabView gives each model's editor its own identity, so a
                // slider's state can't leak across tabs (e.g. RGB's 0…255 bounds
                // vs HSL's 0…100). The compact style keeps the strip to one row.
                TabView(selection: $mode) {
                    Tab("RGB", value: Mode.rgb) { channelEditor(.rgb) }
                    Tab("HSL", value: Mode.hsl) { channelEditor(.hsl) }
                    Tab("HSB", value: Mode.hsb) { channelEditor(.hsb) }
                    Tab("CMYK", value: Mode.cmyk) { channelEditor(.cmyk) }
                    Tab("Semantic", value: Mode.semantic) { semanticEditor }
                    Tab("256 (Xterm)", value: Mode.palette256) { _Color256GridCore(selection: selection) }
                }
                .tabViewStyle(.compact)
            }
        } footer: {
            // No leading Spacer: a Spacer is width-flexible, which would make the
            // dialog claim the full available width instead of sizing to its
            // content. The footer sizes to the button; the dialog fits its tabs.
            Button("Done") { isPresented.wrappedValue = false }
                .buttonStyle(.primary)
        }
    }

    // MARK: Preview

    /// A live swatch plus the colour's hex and `rgb(…)` read-outs. A semantic
    /// selection is resolved against the palette so the read-out shows its
    /// concrete value rather than blanks.
    private var previewRow: some View {
        let components = selection.wrappedValue.resolve(with: palette).rgbComponents
        return HStack(spacing: 1) {
            Text("█████").foregroundStyle(selection.wrappedValue)
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.hexString(components)).foregroundStyle(.palette.foreground)
                Text(Self.rgbString(components)).foregroundStyle(.palette.foregroundTertiary)
            }
        }
    }

    // MARK: Channel editor

    /// The sliders for one colour model's channels. Each tab renders its own,
    /// under the TabView's per-tab identity, so their slider state is isolated.
    @ViewBuilder
    private func channelEditor(_ mode: Mode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(mode.channels.enumerated()), id: \.offset) { index, spec in
                channel(spec.label, channelBinding(index, mode: mode), 0...spec.upperBound)
            }
        }
    }

    // MARK: Semantic tab

    /// The palette roles offered on the semantic tab. Selecting one snapshots
    /// that role's *current concrete colour* into the selection.
    ///
    /// It deliberately does NOT store the `.semantic(role)` reference: when the
    /// edited colour is itself a palette slot (a theme editor), storing a
    /// reference makes the palette return a semantic colour from that slot, and
    /// any consumer that reads `palette.accent` directly (e.g. a button tint)
    /// then hands an unresolved semantic colour to the renderer, which traps. A
    /// palette must always yield concrete colours, so we resolve before storing.
    /// (`Color.palette.accent` already *is* `.semantic(.accent)`, so each entry
    /// still doubles as the swatch.)
    static let semanticColors: [(name: String, color: Color)] = [
        ("Foreground", .palette.foreground),
        ("Secondary", .palette.foregroundSecondary),
        ("Accent", .palette.accent),
        ("Success", .palette.success),
        ("Warning", .palette.warning),
        ("Error", .palette.error),
        ("Info", .palette.info),
        ("Border", .palette.border),
        ("Background", .palette.background),
    ]

    private var semanticEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.semanticColors, id: \.name) { entry in
                semanticRow(entry.name, entry.color)
            }
        }
    }

    /// A swatch + name row that selects the semantic colour; the active role is
    /// marked and uses the primary button style.
    @ViewBuilder
    private func semanticRow(_ name: String, _ color: Color) -> some View {
        // Snapshot the role's current concrete value (resolve before storing) so
        // the selection — which may be a palette slot — never holds a semantic
        // reference. The swatch keeps the semantic colour: it resolves at render
        // and so always shows the role's live colour.
        let concrete = color.resolve(with: palette)
        let isSelected = selection.wrappedValue.resolve(with: palette) == concrete
        HStack(spacing: 1) {
            Text("██").foregroundStyle(color)
            if isSelected {
                Button("● " + name) { selection.wrappedValue = concrete }.buttonStyle(.primary)
            } else {
                Button("  " + name) { selection.wrappedValue = concrete }.buttonStyle(.plain)
            }
        }
    }

    /// One labelled channel row: name, slider, numeric read-out.
    private func channel(
        _ label: String,
        _ binding: Binding<Double>,
        _ range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 1) {
            Text(label)
                .frame(width: 2, alignment: .trailing)
                .foregroundStyle(.palette.foregroundTertiary)
            Slider(value: binding, in: range, step: 1).frame(width: 26)
            Text(String(format: "%4.0f", binding.wrappedValue))
                .frame(width: 4, alignment: .trailing)
                .foregroundStyle(.palette.foregroundSecondary)
        }
    }

    // MARK: - Channel bindings
    //
    // Each binding derives its channel from the current colour and writes the
    // colour back through the matching colour-space constructor. Editing is
    // stateless (the colour is the single source of truth), matching the inline
    // ``ColorPicker``. A consequence of the round-trip: on a fully desaturated
    // colour HSL/HSB hue has no visible effect until saturation is raised.

    /// A `Double` binding onto channel `index` of `mode`, reading from and
    /// writing through ``selection`` via the pure helpers below.
    private func channelBinding(_ index: Int, mode: Mode) -> Binding<Double> {
        Binding(
            get: { Self.channelValue(of: selection.wrappedValue, mode: mode, index: index) },
            set: { selection.wrappedValue = Self.color(bySetting: $0, at: index, mode: mode, of: selection.wrappedValue) })
    }

    /// Reads channel `index` of `color` in `mode`. Pure; unit-tested.
    static func channelValue(of color: Color, mode: Mode, index: Int) -> Double {
        let c = color.rgbComponents ?? (0, 0, 0)
        switch mode {
        case .rgb:
            return Double([c.red, c.green, c.blue][index])
        case .hsl:
            let h = Color.rgbToHSL(red: c.red, green: c.green, blue: c.blue)
            return [h.hue, h.saturation, h.lightness][index]
        case .hsb:
            let h = Color.rgbToHSB(red: c.red, green: c.green, blue: c.blue)
            return [h.hue, h.saturation, h.brightness][index]
        case .cmyk:
            let k = Color.rgbToCMYK(red: c.red, green: c.green, blue: c.blue)
            return [k.cyan, k.magenta, k.yellow, k.black][index]
        case .semantic, .palette256:
            return 0  // no numeric channels; these tabs edit selection directly
        }
    }

    /// Returns `color` with channel `index` of `mode` set to `value`, rewritten
    /// through that model's constructor. Pure; unit-tested.
    static func color(bySetting value: Double, at index: Int, mode: Mode, of color: Color) -> Color {
        let c = color.rgbComponents ?? (0, 0, 0)
        switch mode {
        case .rgb:
            var rgb = [Double(c.red), Double(c.green), Double(c.blue)]
            rgb[index] = value
            let byte = { (v: Double) in UInt8(max(0, min(255, v.rounded()))) }
            return .rgb(byte(rgb[0]), byte(rgb[1]), byte(rgb[2]))
        case .hsl:
            let h = Color.rgbToHSL(red: c.red, green: c.green, blue: c.blue)
            var v = [h.hue, h.saturation, h.lightness]
            v[index] = value
            return .hsl(v[0], v[1], v[2])
        case .hsb:
            let h = Color.rgbToHSB(red: c.red, green: c.green, blue: c.blue)
            var v = [h.hue, h.saturation, h.brightness]
            v[index] = value
            return .hsb(v[0], v[1], v[2])
        case .cmyk:
            let k = Color.rgbToCMYK(red: c.red, green: c.green, blue: c.blue)
            var v = [k.cyan, k.magenta, k.yellow, k.black]
            v[index] = value
            return .cmyk(v[0], v[1], v[2], v[3])
        case .semantic, .palette256:
            return color  // edited via selection directly, not channels
        }
    }

    // MARK: - Read-out formatting

    static func hexString(_ components: (red: UInt8, green: UInt8, blue: UInt8)?) -> String {
        guard let c = components else { return "#------" }
        return String(format: "#%02X%02X%02X", c.red, c.green, c.blue)
    }

    static func rgbString(_ components: (red: UInt8, green: UInt8, blue: UInt8)?) -> String {
        guard let c = components else { return "rgb(—, —, —)" }
        return "rgb(\(c.red), \(c.green), \(c.blue))"
    }
}
