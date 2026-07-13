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
/// as you drag. **Done** keeps the result; **Cancel** — or any other
/// dismissal, `Esc` included — restores the colour the dialog opened with.
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

    /// Per-presentation bookkeeping for Cancel semantics. A REFERENCE type:
    /// the dismissal callback must read the values as they are when it fires,
    /// not as they were when the closure's frame was rendered (a value capture
    /// would miss "Done" setting `applied` in the same action that dismisses).
    @State private var session = Session()

    private final class Session {
        var original: Color?
        var applied = false
    }

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
    ///   - selection: The colour to edit. Rewritten live on every change;
    ///     restored to the opening value on Cancel / `Esc`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
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
        Dialog(title: title, titleColor: .palette.accent, footerAlignment: .center) {
            _ColorPickerBody(selection: selection)
                .onAppear { session.original = selection.wrappedValue }
                .onDisappear {
                    // ANY dismissal that isn't "Done" — Cancel, Esc, the page
                    // going away — restores what the dialog opened with. Live
                    // edits already wrote through `selection`; this is the undo.
                    if !session.applied, let original = session.original {
                        selection.wrappedValue = original
                    }
                }
        } footer: {
            // No leading Spacer: a Spacer is width-flexible, which would make the
            // dialog claim the full available width instead of sizing to its
            // content. The footer sizes to the buttons; the dialog fits its tabs.
            HStack(spacing: 2) {
                Button("Cancel") { isPresented.wrappedValue = false }
                Button("Done") {
                    session.applied = true
                    isPresented.wrappedValue = false
                }
                .buttonStyle(.primary)
            }
        }
    }
}

// MARK: - Embeddable panel body

/// The colour panel's content — live preview plus the model tabs — free of
/// dialog chrome, so it can be embedded inside other editors (the
/// ``GradientEditorPanel`` hosts one to edit the selected gradient stop in
/// place, instead of nesting dialogs).
struct _ColorPickerBody: View {
    let selection: Binding<Color>

    private typealias Mode = ColorPickerPanel.Mode

    /// Which tab is currently showing.
    @State private var mode: ColorPickerPanel.Mode = .rgb

    /// Resolves a semantic ``selection`` to concrete RGB for the read-out.
    @Environment(\.palette) private var palette

    var body: some View {
            // Centre the preview and the tab view relative to each other (the tab
            // view is the widest, so the preview centres within it).
            VStack(alignment: .center, spacing: 1) {
                previewRow
                // A TabView gives each model's editor its own identity, so a
                // slider's state can't leak across tabs (e.g. RGB's 0…255 bounds
                // vs HSL's 0…100). The compact style keeps the strip to one row
                // with no padding between the strip and the body; each editor
                // shares the active tab's surface, courtesy of the TabView.
                //
                // Each tab's content is wrapped (via `tabBody`) in a ScrollView so
                // a too-short terminal keeps the tall tabs (256-grid, Named, …)
                // reachable by scrolling rather than clipping them.
                TabView(selection: $mode) {
                    Tab("RGB", value: Mode.rgb) { tabBody { _ChannelEditor(mode: .rgb, selection: selection) } }
                    Tab("HSL", value: Mode.hsl) { tabBody { _ChannelEditor(mode: .hsl, selection: selection) } }
                    Tab("HSB", value: Mode.hsb) { tabBody { _ChannelEditor(mode: .hsb, selection: selection) } }
                    Tab("CMYK", value: Mode.cmyk) { tabBody { _ChannelEditor(mode: .cmyk, selection: selection) } }
                    Tab("Semantic", value: Mode.semantic) { tabBody { semanticEditor } }
                    Tab("256 (Xterm)", value: Mode.palette256) { tabBody { _Palette256Editor(selection: selection) } }
                    Tab("Greyscale", value: Mode.greyscale) {
                        // Only 8 columns, so there's room for larger 4×2 swatches.
                        tabBody {
                            _SwatchGridCore(
                                entries: SwatchPalettes.greyscale, columns: 8,
                                selection: selection, cellWidth: 4, cellHeight: 2)
                        }
                    }
                    Tab("Named", value: Mode.named) {
                        tabBody { _NamedSwatchGrid(entries: SwatchPalettes.cssNamed, columns: 18, selection: selection) }
                    }
                    Tab("Web Safe", value: Mode.webSafe) {
                        tabBody {
                            _SwatchGridCore(
                                entries: SwatchPalettes.webSafe, columns: 18,
                                selection: selection, exactMatchOnly: true)
                        }
                    }
                    Tab("Crayons", value: Mode.crayons) {
                        // 8 columns like Greyscale — room for larger 4×2 swatches.
                        tabBody {
                            _NamedSwatchGrid(
                                entries: SwatchPalettes.crayons, columns: 8,
                                selection: selection, exactMatchOnly: true,
                                cellWidth: 4, cellHeight: 2)
                        }
                    }
                }
                .tabViewStyle(.compact)
                // Many tabs: fold the header strip to the content width so the
                // dialog stays as narrow as its editors rather than being
                // stretched wide by a long single-row strip.
                .tabViewHeaderWrap(.toContentWidth)
                // These tabs have wildly different heights (3 slider rows vs the
                // tall swatch grids, each already scrollable via `tabBody`), so
                // size the panel to the ACTIVE tab — the tallest-tab default
                // would pad the slim slider tabs out to the 256-grid's height.
                .tabViewContentSizing(.activeTab)
            }
    }

