//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TrackStyleEditor.swift
//
//  An interactive TrackConfiguration builder shared by the ProgressView and
//  Slider demo pages: pick each ingredient of a custom track style and watch
//  a live preview rendered with `.custom(_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// Builds a ``TrackConfiguration`` from four pickers (fill glyph, fractional
/// boundary ramp, unfilled treatment, optional gradient) and previews it live
/// on a ``ProgressView`` or a ``Slider``.
struct TrackStyleEditor: View {
    /// Which control the edited style is previewed on.
    enum PreviewControl {
        case progress
        case slider
    }

    let preview: PreviewControl

    @State private var fullGlyph = "█"
    @State private var rampName = "▏▎▍▌▋▊▉"
    @State private var unfilledName = "░"
    @State private var gradientEnabled = false
    @State private var sliderValue = 0.6

    /// Candidate fill glyphs — one column each, chosen to look distinct.
    private static let fullGlyphs = ["█", "▓", "▌", "■", "●", "━", "=", "#"]

    /// Candidate fractional-boundary ramps, keyed by their display name.
    private static let ramps: [(name: String, ramp: [Character]?)] = [
        ("—", nil),
        ("▏▎▍▌▋▊▉", ["▏", "▎", "▍", "▌", "▋", "▊", "▉"]),
        ("░▒▓", ["░", "▒", "▓"]),
        ("⣀⣄⣤⣦⣶⣷⣿", ["⣀", "⣄", "⣤", "⣦", "⣶", "⣷", "⣿"]),
    ]

    /// Candidate unfilled treatments, keyed by their display name. The last
    /// entry is the solid-background mode; the rest are empty glyphs.
    private static let unfilledGlyphs = ["░", "·", "─", "␣"]

    /// The demo gradient (red → amber → green), applied when the toggle is on.
    private static let gradient: [Color] = [
        .rgb(255, 80, 80), .rgb(255, 200, 80), .rgb(80, 220, 120),
    ]

    /// The configuration the pickers currently describe.
    private var configuration: TrackConfiguration {
        let ramp = Self.ramps.first { $0.name == rampName }.flatMap(\.ramp)
        let empty: TrackConfiguration.EmptyStyle
        switch unfilledName {
        case "␣": empty = .glyph(" ")
        case "background": empty = .background  // stable tag; label is localized
        default: empty = .glyph(unfilledName.first ?? "░")
        }
        return TrackConfiguration(
            fullGlyph: fullGlyph.first ?? "█",
            partialRamp: ramp,
            emptyStyle: empty,
            fillGradient: gradientEnabled ? Self.gradient : nil)
    }

    /// A slowly-advancing fraction (0→1 over 50 s), shared phase with the
    /// page's other determinate bars.
    private var animatedFraction: Double {
        let now = Date().timeIntervalSinceReferenceDate
        return now.truncatingRemainder(dividingBy: 50) / 50
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Picker(L("component.trackEditor.fill"), selection: $fullGlyph) {
                    ForEach(Self.fullGlyphs, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                Picker(L("component.trackEditor.ramp"), selection: $rampName) {
                    ForEach(Self.ramps.map(\.name), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            HStack(spacing: 2) {
                Picker(L("component.trackEditor.unfilled"), selection: $unfilledName) {
                    ForEach(Self.unfilledGlyphs, id: \.self) { Text($0).tag($0) }
                    // Localized label, stable tag — a language switch must not
                    // strand the stored selection.
                    Text(L("component.trackEditor.background")).tag("background")
                }
                .pickerStyle(.menu)
                Toggle(L("component.trackEditor.gradient"), isOn: $gradientEnabled)
            }

            switch preview {
            case .progress:
                ProgressView(value: animatedFraction)
                    .progressViewStyle(.custom(configuration))
                    .frame(width: 36)
            case .slider:
                Slider(value: $sliderValue)
                    .trackStyle(.custom(configuration))
                    .frame(width: 36)
            }
        }
    }
}
