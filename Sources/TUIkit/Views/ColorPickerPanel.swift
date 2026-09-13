//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    private let supportsOpacity: Bool
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

    /// Creates a colour-picker panel with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The title is not defaulted in this overload, or
    /// the two would be ambiguous where it is omitted.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the dialog title.
    ///   - selection: The colour to edit. Rewritten live on every change;
    ///     restored to the opening value on Cancel / `Esc`.
    ///   - supportsOpacity: Whether the panel offers an opacity row. SwiftUI's
    ///     default, `true`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Color>,
        supportsOpacity: Bool = true,
        isPresented: Binding<Bool>
    ) {
        self.init(
            titleKey.localized, selection: selection, supportsOpacity: supportsOpacity,
            isPresented: isPresented)
    }

    /// Creates a colour-picker panel titled as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    /// A generic parameter cannot carry a default, so the defaulted title lives
    /// in ``init(selection:supportsOpacity:isPresented:)`` instead of here.
    ///
    /// - Parameters:
    ///   - title: The dialog title.
    ///   - selection: The colour to edit. Rewritten live on every change;
    ///     restored to the opening value on Cancel / `Esc`.
    ///   - supportsOpacity: Whether the panel offers an opacity row. SwiftUI's
    ///     default, `true`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Color>,
        supportsOpacity: Bool = true,
        isPresented: Binding<Bool>
    ) {
        self.title = String(title)
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.isPresented = isPresented
    }

    /// Creates a colour-picker panel titled `"Colour"`.
    ///
    /// The title's default lives here rather than on either titled overload:
    /// neither of those can carry it — a generic parameter cannot have a
    /// default, and defaulting the ``LocalizedStringKey`` one would make the
    /// two ambiguous wherever the title is omitted. The forwarded default is
    /// written `as String` so it stays on the disfavoured side: a bare literal
    /// would bind to the key overload and go looking for a `"Colour"` key that
    /// is in no table.
    ///
    /// - Parameters:
    ///   - selection: The colour to edit. Rewritten live on every change;
    ///     restored to the opening value on Cancel / `Esc`.
    ///   - supportsOpacity: Whether the panel offers an opacity row. SwiftUI's
    ///     default, `true`.
    ///   - isPresented: Bound to the presenting `.modal`; Done and Cancel set
    ///     it false.
    public init(
        selection: Binding<Color>,
        supportsOpacity: Bool = true,
        isPresented: Binding<Bool>
    ) {
        self.init(
            "Colour" as String, selection: selection, supportsOpacity: supportsOpacity,
            isPresented: isPresented)
    }

    public var body: some View {
        _EditorPanelChrome(title: title, edited: selection, isPresented: isPresented) {
            _ColorPickerBody(selection: selection, supportsOpacity: supportsOpacity)
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

    /// Whether the opacity row is offered. Defaulted on, because a gradient stop —
    /// the other editor that embeds this body — is exactly the place a translucent
    /// colour is worth editing (see `Documentation/Opacity as composition.md` §15).
    /// The tone-curve editor turns it off: a tone curve keeps each pixel's own alpha
    /// and ignores its stops'.
    var supportsOpacity: Bool = true

    private typealias Mode = ColorPickerPanel.Mode

    /// ``selection``, with every write keeping the alpha the colour already had.
    ///
    /// Each model tab rewrites the colour outright — `.rgb(…)`, `.hsl(…)`, a
    /// swatch's entry, a parsed hex — and every one of those spellings is opaque,
    /// so before this the first nudge of any channel silently deleted a
    /// translucent binding's alpha. One transform at the top rather than a repair
    /// at each of the six write sites, which is also the only shape in which a
    /// seventh cannot be forgotten.
    ///
    /// The division of labour it states: **the model tabs edit the colour, the
    /// opacity row edits the opacity.** That is why the semantic tab snapshots a
    /// palette role's RGB and leaves your alpha alone even when the role itself is
    /// translucent — picking a hue is not a statement about transparency.
    /// The two bindings, for the test that asserts they are orthogonal.
    var colorOnlyForTests: Binding<Color> { colorOnly }
    var alphaBindingForTests: Binding<Double> { alphaBinding }

    private var colorOnly: Binding<Color> {
        Binding(
            get: { selection.wrappedValue },
            set: { new in
                var carried = new
                carried.alpha = selection.wrappedValue.alpha
                selection.wrappedValue = carried
            })
    }

    /// A 0–255 binding onto ``selection``'s alpha alone.
    ///
    /// No held state, unlike ``_ChannelEditor``'s channels: alpha is the one
    /// channel here that is not over-determined, so reading it back out of the
    /// colour is exact and there is nothing to re-canonicalise.
    private var alphaBinding: Binding<Double> {
        Binding(
            get: { Double(selection.wrappedValue.alpha) },
            set: { new in
                var faded = selection.wrappedValue
                faded.alpha = UInt8(max(0, min(255, new.isFinite ? new.rounded() : 255)))
                selection.wrappedValue = faded
            })
    }

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
                    Tab("RGB", value: Mode.rgb) { tabBody { _ChannelEditor(mode: .rgb, selection: colorOnly) } }
                    Tab("HSL", value: Mode.hsl) { tabBody { _ChannelEditor(mode: .hsl, selection: colorOnly) } }
                    Tab("HSB", value: Mode.hsb) { tabBody { _ChannelEditor(mode: .hsb, selection: colorOnly) } }
                    Tab("CMYK", value: Mode.cmyk) { tabBody { _ChannelEditor(mode: .cmyk, selection: colorOnly) } }
                    Tab("Semantic", value: Mode.semantic) { tabBody { semanticEditor } }
                    Tab("256 (Xterm)", value: Mode.palette256) { tabBody { _Palette256Editor(selection: colorOnly) } }
                    Tab("Greyscale", value: Mode.greyscale) {
                        // Only 8 columns, so there's room for larger 4×2 swatches.
                        tabBody {
                            _SwatchGridCore(
                                entries: SwatchPalettes.greyscale, columns: 8,
                                selection: colorOnly, cellWidth: 4, cellHeight: 2)
                        }
                    }
                    Tab("Named", value: Mode.named) {
                        tabBody { _NamedSwatchGrid(entries: SwatchPalettes.cssNamed, columns: 18, selection: colorOnly) }
                    }
                    Tab("Web Safe", value: Mode.webSafe) {
                        tabBody {
                            _SwatchGridCore(
                                entries: SwatchPalettes.webSafe, columns: 18,
                                selection: colorOnly, exactMatchOnly: true)
                        }
                    }
                    Tab("Crayons", value: Mode.crayons) {
                        // 8 columns like Greyscale — room for larger 4×2 swatches.
                        tabBody {
                            _NamedSwatchGrid(
                                entries: SwatchPalettes.crayons, columns: 8,
                                selection: colorOnly, exactMatchOnly: true,
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
                // tall swatch grids; the dialog body scrolls if it must), so
                // size the panel to the ACTIVE tab — the tallest-tab default
                // would pad the slim slider tabs out to the 256-grid's height.
                .tabViewContentSizing(.activeTab)
                if supportsOpacity { opacityRow }
            }
    }

    /// The opacity row — one channel, below the tabs rather than inside any of
    /// them.
    ///
    /// Outside the `TabView` because alpha belongs to no colour model: RGB, HSL,
    /// HSB and CMYK each describe a colour and none of them describes how much of
    /// it there is. A fifth entry in ``ColorPickerPanel/Mode/channels`` would have
    /// put a different opacity slider on four tabs, each with its own `@State`,
    /// and made the value appear to change when you switched tab.
    ///
    /// What it edits is genuinely visible, which is the part a terminal might not
    /// have earned: the preview block above states its colour's opaque spelling
    /// and claims an ``OpacityRegion`` over its own cells, so dragging this fades
    /// the block toward the panel actually behind it. No checkerboard, no assumed
    /// backdrop — see `Documentation/Opacity as composition.md` §27.
    private var opacityRow: some View {
        HStack(spacing: 1) {
            Text("Opacity").foregroundStyle(.palette.foregroundTertiary)
            _ChannelRow(label: "A", idBase: "alpha", binding: alphaBinding, range: 0...255)
        }
    }

    /// A tab's content, unwrapped.
    ///
    /// This used to add a per-tab `ScrollView`, because nothing else in the
    /// dialog could scroll — the body was clipped, so a scrollable tab was the
    /// only way to reach a tall grid at all. It only worked because `TabView`
    /// measures each tab with an explicit unbounded proposal, which is why
    /// scrolling existed inside a tab and nowhere else.
    ///
    /// The dialog now scrolls its own body with the title and footer pinned, so
    /// an inner ScrollView would only add a nested wheel-chaining boundary and a
    /// second focus stop for content that already scrolls. Kept as a seam so the
    /// call sites read unchanged.
    @ViewBuilder
    private func tabBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
    }

    // MARK: Preview

    /// A large live swatch plus an editable hex field and the `rgb(…)` read-out.
    /// A semantic selection is resolved against the palette so the read-outs show
    /// its concrete value rather than blanks.
    private var previewRow: some View {
        let resolved = selection.wrappedValue.resolve(with: palette)
        let components = resolved.rgbComponents
        return HStack(alignment: .center, spacing: 2) {
            // A large solid block of the current colour (10 wide × 5 tall).
            VStack(spacing: 0) {
                // Each row IS its colour, not an index into one. `ForEach`'s
                // value memo keys on the element, so `ForEach(0..<5)` with the
                // colour read from OUTSIDE the closure serves the buffer it
                // built the first time, whatever the sliders have done since —
                // the documented hole, and the same shape as
                // `SpinnersPage.catalogueColumns`. The preview stayed on the
                // colour the dialog opened with until a tab switch rebuilt the
                // subtree, which is exactly what "live editing" must not do.
                ForEach(Self.previewRows(resolved)) { row in
                    Text(String(repeating: "█", count: 10))
                        .foregroundStyle(row.color)
                        .background(row.color)
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
                    // Through `colorOnly`: `#RRGGBB` names a colour and says
                    // nothing about opacity, so typing one must not silently
                    // make a half-transparent colour solid.
                    commit: { if let color = Color.hex($0) { colorOnly.wrappedValue = color } })
                Text(ColorPickerPanel.rgbString(components))
                    .foregroundStyle(.palette.foregroundTertiary)
            }
        }
    }

    /// One line of the preview block: the colour it paints, and which line it
    /// is (so five of them are five rows rather than one).
    private struct PreviewRow: Identifiable, Equatable {
        let line: Int
        let color: Color

        /// The row is what its id says it is — which is what lets the value
        /// memo tell a changed row from an unchanged one.
        var id: String { "\(line)|\(color)" }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    /// The preview block's rows: ten cells wide, five tall, all one colour.
    ///
    /// Both the glyph and the background are the colour: the █ keeps it visible
    /// in terminals that do not paint a background behind spaces, and the
    /// matching background fills any hairline gaps a font leaves between the
    /// block glyphs — so it is solid either way.
    private static func previewRows(_ color: Color) -> [PreviewRow] {
        (0..<5).map { PreviewRow(line: $0, color: color) }
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
        let name = LocalizationService.shared.string(for: name)
        HStack(spacing: 1) {
            Text("██").foregroundStyle(color)
            if isSelected {
                Button("● " + name) { colorOnly.wrappedValue = concrete }.buttonStyle(.primary)
            } else {
                Button("  " + name) { colorOnly.wrappedValue = concrete }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Pure helpers (parsing, conversions, read-outs)

extension ColorPickerPanel {
    /// The palette roles offered on the semantic tab (see
    /// ``_ColorPickerBody``'s semantic editor for why selections snapshot the
    /// concrete colour rather than the semantic reference).
    ///
    /// The names are localization KEYS, resolved where the row is built: a
    /// `String`-typed name could only ever bind the verbatim initializer, so
    /// the nine roles read in English in every language.
    static let semanticColors: [(name: String, color: Color)] = [
        ("label.foreground", .palette.foreground),
        ("label.secondary", .palette.foregroundSecondary),
        ("label.accent", .palette.accent),
        ("label.success", .palette.success),
        ("label.warning", .palette.warning),
        ("label.error", .palette.error),
        ("label.info", .palette.info),
        ("label.border", .palette.border),
        ("label.background", .palette.background),
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
                // Structural focus IDs (model + channel index + representation):
                // stable, unique within the panel, never derived from user data.
                _ChannelRow(
                    label: spec.label, idBase: "\(mode.rawValue)-\(index)",
                    binding: channelBinding(index), range: 0...spec.upperBound)
            }
        }
        .onChange(of: selection.wrappedValue) { _, new in
            // Re-seed only on an external change — never on our own write-back,
            // which would re-canonicalise the channels and undo the whole point.
            //
            // Compared by OPAQUE SPELLING, so a change that moved only the alpha
            // is not one: opacity is edited in its own row, none of these channels
            // describes it, and re-seeding for it would re-canonicalise an
            // over-determined model on every drag of the opacity slider — CMYK's
            // C/M/Y snapping away under a raised K, a desaturated colour losing
            // its hue. Exactly the class of bug the held channels exist to
            // prevent, arriving through a control that has nothing to do with them.
            guard new.opaqueSpelling != lastProduced.opaqueSpelling else {
                lastProduced = new
                return
            }
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
                selection.wrappedValue = ColorPickerPanel.color(from: channels, mode: mode)
                // Read BACK, rather than recording what was sent: `selection` is
                // the alpha-preserving transform, so what lands is not what was
                // written, and a `lastProduced` holding the pre-transform value
                // would read every one of our own edits as external.
                lastProduced = selection.wrappedValue
            })
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
/// Internal rather than file-private since ``_ChannelRow`` moved out: the row and
/// the field it is built from are one control split across two files, and the
/// only alternative was to keep a 100-line duplicate of the row so that a
/// `private` could stand.
struct _EditableValueField: View {
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