    /// Wraps a tab's content in a ScrollView so a too-short terminal can scroll the
    /// tall tabs (the 256-grid, Named, Crayons) into view rather than clipping them.
    @ViewBuilder
    private func tabBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView { content() }
    }

    // MARK: Preview

    /// A large live swatch plus an editable hex field and the `rgb(…)` read-out.
    /// A semantic selection is resolved against the palette so the read-outs show
    /// its concrete value rather than blanks.
    private var previewRow: some View {
        let resolved = selection.wrappedValue.resolve(with: palette)
        let components = resolved.rgbComponents
        return HStack(alignment: .center, spacing: 2) {
            // A large solid block of the current colour (10 wide × 5 tall). Both
            // the glyph and the background are the colour: the █ glyphs keep it
            // visible in terminals that don't paint a background behind spaces,
            // and the matching background fills any hairline gaps a font leaves
            // between the block glyphs — so it's solid either way.
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    Text(String(repeating: "█", count: 10))
                        .foregroundStyle(resolved)
                        .background(resolved)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                // Editable: type/paste a #RRGGBB (or RGB / #RGB) hex to set the
                // colour. Free-form while focused; only valid hex moves the colour.
                _EditableValueField(
                    focusID: "combined-hex", width: 10,
                    format: {
                        ColorPickerPanel.hexString(
                            selection.wrappedValue.resolve(with: palette).rgbComponents)
                    },
                    commit: { if let color = Color.hex($0) { selection.wrappedValue = color } })
                Text(ColorPickerPanel.rgbString(components))
                    .foregroundStyle(.palette.foregroundTertiary)
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
    private var semanticEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ColorPickerPanel.semanticColors, id: \.name) { entry in
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
}

// MARK: - Pure helpers (parsing, conversions, read-outs)

extension ColorPickerPanel {
    /// The palette roles offered on the semantic tab (see
    /// ``_ColorPickerBody``'s semantic editor for why selections snapshot the
    /// concrete colour rather than the semantic reference).
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

    /// Parses a typed/pasted channel value: keeps the digits, clamps to `range`
    /// (empty → the lower bound; out-of-range → the nearer bound). Pure; tested.
    static func channelValue(parsing text: String, into range: ClosedRange<Double>) -> Double {
        let digits = text.filter(\.isNumber)
        let parsed = digits.isEmpty ? range.lowerBound : (Double(digits) ?? range.upperBound)
        return max(range.lowerBound, min(range.upperBound, parsed))
    }

    /// Parses a typed/pasted percentage into a channel value: keeps the digits,
    /// clamps the percentage to 0…100, then scales to `upperBound`. Pure; tested.
    static func channelValue(parsingPercent text: String, upperBound: Double) -> Double {
        let digits = text.filter(\.isNumber)
        let percent = digits.isEmpty ? 0 : (Double(digits) ?? 100)
        return max(0, min(100, percent)) / 100 * upperBound
    }

    /// Parses a typed/pasted hex value (optionally `0x`/`#`-prefixed) into a
    /// 0…255 channel value: keeps the hex digits, clamps. Pure; tested.
    static func channelValue(parsingHex text: String) -> Double {
        var lowered = text.lowercased()
        if lowered.hasPrefix("0x") { lowered.removeFirst(2) }
        let hex = lowered.filter(\.isHexDigit)
        let value = hex.isEmpty ? 0 : (Int(hex, radix: 16) ?? 255)
        return Double(max(0, min(255, value)))
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
                channelRow(spec.label, index, channelBinding(index), 0...spec.upperBound)
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

    /// One labelled channel row: name, slider, then editable read-outs for the
    /// representations that apply to this channel — percentage always (it's the
    /// value the slider used to print, now editable), the raw integer when it
    /// differs from the percentage (i.e. not a 0–100 channel), and hex for the
    /// 0–255 channels. All drive the same binding, so they stay in sync.
    private func channelRow(
        _ label: String,
        _ index: Int,
        _ binding: Binding<Double>,
        _ range: ClosedRange<Double>
    ) -> some View {
        let upper = range.upperBound
        // Structural focus IDs (model + channel index + representation): stable,
        // unique within the panel, and never derived from user data.
        let idBase = "\(mode.rawValue)-\(index)"
        // Adapt to the available width: the preferred one-row layout, falling back
        // to the slider on its own (flexing) row with the value fields stacked
        // beneath — so a constrained editor still works down to ~12 cells. Only
        // the chosen candidate renders, so the shared focus IDs never collide.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 1) {
                channelLabel(label)
                Slider(value: binding, in: range, step: 1).frame(width: 16).sliderShowsValue(false)
                pctField(idBase, binding, upper)
                if upper != 100 { intField(idBase, binding, range, upper) }
                if upper == 255 { hexField(idBase, binding) }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    channelLabel(label)
                    Slider(value: binding, in: range, step: 1).sliderShowsValue(false)
                }
                pctField(idBase, binding, upper)
                if upper != 100 { intField(idBase, binding, range, upper) }
                if upper == 255 { hexField(idBase, binding) }
            }
        }
    }

    /// The channel's one-letter label, right-aligned in a fixed gutter.
    private func channelLabel(_ label: String) -> some View {
        Text(label)
            .frame(width: 2, alignment: .trailing)
            .foregroundStyle(.palette.foregroundTertiary)
    }

    /// Percentage field — always shown (it's the value the slider used to print).
    private func pctField(_ idBase: String, _ binding: Binding<Double>, _ upper: Double) -> some View {
        _EditableValueField(
            focusID: "\(idBase)-pct", width: 7,
            format: { Self.percentString(binding.wrappedValue, upperBound: upper) },
            commit: { raw in
                guard raw.contains(where: \.isNumber) else { return }
                binding.wrappedValue = ColorPickerPanel.channelValue(parsingPercent: raw, upperBound: upper)
            })
    }

    /// Raw integer field — only when it differs from the percentage (a 0–100
    /// channel would just duplicate it). Hue (0–360) gets a ° suffix.
    private func intField(
        _ idBase: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, _ upper: Double
    ) -> some View {
        _EditableValueField(
            focusID: "\(idBase)-int", width: 7,
            format: { Self.integerString(binding.wrappedValue, degrees: upper == 360) },
            commit: { raw in
                guard raw.contains(where: \.isNumber) else { return }
                binding.wrappedValue = ColorPickerPanel.channelValue(parsing: raw, into: range)
            })
    }

    /// Hex field — only for the 0–255 (RGB) channels.
    private func hexField(_ idBase: String, _ binding: Binding<Double>) -> some View {
        _EditableValueField(
            focusID: "\(idBase)-hex", width: 7,
            format: { Self.channelHexString(binding.wrappedValue) },
            commit: { raw in
                guard raw.contains(where: \.isHexDigit) else { return }
                binding.wrappedValue = ColorPickerPanel.channelValue(parsingHex: raw)
            })
    }

    /// `"NN%"` of the channel's range.
    private static func percentString(_ value: Double, upperBound: Double) -> String {
        let pct = upperBound > 0 ? (value.isFinite ? value : 0) / upperBound * 100 : 0
        return "\(Int(pct.rounded()))%"
    }

    /// The raw integer value, with a `°` suffix for a degrees (hue) channel.
    private static func integerString(_ value: Double, degrees: Bool) -> String {
        "\(Int((value.isFinite ? value : 0).rounded()))" + (degrees ? "°" : "")
    }

    /// The value as `"0xNN"` (two upper-case hex digits).
    private static func channelHexString(_ value: Double) -> String {
        let v = Int((value.isFinite ? value : 0).rounded())
        let digits = String(max(0, min(255, v)), radix: 16, uppercase: true)
        return "0x" + (digits.count < 2 ? "0" + digits : digits)
    }
}

