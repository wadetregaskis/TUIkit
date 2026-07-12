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

    // The edited style itself persists app-wide (and across sessions, like
    // the recents): leaving the page and coming back — or relaunching —
    // resumes the same custom style. Shared between the Slider and
    // ProgressView pages' editors, which deliberately edit one style.
    @AppStorage("trackEditor.fill") private var fullGlyph = "█"
    @AppStorage("trackEditor.ramp") private var rampText = "▏▎▍▌▋▊▉"
    @AppStorage("trackEditor.unfilled") private var unfilledName = "░"
    @AppStorage("trackEditor.gradient") private var gradientEnabled = false
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

    /// The configuration the fields currently describe. Both the fill and
    /// the unfilled entries are PATTERNS: several characters repeat
    /// cyclically along the track, and multi-cell characters (emoji, CJK)
    /// coarsen the resolution — see ``TrackConfiguration/fill``.
    private var configuration: TrackConfiguration {
        let empty: TrackConfiguration.EmptyStyle
        switch unfilledName {
        case "␣": empty = .glyph(" ")
        case "background": empty = .background  // stable token; label is localized
        case "": empty = .glyph("░")
        default: empty = .pattern(unfilledName)
        }
        return TrackConfiguration(
            fill: fullGlyph.isEmpty ? "█" : fullGlyph,
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
                    predefined: Self.ramps, recentsJSON: $recentRampsJSON,
                    extraCompletions: [""]
                ) {
                    // An explicit "no sub-cell ramp" choice: its completion is
                    // the empty string, which the configuration maps to nil.
                    Text(L("component.trackEditor.rampNone")).textInputCompletion("")
                }
                comboField(
                    L("component.trackEditor.unfilled"), text: $unfilledName, width: 9,
                    predefined: Self.unfilledGlyphs, recentsJSON: $recentUnfilledJSON,
                    extraCompletions: ["background"]
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
    /// persisted recents. A value is recorded on Enter, on picking a
    /// suggestion (which submits), and when the field loses focus — a custom
    /// value applies live, so tabbing away must not lose it. Only genuinely
    /// custom values are recorded: the pre-defined options (and any extra
    /// options' completions) already have a home above the divider.
    @ViewBuilder private func comboField(
        _ title: String,
        text: Binding<String>,
        width: Int,
        predefined: [String],
        recentsJSON: Binding<String>,
        extraCompletions: [String] = [],
        @ViewBuilder extraOptions: () -> some View = { EmptyView() }
    ) -> some View {
        // Recents that just repeat a pre-defined option would show twice
        // (defensive display filter for storage recorded before this rule).
        let recents = RecentValues.list(from: recentsJSON.wrappedValue)
            .filter { !predefined.contains($0) && !extraCompletions.contains($0) }
        let record = {
            let value = text.wrappedValue
            guard !predefined.contains(value), !extraCompletions.contains(value) else { return }
            recentsJSON.wrappedValue = RecentValues.recording(
                value, in: recentsJSON.wrappedValue)
        }
        VStack(alignment: .leading, spacing: 0) {
            Text(title).dim()
            TextField(title, text: text)
                .onSubmit(record)
                .onEditingChanged { began in
                    if !began { record() }
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
