//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorPicker.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Color Picker

/// A control for editing an RGB ``Color``.
///
/// Mirrors SwiftUI's `ColorPicker(_:selection:)` signature. SwiftUI opens the
/// platform colour panel from a swatch; a terminal has none, so this renders an
/// inline editor instead — a live swatch plus one ``Slider`` per channel (R, G,
/// B, each 0–255). Tab moves focus between the channel sliders; the arrow keys
/// adjust the focused channel. (There is no opacity channel — terminal colours
/// have no alpha — so `supportsOpacity` is omitted.)
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
    private let step: Double

    /// Creates a colour picker over an RGB binding.
    ///
    /// - Parameters:
    ///   - title: The label shown beside the editor.
    ///   - selection: The colour to edit. Rewritten as `.rgb(...)` on each change.
    ///   - step: How much each arrow press moves a channel (default 5 of 255).
    public init(_ title: String, selection: Binding<Color>, step: Double = 5) {
        self.title = title
        self.selection = selection
        self.step = step
    }

    public var body: some View {
        HStack(spacing: 1) {
            Text(title)
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(.palette.foregroundSecondary)
            // Live swatch in the colour being edited.
            Text("███").foregroundStyle(selection.wrappedValue)
            channel("R", 0)
            channel("G", 1)
            channel("B", 2)
        }
    }

    /// A labelled slider bound to one RGB channel (0 = red, 1 = green, 2 = blue).
    @ViewBuilder
    private func channel(_ label: String, _ index: Int) -> some View {
        let binding = channelBinding(index)
        HStack(spacing: 0) {
            Text(" \(label) ").foregroundStyle(.palette.foregroundTertiary)
            Slider(value: binding, in: 0...255, step: step).frame(width: 10)
            Text(String(format: "%3d", Int(binding.wrappedValue)))
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// A `Double` binding (0...255) onto one RGB channel of ``selection``,
    /// reading the current components and rewriting the colour as `.rgb`.
    private func channelBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                let components = selection.wrappedValue.rgbComponents ?? (0, 0, 0)
                switch index {
                case 0: return Double(components.red)
                case 1: return Double(components.green)
                default: return Double(components.blue)
                }
            },
            set: { newValue in
                var components = selection.wrappedValue.rgbComponents ?? (0, 0, 0)
                let clamped = UInt8(max(0, min(255, newValue.rounded())))
                switch index {
                case 0: components.red = clamped
                case 1: components.green = clamped
                default: components.blue = clamped
                }
                selection.wrappedValue = .rgb(components.red, components.green, components.blue)
            }
        )
    }
}