// MARK: - Editable value field

/// A text field that edits a value through free-form text.
///
/// While focused it shows exactly what you type — it never reformats the text
/// out from under you — and parses each keystroke to update the model live
/// (best-effort: input with no value characters simply doesn't move the value,
/// via the caller's `commit`). When focus is lost it shows the canonical
/// ``format`` again, "prettying" the entry (e.g. `0xF` → `0x0F`, `9` → `9%`).
///
/// This decouples the *displayed* text from the *stored* value: the previous
/// binding-based fields re-derived the formatted text every render, so a
/// backspace or a digit was immediately reformatted/clamped, fighting the edit
/// (typing `9` into `5%` produced `90%`; backspacing `0xFF` gave `0x0F`).
private struct _EditableValueField: View {
    let focusID: String
    let width: Int
    let format: () -> String
    let commit: (String) -> Void

    @Environment(\.focusManager) private var focusManager
    /// The text being edited. Shown only while focused; seeded from `format()`.
    @State private var draft: String

    init(focusID: String, width: Int, format: @escaping () -> String, commit: @escaping (String) -> Void) {
        self.focusID = focusID
        self.width = width
        self.format = format
        self.commit = commit
        _draft = State(wrappedValue: format())
    }

    var body: some View {
        let focused = focusManager?.isFocused(id: focusID) ?? false
        return TextField("", text: Binding(
            get: { focused ? draft : format() },
            set: { draft = $0; commit($0) }))
            .focusID(focusID)
            .frame(width: width)
            .onChange(of: focused) { _, nowFocused in
                // Re-seed the editing text from the current value on focus-gain,
                // so editing starts from what was displayed.
                if nowFocused { draft = format() }
            }
    }
}
