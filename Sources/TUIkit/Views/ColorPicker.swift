//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorPicker.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Color Picker

/// A control for editing an RGB ``Color``.
///
/// Mirrors SwiftUI's `ColorPicker(_:selection:)` signature, and its two halves:
/// the swatch **opens the full colour editor** — SwiftUI's platform colour
/// panel, here ``ColorPickerPanel`` as a modal — and, since a terminal row has
/// space SwiftUI's control does not, the rest of the row edits the colour in
/// place: one ``Slider`` per channel (R, G, B, each 0–255). Tab moves focus
/// between the swatch and the channel sliders; the arrow keys adjust the
/// focused channel; Return, Space or a click on the swatch opens the panel.
///
/// `supportsOpacity` adds a fourth channel, `A`, exactly as SwiftUI's does — and
/// like SwiftUI's it defaults to `true`. What a terminal makes of a
/// half-transparent colour is the interesting part: the swatch states the colour's
/// opaque spelling and claims an ``OpacityRegion`` over its own cells, so the
/// alpha is resolved against **whatever is actually behind the swatch on the
/// page**. There is no checkerboard and no assumed backdrop, because the
/// composite knows the real one; see `Documentation/Opacity as composition.md` §27.
///
/// `supportsOpacity: false` withholds the channel *and* draws the swatch opaque —
/// a picker that does not deal in opacity should not display one — but it never
/// rewrites the bound colour's alpha. Editing R, G or B carries the existing alpha
/// through on every path, whatever `supportsOpacity` says: the flag governs what
/// this control *offers*, not what the app's value *is*.
///
/// ``TUIkit/View/colorPickerChannels(_:)`` drops the inline sliders, leaving
/// label and swatch — SwiftUI's own shape, and what a narrow row has space for.
///
/// The swatch shows focus and hover in its centre cell — a bullet, pulsing
/// while focused — rather than by re-colouring itself, because its colour is
/// its content (`_ColorSwatchButtonStyle`).
///
/// ```swift
/// @State var tint: Color = .rgb(80, 160, 255)
/// ColorPicker("Accent", selection: $tint)
/// ```
///
/// The bound `Color` is rewritten as `.rgb(...)` on every edit. A non-RGB input
/// (e.g. an ANSI or 256-palette colour) is read through ``Color/rgbComponents``;
/// a semantic colour has no fixed RGB and is treated as black until edited.
public struct ColorPicker: View {
    private let title: String
    private let selection: Binding<Color>
    private let supportsOpacity: Bool
    private let step: Double

    /// True while the full ``ColorPickerPanel`` is up for this picker.
    @State private var isEditing = false

    /// How wide the label column is — see ``TUIkit/View/colorPickerLabelWidth(_:)``.
    @Environment(\.colorPickerLabelWidth) private var labelWidth
    @Environment(\.labelsVisibility) private var labelsVisibility
    private var labelsHidden: Bool { labelsVisibility == .hidden }

    /// Whether the inline channel sliders are drawn — see
    /// ``TUIkit/View/colorPickerChannels(_:)``.
    @Environment(\.colorPickerChannels) private var channelsVisibility
    private var channelsHidden: Bool { channelsVisibility == .hidden }

    /// Creates a colour picker over an RGB binding, with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the label shown beside the editor.
    ///   - selection: The colour to edit. Rewritten as `.rgb(...)` on each change,
    ///     keeping whatever alpha it already carried.
    ///   - supportsOpacity: Whether the fourth (`A`) channel is offered. SwiftUI's
    ///     default, `true`.
    ///   - step: How much each arrow press moves a channel (default 5 of 255).
    public init(
        _ titleKey: LocalizedStringKey, selection: Binding<Color>,
        supportsOpacity: Bool = true, step: Double = 5
    ) {
        self.init(
            titleKey.localized, selection: selection, supportsOpacity: supportsOpacity, step: step)
    }

