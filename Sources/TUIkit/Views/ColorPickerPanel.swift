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
        case greyscale = "Greyscale"
        case named = "Named"
        case webSafe = "Web Safe"
        case crayons = "Crayons"

        /// The channels of this colour model: a one-letter label and the
        /// slider's upper bound (the lower bound is always 0). Empty for tabs
        /// that aren't channel editors (``semantic``, ``palette256``).
        var channels: [(label: String, upperBound: Double)] {
            switch self {
            case .rgb: [("R", 255), ("G", 255), ("B", 255)]
            case .hsl: [("H", 360), ("S", 100), ("L", 100)]
            case .hsb: [("H", 360), ("S", 100), ("B", 100)]
            case .cmyk: [("C", 100), ("M", 100), ("Y", 100), ("K", 100)]
            case .semantic, .palette256, .greyscale, .named, .webSafe, .crayons: []
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
                    Tab("RGB", value: Mode.rgb) { _ChannelEditor(mode: .rgb, selection: selection) }
                    Tab("HSL", value: Mode.hsl) { _ChannelEditor(mode: .hsl, selection: selection) }
                    Tab("HSB", value: Mode.hsb) { _ChannelEditor(mode: .hsb, selection: selection) }
                    Tab("CMYK", value: Mode.cmyk) { _ChannelEditor(mode: .cmyk, selection: selection) }
                    Tab("Semantic", value: Mode.semantic) { semanticEditor }
                    Tab("256 (Xterm)", value: Mode.palette256) { _Palette256Editor(selection: selection) }
                    Tab("Greyscale", value: Mode.greyscale) {
                        _SwatchGridCore(entries: SwatchPalettes.greyscale, columns: 8, selection: selection)
                    }
                    Tab("Named", value: Mode.named) {
                        _NamedSwatchGrid(entries: SwatchPalettes.cssNamed, columns: 18, selection: selection)
                    }
                    Tab("Web Safe", value: Mode.webSafe) {
                        _SwatchGridCore(entries: SwatchPalettes.webSafe, columns: 18, selection: selection)
                    }
                    Tab("Crayons", value: Mode.crayons) {
                        _NamedSwatchGrid(entries: SwatchPalettes.crayons, columns: 8, selection: selection)
                    }
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
        return HStack(alignment: .center, spacing: 2) {
            // A large solid block of the current colour (10 wide × 5 tall).
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    Text(String(repeating: "█", count: 10)).foregroundStyle(selection.wrappedValue)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.hexString(components)).foregroundStyle(.palette.foreground)
                Text(Self.rgbString(components)).foregroundStyle(.palette.foregroundTertiary)
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

    /// Parses a typed/pasted channel value: keeps the digits, clamps to `range`
    /// (empty → the lower bound; out-of-range → the nearer bound). Pure; tested.
    static func channelValue(parsing text: String, into range: ClosedRange<Double>) -> Double {
        let digits = text.filter(\.isNumber)
        let parsed = digits.isEmpty ? range.lowerBound : (Double(digits) ?? range.upperBound)
        return max(range.lowerBound, min(range.upperBound, parsed))
    }

    // MARK: - Channel conversions
    //
    // The stateful ``_ChannelEditor`` seeds its sliders from the current colour
    // with ``channelValue(of:mode:index:)`` and pushes edits back through
    // ``color(from:mode:)`` — a one-way build from the *full* channel set. That
    // avoids the stateless round-trip's re-canonicalisation: an over-determined
    // model (CMYK, or HSL/HSB hue on a desaturated colour) keeps the exact
    // values you typed instead of being re-derived from the resulting RGB.

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
        case .semantic, .palette256, .greyscale, .named, .webSafe, .crayons:
            return 0  // no numeric channels; these tabs edit selection directly
        }
    }

    /// Builds a colour directly from a full set of `mode` channel values — the
    /// one-way push used by ``_ChannelEditor``. Unlike a read-modify-write
    /// round-trip it does not read any channel back out of the current colour,
    /// so over-determined models keep the exact values supplied: CMYK with
    /// `K=100` still carries its C/M/Y, equal C/M/Y don't collapse into `K`, and
    /// HSL/HSB hue survives a zero-saturation colour. Missing entries read as 0.
    /// Pure; unit-tested.
    static func color(from channels: [Double], mode: Mode) -> Color {
        func at(_ i: Int) -> Double { channels.indices.contains(i) ? channels[i] : 0 }
        switch mode {
        case .rgb:
            let byte = { (v: Double) in UInt8(max(0, min(255, v.isFinite ? v.rounded() : 0))) }
            return .rgb(byte(at(0)), byte(at(1)), byte(at(2)))
        case .hsl:
            return .hsl(at(0), at(1), at(2))
        case .hsb:
            return .hsb(at(0), at(1), at(2))
        case .cmyk:
            return .cmyk(at(0), at(1), at(2), at(3))
        case .semantic, .palette256, .greyscale, .named, .webSafe, .crayons:
            return .rgb(0, 0, 0)  // channelless tabs edit selection directly; unreachable here
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

// MARK: - Stateful channel editor

/// The sliders + editable read-outs for one colour model's channels.
///
/// Colour models other than RGB are *over-determined*: many channel
/// combinations map to the same RGB (any CMYK with `K=100` is black; a grey is
/// `K` alone or equal `C/M/Y`; hue is undefined on a desaturated colour).
/// Reading the channels back out of the stored colour on every edit therefore
/// re-canonicalises them — raising `K` zeroes `C/M/Y`, adjusting one of `C/M/Y`
/// shifts the derived `K` instead, and hue is lost. To let each channel be
/// edited independently this view holds the channel values in `@State` and
/// converts them to a colour one-way (``ColorPickerPanel/color(from:mode:)``);
/// it re-seeds from `selection` only when the colour changes from *outside* (a
/// different tab or the host app), detected by comparing against the colour it
/// last produced.
///
/// Per-tab `@State` lifecycle does the rest: ``TabView`` renders each tab under
/// its own identity, so leaving a tab prunes this editor's state and re-entering
/// re-seeds the canonical channels for the current colour.
private struct _ChannelEditor: View {
    let mode: ColorPickerPanel.Mode
    let selection: Binding<Color>

    // Two @State, in declaration order: [0] the live channel values, [1] the
    // colour we last pushed — so our own write-back isn't mistaken for an
    // external change by the `onChange` below.
    @State private var channels: [Double]
    @State private var lastProduced: Color

    init(mode: ColorPickerPanel.Mode, selection: Binding<Color>) {
        self.mode = mode
        self.selection = selection
        let color = selection.wrappedValue
        _channels = State(wrappedValue: mode.channels.indices.map {
            ColorPickerPanel.channelValue(of: color, mode: mode, index: $0)
        })
        _lastProduced = State(wrappedValue: color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(mode.channels.enumerated()), id: \.offset) { index, spec in
                channelRow(spec.label, channelBinding(index), 0...spec.upperBound)
            }
        }
        .onChange(of: selection.wrappedValue) { _, new in
            // Re-seed only on an external change — never on our own write-back,
            // which would re-canonicalise the channels and undo the whole point.
            guard new != lastProduced else { return }
            channels = mode.channels.indices.map {
                ColorPickerPanel.channelValue(of: new, mode: mode, index: $0)
            }
            lastProduced = new
        }
    }

    /// A `Double` binding onto channel `index`: reads/writes the held `@State`
    /// and, on write, pushes the *full* channel set to `selection`.
    private func channelBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { channels.indices.contains(index) ? channels[index] : 0 },
            set: { newValue in
                guard channels.indices.contains(index) else { return }
                channels[index] = newValue
                let color = ColorPickerPanel.color(from: channels, mode: mode)
                lastProduced = color
                selection.wrappedValue = color
            })
    }

    /// One labelled channel row: name, slider, editable numeric read-out.
    private func channelRow(
        _ label: String,
        _ binding: Binding<Double>,
        _ range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 1) {
            Text(label)
                .frame(width: 2, alignment: .trailing)
                .foregroundStyle(.palette.foregroundTertiary)
            Slider(value: binding, in: range, step: 1).frame(width: 22)
            // Editable read-out: type or paste an exact value, kept in sync with
            // the slider (both drive the same binding). A fixed width keeps the
            // panel sized-to-fit; 12 is the field's natural minimum, so both end
            // caps render with room to type/select.
            TextField("", text: channelText(binding, in: range)).frame(width: 12)
        }
    }

    /// A `String` binding over a numeric channel: shows the integer value, and on
    /// edit parses the digits and clamps to `range`.
    private func channelText(_ value: Binding<Double>, in range: ClosedRange<Double>) -> Binding<String> {
        Binding(
            get: {
                let v = value.wrappedValue
                return String(Int((v.isFinite ? v : 0).rounded()))
            },
            set: { value.wrappedValue = ColorPickerPanel.channelValue(parsing: $0, into: range) })
    }
}
