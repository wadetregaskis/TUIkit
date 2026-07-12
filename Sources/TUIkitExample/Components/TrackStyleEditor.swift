//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TrackStyleEditor.swift
//
//  An interactive TrackConfiguration builder shared by the ProgressView and
//  Slider demo pages: three combo fields (text entry + a menu of pre-defined
//  and recent values, via `.textInputSuggestions`) build a custom track style
//  and preview it live with `.custom(_:)`. Values committed with Enter — or
//  picked from a menu — are recorded in persistent app state, most recent
//  first, and offered under a divider on the next visit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// Builds a ``TrackConfiguration`` from three combo fields (fill glyph,
/// fractional boundary ramp, unfilled treatment) plus a gradient toggle, and
/// previews it live on a ``ProgressView`` or a ``Slider``.
struct TrackStyleEditor: View {
    /// Which control the edited style is previewed on.
    enum PreviewControl {
        case progress
        case slider
    }

    let preview: PreviewControl

    @State private var fullGlyph = "█"
    @State private var rampText = "▏▎▍▌▋▊▉"
    @State private var unfilledName = "░"
    @State private var gradientEnabled = false
    @State private var sliderValue = 0.6

    // The last hundred committed values per field, most recent first,
    // persisted in app state (shared by the Slider and ProgressView pages).
    @AppStorage("trackEditor.recentFills") private var recentFillsJSON = "[]"
    @AppStorage("trackEditor.recentRamps") private var recentRampsJSON = "[]"
    @AppStorage("trackEditor.recentUnfilled") private var recentUnfilledJSON = "[]"

    /// Pre-defined fill glyphs — one column each, chosen to look distinct.
    private static let fullGlyphs = ["█", "▓", "▌", "■", "●", "━", "=", "#"]

    /// Pre-defined fractional-boundary ramps. The field's text IS the ramp
    /// (darkest last), so free typing builds a custom ramp directly.
    private static let ramps = ["▏▎▍▌▋▊▉", "░▒▓", "⣀⣄⣤⣦⣶⣷⣿"]

    /// Pre-defined unfilled glyphs; the solid-background mode is offered via
    /// an explicit completion so its label can be localized while the stored
    /// value stays the stable "background" token.
    private static let unfilledGlyphs = ["░", "·", "─", "␣"]

    /// The demo gradient (red → amber → green), applied when the toggle is on.
    private static let gradient: [Color] = [
        .rgb(255, 80, 80), .rgb(255, 200, 80), .rgb(80, 220, 120),
    ]

    /// The configuration the fields currently describe.
    private var configuration: TrackConfiguration {
        let empty: TrackConfiguration.EmptyStyle
        switch unfilledName {
        case "␣": empty = .glyph(" ")
        case "background": empty = .background  // stable token; label is localized
        default: empty = .glyph(unfilledName.first ?? "░")
        }
        return TrackConfiguration(
            fullGlyph: fullGlyph.first ?? "█",
            partialRamp: rampText.isEmpty ? nil : Array(rampText),
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
            HStack(alignment: .top, spacing: 2) {
                comboField(
                    L("component.trackEditor.fill"), text: $fullGlyph, width: 9,
                    predefined: Self.fullGlyphs, recentsJSON: $recentFillsJSON)
                comboField(
                    L("component.trackEditor.ramp"), text: $rampText, width: 14,
                    predefined: Self.ramps, recentsJSON: $recentRampsJSON)
                comboField(
                    L("component.trackEditor.unfilled"), text: $unfilledName, width: 9,
                    predefined: Self.unfilledGlyphs, recentsJSON: $recentUnfilledJSON
                ) {
                    // The localized "solid background" option carries the
                    // stable token as its completion — a language switch must
                    // not strand the stored value.
                    Text(L("component.trackEditor.background"))
                        .textInputCompletion("background")
                }
            }
            Toggle(L("component.trackEditor.gradient"), isOn: $gradientEnabled)
            Text(L("component.trackEditor.comboHint"))
                .foregroundStyle(.palette.foregroundSecondary)

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

    /// One labelled combo field: free text entry over a suggestions menu of
    /// the pre-defined values, any extra options, and — under a divider — the
    /// persisted recents. Enter (or picking a suggestion, which submits)
    /// records the value.
    @ViewBuilder private func comboField(
        _ title: String,
        text: Binding<String>,
        width: Int,
        predefined: [String],
        recentsJSON: Binding<String>,
        @ViewBuilder extraOptions: () -> some View = { EmptyView() }
    ) -> some View {
        // Recents that just repeat a pre-defined option would show twice.
        let recents = RecentValues.list(from: recentsJSON.wrappedValue)
            .filter { !predefined.contains($0) }
        VStack(alignment: .leading, spacing: 0) {
            Text(title).dim()
            TextField(title, text: text)
                .onSubmit {
                    recentsJSON.wrappedValue = RecentValues.recording(
                        text.wrappedValue, in: recentsJSON.wrappedValue)
                }
                .textInputSuggestions {
                    ForEach(predefined, id: \.self) { Text($0) }
                    extraOptions()
                    if !recents.isEmpty {
                        Divider()
                        ForEach(recents, id: \.self) { Text($0) }
                    }
                }
                .frame(width: width)
        }
    }
}
