//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackStyleEditor.swift
//
//  An interactive TrackConfiguration builder shared by the ProgressView and
//  Slider demo pages: one row each for the track's Fill, Leading edge and
//  Background. Each row is a combo field (text entry + a menu of pre-defined
//  and recent values, via `.textInputSuggestions`); the Fill and Background
//  rows add that part's colours. The style previews live with `.custom(_:)`.
//  Values committed with Enter — or picked from a menu — are recorded in
//  persistent app state, most recent first, and offered under a divider on the
//  next visit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// Builds a ``TrackConfiguration`` from three rows (the fill pattern, the
/// leading edge's fractional ramp, and the background) plus the colours of the
/// fill and of the background, and previews it live on a ``ProgressView`` or a
/// ``Slider``.
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
    @AppStorage("trackEditor.leadingEdge") private var leadingEdgeText = "▏▎▍▌▋▊▉"
    @AppStorage("trackEditor.background") private var backgroundName = "░"
    /// Whether the fill has colours of its own.
    @AppStorage("trackEditor.fillColoured") private var fillColoured = false
    /// The fill's stops, persisted as comma-separated hex like the
    /// ProgressView page's sweep gradient. Default: red → amber → green.
    @AppStorage("trackEditor.fillStops") private var fillStopsRaw = "FF5050,FFC850,50DC78"
    /// What the fill's stops are measured across. The same control Progress &
    /// Gauges has, because it is the same question and the answer changes what
    /// a gradient MEANS — a scale, or a decoration.
    @AppStorage("trackEditor.fillSpan") private var fillSpansTrack = true
    /// The same question for the background's stops, answered on its own:
    /// a fill that is a scale and a background that is a decoration is a
    /// perfectly ordinary bar.
    @AppStorage("trackEditor.backgroundSpan") private var backgroundSpansTrack = true
    /// Whether the background has colours of its own.
    @AppStorage("trackEditor.backgroundColoured") private var backgroundColoured = false
    /// The background's stops. Default: a cool ramp, so it reads as the other
    /// half of the bar rather than as more fill.
    @AppStorage("trackEditor.backgroundStops") private var backgroundStopsRaw = "203050,2A4A78,3C6EA5"
    /// Whether the background's colour editor is up.
    @State private var editingBackgroundStops = false
    @State private var sliderValue = 0.6
    /// Whether the fill's colour editor is up.
    @State private var editingFillStops = false

    // The last hundred committed values per field, most recent first,
    // persisted in app state (shared by the Slider and ProgressView pages).
    @AppStorage("trackEditor.recentFills") private var recentFillsJSON = "[]"
    @AppStorage("trackEditor.recentLeadingEdges") private var recentLeadingEdgesJSON = "[]"
    @AppStorage("trackEditor.recentBackgrounds") private var recentBackgroundsJSON = "[]"

    /// The row labels, in drawing order. The label column is as wide as the
    /// longest of them in the language on screen, so the fields line up.
    private static let rowLabels: [LocalizedStringKey] = [
        "component.trackEditor.fill",
        "component.trackEditor.leadingEdge",
        "component.trackEditor.background",
    ]

    /// Pre-defined fill glyphs — chosen to look distinct. The smiley combo
    /// (fill 😃, leading edge 🫥😶😐🙂, background 〰️) is offered on both
    /// pages; the Pac-Man combo (space fill — the eaten trail — with the ᗧ
    /// leading edge chomping a • dot line) is progress-only, where the fraction
    /// only ever advances. "␣" is the visible stand-in for a literal space
    /// fill, the same convention as the background field.
    private var fullGlyphs: [String] {
        var glyphs = ["█", "▓", "▌", "■", "●", "━", "=", "#", "😃"]
        if preview == .progress { glyphs.append("␣") }
        return glyphs
    }

    /// Pre-defined leading edges, each a fractional ramp. The field's text IS
    /// the ramp (darkest last), so free typing builds a custom ramp directly.
    private var leadingEdges: [String] {
        var edges = ["▏▎▍▌▋▊▉", "░▒▓", "⣀⣄⣤⣦⣶⣷⣿", "🫥😶😐🙂"]
        if preview == .progress { edges.append("ᗧ") }
        return edges
    }

    /// Pre-defined background patterns; the solid-background mode is offered
    /// via an explicit completion so its label can be localized while the
    /// stored value stays the stable "solid" token.
    private var backgroundPatterns: [String] {
        var glyphs = ["░", "·", "─", "␣", "〰️"]
        if preview == .progress { glyphs.append("•") }
        return glyphs
    }

    /// The fallback fill stops (red → amber → green) when the persisted stops
    /// don't decode to at least two colours.
    private static let defaultFillStops = Gradient(colors: [
        .rgb(255, 80, 80), .rgb(255, 200, 80), .rgb(80, 220, 120),
    ])

    /// The persisted fill stops decoded to a gradient.
    private var fillStops: Gradient {
        GradientStopsCodec.decode(fillStopsRaw, fallback: Self.defaultFillStops)
    }

    /// The fallback background stops when the persisted stops are unusable.
    private static let defaultBackgroundStops = Gradient(colors: [
        .rgb(32, 48, 80), .rgb(42, 74, 120), .rgb(60, 110, 165),
    ])

    private var backgroundStops: Gradient {
        GradientStopsCodec.decode(backgroundStopsRaw, fallback: Self.defaultBackgroundStops)
    }

    private var backgroundStopsBinding: Binding<Gradient> {
        Binding(
            get: { backgroundStops },
            set: { backgroundStopsRaw = GradientStopsCodec.encode($0) })
    }

    /// The fill's colour editor binding: decodes on read, re-encodes on write.
    private var fillStopsBinding: Binding<Gradient> {
        Binding(
            get: { fillStops },
            set: { fillStopsRaw = GradientStopsCodec.encode($0) })
    }

    /// The configuration the fields currently describe. Both the fill and
    /// the background entries are PATTERNS: several characters repeat
    /// cyclically along the track, and multi-cell characters (emoji, CJK)
    /// coarsen the resolution — see ``TrackConfiguration/fill``.
    private var configuration: TrackConfiguration {
        let background: TrackConfiguration.Background
        switch backgroundName {
        case "␣": background = .glyph(" ")
        case "solid": background = .solid  // stable token; label is localized
        case "": background = .glyph("░")
        default: background = .pattern(backgroundName)
        }
        // "␣" is the menu's visible stand-in for a literal space fill (the
        // Pac-Man eaten trail), mirroring the background field's convention.
        let fill: String
        switch fullGlyph {
        case "␣": fill = " "
        case "": fill = "█"
        default: fill = fullGlyph
        }
        return TrackConfiguration(
            fill: fill,
            leadingEdge: leadingEdgeText.isEmpty ? nil : Array(leadingEdgeText),
            background: background,
            fillGradient: fillColoured ? fillStops : nil,
            // A coloured background is its stops; the first stop doubles as
            // the flat colour, for the paths that take no gradient at all (a
            // coarse multi-cell fill, or a track one cell wide).
            backgroundColor: backgroundColoured ? backgroundStops.stops.first?.color : nil,
            backgroundGradient: backgroundColoured ? backgroundStops : nil)
    }

    /// A slowly-advancing fraction (0→1 over 50 s) for the preview bar.
    ///
    /// State advanced by ``runPreviewProgress()``, not a wall-clock read at
    /// render time — which is what this was, and which only ever moved because
    /// something else on the page was forcing renders. See the same note on
    /// `ProgressViewPage.demoFraction`.
    @State private var animatedFraction: Double = 0

    /// Advances the preview on its own. Cancelled when the editor goes away.
    private func runPreviewProgress() async {
        while !Task.isCancelled {
            // 1% every half-second — the data's rate, not a frame rate. See
            // `DemoProgress` on the ProgressView page.
            try? await Task.sleep(for: .milliseconds(500))
            animatedFraction += 0.01
            if animatedFraction > 1 { animatedFraction = 0 }
        }
    }

    var body: some View {
        // Measured in cells, not characters: a CJK label is two cells a glyph.
        let labelWidth = Self.rowLabels.map { key in key.localized.strippedLength }.max() ?? 0
        VStack(alignment: .leading, spacing: 1) {
            // One line per row: its label, its field, then (Fill and Background
            // only) its colour controls, which wrap onto further lines when the
            // terminal is too narrow for them.
            HStack(alignment: .top, spacing: 2) {
                Text("component.trackEditor.fill").frame(width: labelWidth)
                comboField(
                    "component.trackEditor.fill", text: $fullGlyph, width: 9,
                    predefined: fullGlyphs, recentsJSON: $recentFillsJSON)
                colourControls(coloured: $fillColoured, spansTrack: $fillSpansTrack) {
                    editingFillStops = true
                }
            }
            // The leading edge is drawn in the fill's colours, so it has no
            // colour controls of its own.
            HStack(alignment: .top, spacing: 2) {
                Text("component.trackEditor.leadingEdge").frame(width: labelWidth)
                comboField(
                    "component.trackEditor.leadingEdge", text: $leadingEdgeText, width: 14,
                    predefined: leadingEdges, recentsJSON: $recentLeadingEdgesJSON,
                    extraCompletions: [""]
                ) {
                    // An explicit "no sub-cell ramp" choice: its completion is
                    // the empty string, which the configuration maps to nil.
                    Text("component.trackEditor.rampNone").textInputCompletion("")
                }
            }
            HStack(alignment: .top, spacing: 2) {
                Text("component.trackEditor.background").frame(width: labelWidth)
                comboField(
                    "component.trackEditor.background", text: $backgroundName, width: 9,
                    predefined: backgroundPatterns, recentsJSON: $recentBackgroundsJSON,
                    extraCompletions: ["solid"]
                ) {
                    // The localized "solid background" option carries the
                    // stable token as its completion — a language switch must
                    // not strand the stored value.
                    Text("component.trackEditor.solidBackground")
                        .textInputCompletion("solid")
                }
                colourControls(coloured: $backgroundColoured, spansTrack: $backgroundSpansTrack) {
                    editingBackgroundStops = true
                }
            }

            // Full width, not a fixed 36 cells: this is the one bar on either
            // page that the reader is editing, and a coarse fill (an emoji
            // pattern quantizes the track to its own cell width) has visibly
            // more to show at 80 cells than at 36.
            switch preview {
            case .progress:
                ProgressView(value: animatedFraction)
                    .progressViewStyle(.custom(configuration))
                    .frame(maxWidth: .infinity)
                    .trackGradientScaling(
                        fill: fillSpansTrack ? .track : .region,
                        background: backgroundSpansTrack ? .track : .region)
            case .slider:
                Slider(value: $sliderValue)
                    .trackStyle(.custom(configuration))
                    .frame(maxWidth: .infinity)
                    .trackGradientScaling(
                        fill: fillSpansTrack ? .track : .region,
                        background: backgroundSpansTrack ? .track : .region)
            }
        }
        .modal(isPresented: $editingBackgroundStops) {
            GradientEditorPanel(
                "component.trackEditor.emptyGradientTitle",
                gradient: backgroundStopsBinding,
                isPresented: $editingBackgroundStops)
        }
        .modal(isPresented: $editingFillStops) {
            GradientEditorPanel(
                "component.trackEditor.gradientTitle",
                gradient: fillStopsBinding,
                isPresented: $editingFillStops)
        }
        .task {
            await runPreviewProgress()
        }
    }

    /// A Fill or Background row's colour controls: whether that part has
    /// colours of its own, an editor for them, and what they are measured
    /// across. The last two only mean something while the part is coloured,
    /// so they disable with the toggle off.
    ///
    /// One toggle, not a flat-colour toggle and a gradient toggle: a one-stop
    /// gradient already IS a flat colour, everywhere from `GradientStopsCodec`
    /// to `TrackRenderer.gradientColor`, so the editor expresses "flat" by
    /// holding one stop. Held in a ``Flow``, so a narrow terminal moves whole
    /// controls onto the next line instead of clipping the last one.
    private func colourControls(
        coloured: Binding<Bool>, spansTrack: Binding<Bool>, edit: @escaping () -> Void
    ) -> some View {
        Flow(spacing: 2) {
            Toggle("component.trackEditor.coloured", isOn: coloured)
            Button("component.trackEditor.edit", action: edit)
                .disabled(!coloured.wrappedValue)
            Toggle("component.trackEditor.spanWholeTrack", isOn: spansTrack)
                .disabled(!coloured.wrappedValue)
        }
    }

    /// One combo field: free text entry over a suggestions menu of the
    /// pre-defined values, any extra options, and — under a divider — the
    /// persisted recents. The row supplies the visible label; `title` is the
    /// field's prompt, shown while it is empty. A value is recorded on Enter,
    /// on picking a suggestion (which submits), and when the field loses focus
    /// — a custom value applies live, so tabbing away must not lose it. Only
    /// genuinely custom values are recorded: the pre-defined options (and any
    /// extra options' completions) already have a home above the divider.
    @ViewBuilder private func comboField(
        _ title: LocalizedStringKey,
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
