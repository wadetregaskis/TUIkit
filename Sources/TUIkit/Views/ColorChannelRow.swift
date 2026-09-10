//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorChannelRow.swift
//
//  One editable channel of a colour: caption, slider, and the read-outs that
//  are also the way to type a value in.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - One channel's row

/// A labelled slider plus editable read-outs for one channel of a colour.
///
/// Extracted from ``_ColorPickerBody``'s model tabs so the **opacity** row is
/// the same control rather than a second one that looks like it. The two differ
/// in exactly one thing — where the number comes from — and everything a reader
/// can see about a channel row (the two-cell caption gutter, which read-outs
/// appear at which range, the focus-ID scheme) is decided once, here.
///
/// The read-outs shown depend on the range, because a duplicate is worse than a
/// missing one: a 0–100 channel's percentage *is* its value, so it gets no
/// integer field, and only a 0–255 channel gets hex.
struct _ChannelRow: View {
    /// The channel's one-letter caption — "R", "H", "A".
    let label: String

    /// Distinguishes this row's focus IDs from every other row in the panel.
    /// Structural (model name plus channel index, or `"alpha"`), never derived
    /// from user data.
    let idBase: String

    /// The value being edited, in the channel's own units.
    let binding: Binding<Double>

    /// The channel's range. Its upper bound decides which read-outs appear.
    let range: ClosedRange<Double>

    var body: some View {
        let upper = range.upperBound
        // Adapt to the available width: the preferred one-row layout, falling
        // back to the slider on its own (flexing) row with the value fields
        // stacked beneath — so a constrained editor still works down to ~12
        // cells. Only the chosen candidate renders, so the shared focus IDs
        // never collide.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 1) {
                caption
                Slider(value: binding, in: range, step: 1).frame(width: 16).sliderShowsValue(false)
                pctField(upper)
                if upper != 100 { intField(upper) }
                if upper == 255 { hexField() }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    caption
                    Slider(value: binding, in: range, step: 1).sliderShowsValue(false)
                }
                pctField(upper)
                if upper != 100 { intField(upper) }
                if upper == 255 { hexField() }
            }
        }
    }

    /// The channel's one-letter label, right-aligned in a fixed gutter.
    private var caption: some View {
        Text(label)
            .frame(width: 2, alignment: .trailing)
            .foregroundStyle(.palette.foregroundTertiary)
    }

    /// Percentage field — always shown (it's the value the slider used to print).
    private func pctField(_ upper: Double) -> some View {
        _EditableValueField(
            focusID: "\(idBase)-pct", width: 7,
            format: { Self.percentString(binding.wrappedValue, upperBound: upper) },
            commit: { raw in
                guard raw.contains(where: \.isNumber) else { return }
                binding.wrappedValue = ColorPickerPanel.channelValue(
                    parsingPercent: raw, upperBound: upper)
            })
    }

    /// Raw integer field — only when it differs from the percentage (a 0–100
    /// channel would just duplicate it). Hue (0–360) gets a ° suffix.
    private func intField(_ upper: Double) -> some View {
        _EditableValueField(
            focusID: "\(idBase)-int", width: 7,
            format: { Self.integerString(binding.wrappedValue, degrees: upper == 360) },
            commit: { raw in
                guard raw.contains(where: \.isNumber) else { return }
                binding.wrappedValue = ColorPickerPanel.channelValue(parsing: raw, into: range)
            })
    }

    /// Hex field — only for the 0–255 channels (RGB, and opacity).
    private func hexField() -> some View {
        _EditableValueField(
            focusID: "\(idBase)-hex", width: 7,
            format: { Self.channelHexString(binding.wrappedValue) },
            commit: { raw in
                guard raw.contains(where: \.isHexDigit) else { return }
                binding.wrappedValue = ColorPickerPanel.channelValue(parsingHex: raw)
            })
    }

    /// `"NN%"` of the channel's range.
    static func percentString(_ value: Double, upperBound: Double) -> String {
        let pct = upperBound > 0 ? (value.isFinite ? value : 0) / upperBound * 100 : 0
        return "\(Int(pct.rounded()))%"
    }

    /// The raw integer value, with a `°` suffix for a degrees (hue) channel.
    static func integerString(_ value: Double, degrees: Bool) -> String {
        "\(Int((value.isFinite ? value : 0).rounded()))" + (degrees ? "°" : "")
    }

    /// The value as `"0xNN"` (two upper-case hex digits).
    static func channelHexString(_ value: Double) -> String {
        let v = Int((value.isFinite ? value : 0).rounded())
        let digits = String(max(0, min(255, v)), radix: 16, uppercase: true)
        return "0x" + (digits.count < 2 ? "0" + digits : digits)
    }
}