    /// Creates a colour picker whose label is displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey`` for why the concrete-`String` spelling does not.
    /// `step` keeps its default: it is `S` that cannot carry one, and `step` is
    /// a plain `Double`.
    ///
    /// - Parameters:
    ///   - title: The label shown beside the editor.
    ///   - selection: The colour to edit. Rewritten as `.rgb(...)` on each change,
    ///     keeping whatever alpha it already carried.
    ///   - supportsOpacity: Whether the fourth (`A`) channel is offered. SwiftUI's
    ///     default, `true`.
    ///   - step: How much each arrow press moves a channel (default 5 of 255).
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, selection: Binding<Color>, supportsOpacity: Bool = true, step: Double = 5
    ) {
        self.title = String(title)
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.step = step
    }

    public var body: some View {
        // Two-column gaps between the swatch and each channel group, so a
        // channel's value field reads as its own ("…102  G ◀…", not "102 G"
        // where the G looks like a suffix of the previous channel's value).
        HStack(spacing: 2) {
            // `.labelsHidden()` drops the whole label COLUMN, width and gap
            // included — the point of `colorPickerLabelWidth` is a shared
            // pillar, and a pillar of hidden captions is just an indent.
            if !labelsHidden {
                Text(title)
                    .frame(width: labelWidth, alignment: .leading)
                    .foregroundStyle(.palette.foregroundSecondary)
            }
            swatch
            if !channelsHidden {
                ForEach(channels, id: \.self) { channel($0) }
            }
        }
    }

    /// The live swatch, and the way into the full editor: a button whose whole
    /// body is the colour, opening ``ColorPickerPanel`` on the same binding.
    /// The panel edits live and restores the opening colour on Cancel or `Esc`,
    /// so the two editors are two views of one value, not two values.
    private var swatch: some View {
        Button("") { isEditing = true }
            // Opaque when there is no alpha channel on offer: a control that
            // withholds the editor should not show the value either, or the one
            // state you cannot reach is the one you can see. The BINDING keeps its
            // alpha — this is about what the swatch draws, not what the app holds.
            .buttonStyle(
                _ColorSwatchButtonStyle(
                    color: supportsOpacity
                        ? selection.wrappedValue : selection.wrappedValue.opaqueSpelling))
            .modal(isPresented: $isEditing) {
                // `title` is already localized (the key overload resolves it in
                // init), so the as-written overload takes it — a `String` is
                // not a literal, so it cannot reach the key one, and a second
                // lookup would search for the resolved text as a key.
                ColorPickerPanel(
                    title, selection: selection, supportsOpacity: supportsOpacity,
                    isPresented: $isEditing)
            }
    }

    /// The channels this picker offers, in order.
    private var channels: [Channel] {
        supportsOpacity ? Channel.allCases : [.red, .green, .blue]
    }

    /// One editable channel of the bound colour, each 0–255.
    ///
    /// An enum rather than the bare indices the three RGB channels used, because
    /// alpha is the case a `default:` arm would have swallowed: the read wrote
    /// `default: components.blue`, so a fourth index would have edited blue.
    private enum Channel: Int, CaseIterable, Hashable {
        case red, green, blue, alpha

        /// The one-letter caption, which is also all the reader has to tell the
        /// channels apart by.
        var label: String {
            switch self {
            case .red: "R"
            case .green: "G"
            case .blue: "B"
            case .alpha: "A"
            }
        }
    }

    /// A labelled slider bound to one channel.
    @ViewBuilder
    private func channel(_ channel: Channel) -> some View {
        let label = channel.label
        let binding = channelBinding(channel)
        // The gaps come from the stack's `spacing`, NOT leading spaces in the
        // texts — Text trims leading whitespace, which is exactly how the old
        // layout ended up reading "102 G" with the G hugging the previous
        // channel's value.
        HStack(spacing: 1) {
            Text(label).foregroundStyle(.palette.foregroundTertiary)
            // The slider's built-in read-out is a percentage; these channels
            // show the raw 0–255 value instead, so the built-in display is
            // off. No fixed frame: the three channels split the available
            // width evenly (Slider is width-flexible), growing finer on wide
            // terminals and compressing — track first, never the arrows —
            // on narrow ones.
            Slider(value: binding, in: 0...255, step: step)
                .sliderShowsValue(false)
            // The value in a fixed-width right-aligned 3-column field
            // ("  0" … "255") — frame alignment, because string padding would
            // be trimmed.
            Text("\(Int(binding.wrappedValue))")
                .frame(width: 3, alignment: .trailing)
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// The channel binding, for the test that drives an edit without a key event.
    func channelBindingForTests(_ channel: ChannelForTests) -> Binding<Double> {
        let resolved: Channel =
            switch channel {
            case .red: .red
            case .green: .green
            case .blue: .blue
            case .alpha: .alpha
            }
        return channelBinding(resolved)
    }

    /// ``Channel`` is private, so a test names its cases through this.
    enum ChannelForTests { case red, green, blue, alpha }

    /// A `Double` binding (0...255) onto one channel of ``selection``, reading the
    /// current components and rewriting the colour as `.rgb`.
    ///
    /// The rewrite CARRIES the existing alpha. `.rgb(r, g, b)` is opaque, so the
    /// three colour channels used to destroy a translucent binding's alpha on the
    /// first arrow press — a picker that could not edit opacity silently deleted
    /// it instead. That is independent of ``supportsOpacity``: withholding the
    /// editor is not licence to overwrite the value.
    private func channelBinding(_ channel: Channel) -> Binding<Double> {
        Binding(
            get: {
                let color = selection.wrappedValue
                guard channel != .alpha else { return Double(color.alpha) }
                let components = color.rgbComponents ?? (0, 0, 0)
                switch channel {
                case .red: return Double(components.red)
                case .green: return Double(components.green)
                default: return Double(components.blue)
                }
            },
            set: { newValue in
                let color = selection.wrappedValue
                let clamped = UInt8(max(0, min(255, newValue.rounded())))
                guard channel != .alpha else {
                    var faded = color
                    faded.alpha = clamped
                    selection.wrappedValue = faded
                    return
                }
                var components = color.rgbComponents ?? (0, 0, 0)
                switch channel {
                case .red: components.red = clamped
                case .green: components.green = clamped
                default: components.blue = clamped
                }
                var rewritten = Color.rgb(components.red, components.green, components.blue)
                rewritten.alpha = color.alpha
                selection.wrappedValue = rewritten
            }
        )
    }
}

// MARK: - Label Width

private struct ColorPickerLabelWidthKey: EnvironmentKey {
    /// Wide enough for the names a single picker usually carries ("Accent",
    /// "Background"), which is what the control was written against.
    static let defaultValue = 18
}

extension EnvironmentValues {
    /// The width of a ``ColorPicker``'s label column. See
    /// ``TUIkit/View/colorPickerLabelWidth(_:)``.
    public var colorPickerLabelWidth: Int {
        get { self[ColorPickerLabelWidthKey.self] }
        set { self[ColorPickerLabelWidthKey.self] = newValue }
    }
}

extension View {
    /// Sets the width of the label column in every ``ColorPicker`` in this view.
    ///
    /// A picker's label sits in a fixed-width column so that a *stack* of them
    /// lines up: swatch under swatch, channel under channel. The default fits
    /// the short names a picker usually carries; widen it for a column of
    /// longer ones, so they neither wrap nor push the editors out of line.
    ///
    /// ```swift
    /// VStack(alignment: .leading, spacing: 0) {
    ///     ForEach(colors) { ColorPicker($0.name, selection: binding(for: $0)) }
    /// }
    /// .colorPickerLabelWidth(20)   // "foregroundQuaternary" fits
    /// ```
    ///
    /// TUI-specific: SwiftUI sizes a picker's label to its text and aligns a
    /// column of them with a `Form` or a `Grid`.
    ///
    /// - Parameter width: The column width in cells.
    public func colorPickerLabelWidth(_ width: Int) -> some View {
        environment(\.colorPickerLabelWidth, width)
    }
}

// MARK: - Inline Channels

private struct ColorPickerChannelsKey: EnvironmentKey {
    /// Shown. A terminal row usually has the space, and editing in place beats
    /// opening a panel for a five-unit nudge.
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether ``ColorPicker`` draws its inline channel sliders. See
    /// ``TUIkit/View/colorPickerChannels(_:)``.
    public var colorPickerChannels: Visibility {
        get { self[ColorPickerChannelsKey.self] }
        set { self[ColorPickerChannelsKey.self] = newValue }
    }
}

extension View {
    /// Shows or hides the inline R/G/B sliders in every ``ColorPicker`` in this
    /// view, leaving the label and the swatch.
    ///
    /// The swatch is a `Button`: it still focuses, still shows hover, and still
    /// opens the full ``ColorPickerPanel`` on Return, Space or a click. So
    /// hiding the channels removes a way to edit, not the ability to.
    ///
    /// Worth doing wherever the sliders are the widest thing on the row and the
    /// colour is not the row's subject — three sliders are some ninety cells,
    /// which is enough to decide a whole page's layout.
    ///
    /// ```swift
    /// ColorPicker("Tint", selection: $tint)
    ///     .colorPickerChannels(.hidden)
    /// ```
    ///
    /// TUI-specific: SwiftUI's control is label-and-swatch, with no inline
    /// channels to hide.
    ///
    /// - Parameter visibility: `.hidden` for the swatch alone; `.visible` or
    ///   `.automatic` for the full row.
    public func colorPickerChannels(_ visibility: Visibility) -> some View {
        environment(\.colorPickerChannels, visibility)
    }
}
