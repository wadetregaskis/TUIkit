//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// The fill gradient's stops, persisted as comma-separated hex like the
    /// ProgressView page's sweep gradient. Default: red → amber → green.
    @AppStorage("trackEditor.gradientStops") private var gradientStopsRaw = "FF5050,FFC850,50DC78"
    /// What a gradient is measured across. The same control Progress & Gauges
    /// has, because it is the same question and the answer changes what a
    /// gradient MEANS — a scale, or a decoration.
    @AppStorage("trackEditor.gradientSpan") private var gradientSpansTrack = true
    /// The same question for the unfilled half's ramp, answered on its own:
    /// a fill that is a scale and a remainder that is a decoration is a
    /// perfectly ordinary bar.
    @AppStorage("trackEditor.emptyGradientSpan") private var emptyGradientSpansTrack = true
    /// Whether the unfilled half gets a colour of its own.
    @AppStorage("trackEditor.emptyTinted") private var emptyTinted = false
    /// Whether the unfilled half gets a gradient rather than a flat colour.
    /// The unfilled gradient's stops. Default: a cool ramp, so it reads as the
    /// other half of the bar rather than as more fill.
    @AppStorage("trackEditor.emptyStops") private var emptyStopsRaw = "203050,2A4A78,3C6EA5"
    @State private var editingEmptyGradient = false
    @State private var sliderValue = 0.6
    /// Whether the gradient-editor dialog is up.
    @State private var editingGradient = false

    // The last hundred committed values per field, most recent first,
    // persisted in app state (shared by the Slider and ProgressView pages).
    @AppStorage("trackEditor.recentFills") private var recentFillsJSON = "[]"
    @AppStorage("trackEditor.recentRamps") private var recentRampsJSON = "[]"
    @AppStorage("trackEditor.recentUnfilled") private var recentUnfilledJSON = "[]"

    /// Pre-defined fill glyphs — chosen to look distinct. The smiley combo
    /// (fill 😃, ramp 🫥😶😐🙂, unfilled 〰️) is offered on both pages; the
    /// Pac-Man combo (space fill — the eaten trail — with the ᗧ ramp head
    /// chomping a • dot line) is progress-only, where the fraction only ever
    /// advances. "␣" is the visible stand-in for a literal space fill, the
    /// same convention as the unfilled field.
    private var fullGlyphs: [String] {
        var glyphs = ["█", "▓", "▌", "■", "●", "━", "=", "#", "😃"]
        if preview == .progress { glyphs.append("␣") }
        return glyphs
    }

    /// Pre-defined fractional-boundary ramps. The field's text IS the ramp
    /// (darkest last), so free typing builds a custom ramp directly.
    private var ramps: [String] {
        var ramps = ["▏▎▍▌▋▊▉", "░▒▓", "⣀⣄⣤⣦⣶⣷⣿", "🫥😶😐🙂"]
        if preview == .progress { ramps.append("ᗧ") }
        return ramps
    }

    /// Pre-defined unfilled glyphs; the solid-background mode is offered via
    /// an explicit completion so its label can be localized while the stored
    /// value stays the stable "background" token.
    private var unfilledGlyphs: [String] {
        var glyphs = ["░", "·", "─", "␣", "〰️"]
        if preview == .progress { glyphs.append("•") }
        return glyphs
    }

    /// The fallback gradient (red → amber → green) when the persisted stops
    /// don't decode to at least two colours.
    private static let defaultGradient = Gradient(colors: [
        .rgb(255, 80, 80), .rgb(255, 200, 80), .rgb(80, 220, 120),
    ])

    /// The persisted stops decoded to a gradient.
    private var gradientStops: Gradient {
        GradientStopsCodec.decode(gradientStopsRaw, fallback: Self.defaultGradient)
    }

    /// The fallback unfilled gradient when the persisted stops are unusable.
    private static let defaultEmptyGradient = Gradient(colors: [
        .rgb(32, 48, 80), .rgb(42, 74, 120), .rgb(60, 110, 165),
    ])

    private var emptyStops: Gradient {
        GradientStopsCodec.decode(emptyStopsRaw, fallback: Self.defaultEmptyGradient)
    }

    private var emptyStopsBinding: Binding<Gradient> {
        Binding(
            get: { emptyStops },
            set: { emptyStopsRaw = GradientStopsCodec.encode($0) })
    }

    /// The gradient editor's binding: decodes on read, re-encodes on write.
    private var gradientStopsBinding: Binding<Gradient> {
        Binding(
            get: { gradientStops },
            set: { gradientStopsRaw = GradientStopsCodec.encode($0) })
    }

    /// The configuration the fields currently describe. Both the fill and
    /// the unfilled entries are PATTERNS: several characters repeat
    /// cyclically along the track, and multi-cell characters (emoji, CJK)
    /// coarsen the resolution — see ``TrackConfiguration/fill``.
    private var configuration: TrackConfiguration {
        let empty: TrackConfiguration.Background
        switch unfilledName {
        case "␣": empty = .glyph(" ")
        case "background": empty = .solid  // stable token; label is localized
        case "": empty = .glyph("░")
        default: empty = .pattern(unfilledName)
        }
        // "␣" is the menu's visible stand-in for a literal space fill (the
        // Pac-Man eaten trail), mirroring the unfilled field's convention.
        let fill: String
        switch fullGlyph {
        case "␣": fill = " "
        case "": fill = "█"
        default: fill = fullGlyph
        }
        return TrackConfiguration(
            fill: fill,
            leadingEdge: rampText.isEmpty ? nil : Array(rampText),
            background: empty,
            fillGradient: gradientEnabled ? gradientStops : nil,
            // The unfilled half is stylable too: a flat colour of the style's
            // own, or a ramp across it. Its first stop doubles as the flat
            // colour so the two controls agree about what "tinted" means.
            // Its first stop doubles as the flat colour, for the paths that
            // take no gradient at all (a coarse multi-cell fill, or a track
            // one cell wide).
            backgroundColor: emptyTinted ? emptyStops.stops.first?.color : nil,
            backgroundGradient: emptyTinted ? emptyStops : nil)
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
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 2) {
                comboField(
                    "component.trackEditor.fill", text: $fullGlyph, width: 9,
                    predefined: fullGlyphs, recentsJSON: $recentFillsJSON)
                comboField(
                    "component.trackEditor.ramp", text: $rampText, width: 14,
                    predefined: ramps, recentsJSON: $recentRampsJSON,
                    extraCompletions: [""]
                ) {
                    // An explicit "no sub-cell ramp" choice: its completion is
                    // the empty string, which the configuration maps to nil.
                    Text("component.trackEditor.rampNone").textInputCompletion("")
                }
                comboField(
                    "component.trackEditor.unfilled", text: $unfilledName, width: 9,
                    predefined: unfilledGlyphs, recentsJSON: $recentUnfilledJSON,
                    extraCompletions: ["background"]
                ) {
                    // The localized "solid background" option carries the
                    // stable token as its completion — a language switch must
                    // not strand the stored value.
                    Text("component.trackEditor.background")
                        .textInputCompletion("background")
                }
            }
            HStack(spacing: 2) {
                Toggle("component.trackEditor.gradient", isOn: $gradientEnabled)
                // Opens the modal gradient editor over the persisted stops.
                // Only meaningful while the gradient is applied, so it
                // disables with the toggle off.
                Button("component.trackEditor.editGradient") { editingGradient = true }
                    .disabled(!gradientEnabled)
                Toggle("component.trackEditor.gradientSpansTrack", isOn: $gradientSpansTrack)
                    .disabled(!gradientEnabled)
            }
            HStack(spacing: 2) {
                // One toggle, not two. There used to be a "…with a gradient"
                // beside this one, and all it did was choose between the
                // stops and their FIRST colour — an Example-side gradient →
                // flat conversion, not a different thing asked of the track.
                // A one-stop gradient already IS a flat colour, everywhere
                // from `GradientStopsCodec` to `TrackRenderer.gradientColor`,
                // so the editor below expresses "flat" by holding one stop and
                // the toggle has nothing left to say. This side now reads like
                // the fill's row above it: tint or leave it to the control.
                Toggle("component.trackEditor.emptyTinted", isOn: $emptyTinted)
                Button("component.trackEditor.editEmptyGradient") { editingEmptyGradient = true }
                    .disabled(!emptyTinted)
                Toggle("component.trackEditor.emptyGradientSpansTrack", isOn: $emptyGradientSpansTrack)
                    .disabled(!emptyTinted)
            }
            Text("component.trackEditor.comboHint")
                .foregroundStyle(.palette.foregroundSecondary)

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
                        fill: gradientSpansTrack ? .track : .region,
                        background: emptyGradientSpansTrack ? .track : .region)
            case .slider:
                Slider(value: $sliderValue)
                    .trackStyle(.custom(configuration))
                    .frame(maxWidth: .infinity)
                    .trackGradientScaling(
                        fill: gradientSpansTrack ? .track : .region,
                        background: emptyGradientSpansTrack ? .track : .region)
            }
        }
        .modal(isPresented: $editingEmptyGradient) {
            GradientEditorPanel(
                "component.trackEditor.emptyGradientTitle",
                gradient: emptyStopsBinding,
                isPresented: $editingEmptyGradient)
        }
        .modal(isPresented: $editingGradient) {
            GradientEditorPanel(
                "component.trackEditor.gradientTitle",
                gradient: gradientStopsBinding,
                isPresented: $editingGradient)
        }
        .task {
            await runPreviewProgress()
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
