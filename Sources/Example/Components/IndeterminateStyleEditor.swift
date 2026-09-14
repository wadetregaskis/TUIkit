//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateStyleEditor.swift
//
//  The indeterminate twin of `TrackStyleEditor`: the same combo fields over the
//  same persisted recents, plus the two things only a moving bar has — how long
//  a pass takes, and how much of the track is lit — previewed live through
//  `.indeterminateStyle(.custom(_:))`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// Builds an ``IndeterminateConfiguration`` and previews it live on a bare
/// ``ProgressView``.
struct IndeterminateStyleEditor: View {
    /// The chosen motion, persisted by its stable raw value rather than by
    /// index: reordering the enum must not silently repoint a saved setting.
    @AppStorage("indeterminateEditor.motion") private var motionName = "sweep"
    @AppStorage("indeterminateEditor.fill") private var fillGlyph = "█"
    @AppStorage("indeterminateEditor.empty") private var emptyGlyph = "░"
    @AppStorage("indeterminateEditor.period") private var period = 1.6
    @AppStorage("indeterminateEditor.extent") private var extent = 1.0 / 3.0
    @AppStorage("indeterminateEditor.tinted") private var tinted = false
    /// The ramp's stops, persisted as comma-separated hex like every other
    /// editable gradient on these pages. Default: the teal → violet demo.
    @AppStorage("indeterminateEditor.stops") private var stopsRaw = "3CC8BE,506EF0,AA46DC"

    @State private var editingStops = false

    // The last hundred committed values per field, most recent first. Separate
    // from the track editor's: a fill that reads well under a sweep is not the
    // one that reads well behind a boundary ramp.
    @AppStorage("indeterminateEditor.recentFills") private var recentFillsJSON = "[]"
    @AppStorage("indeterminateEditor.recentEmpties") private var recentEmptiesJSON = "[]"

    private static let defaultStops = Gradient(colors: [
        .rgb(60, 200, 190), .rgb(80, 110, 240), .rgb(170, 70, 220),
    ])

    /// Pre-defined lit patterns. `◢◤` is here because it is what makes a barber
    /// pole a barber pole — under that motion the pattern IS the stripe.
    private let fillGlyphs = ["█", "▓", "▌", "■", "●", "◢◤", "━", "=", "🎵"]

    /// Pre-defined unlit patterns, matching the track editor's vocabulary.
    private let emptyGlyphs = ["░", "·", "─", "␣", "•"]

    private var motion: IndeterminateConfiguration.Motion {
        IndeterminateConfiguration.Motion(rawValue: motionName) ?? .sweep
    }

    private var motionBinding: Binding<IndeterminateConfiguration.Motion> {
        Binding(get: { motion }, set: { motionName = $0.rawValue })
    }

    private var stops: Gradient {
        GradientStopsCodec.decode(stopsRaw, fallback: Self.defaultStops)
    }

    private var stopsBinding: Binding<Gradient> {
        Binding(get: { stops }, set: { stopsRaw = GradientStopsCodec.encode($0) })
    }

    /// Which of the two shape controls the chosen motion actually reads —
    /// `.pulse`, `.barberPole` and `.gradient` light every cell, so a lit
    /// fraction means nothing to them and its slider disables rather than
    /// pretending otherwise.
    private var usesExtent: Bool {
        motion == .sweep || motion == .knightRider
    }

    /// The configuration the controls currently describe. "␣" is the visible
    /// stand-in for a literal space, the same convention the track editor's
    /// unfilled field uses.
    private var configuration: IndeterminateConfiguration {
        IndeterminateConfiguration(
            motion: motion,
            fill: fillGlyph.isEmpty ? "█" : fillGlyph,
            background: emptyGlyph == "␣" ? " " : (emptyGlyph.isEmpty ? "░" : emptyGlyph),
            gradient: tinted ? stops : nil,
            period: period,
            extent: extent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Picker("component.indeterminateEditor.motion", selection: motionBinding) {
                Text(verbatim: "sweep").tag(IndeterminateConfiguration.Motion.sweep)
                Text(verbatim: "barberPole").tag(IndeterminateConfiguration.Motion.barberPole)
                Text(verbatim: "pulse").tag(IndeterminateConfiguration.Motion.pulse)
                Text(verbatim: "knightRider").tag(IndeterminateConfiguration.Motion.knightRider)
                Text(verbatim: "gradient").tag(IndeterminateConfiguration.Motion.gradient)
            }
            .pickerStyle(.menu)

            HStack(alignment: .top, spacing: 2) {
                comboField(
                    "component.trackEditor.fill", text: $fillGlyph, width: 9,
                    predefined: fillGlyphs, recentsJSON: $recentFillsJSON)
                comboField(
                    "component.trackEditor.unfilled", text: $emptyGlyph, width: 9,
                    predefined: emptyGlyphs, recentsJSON: $recentEmptiesJSON)
            }

            Slider(value: $period, in: 0.2...6, step: 0.1) {
                Text("\(L("component.indeterminateEditor.period")) \(String(format: "%.1f s", period))")
            }
            Slider(value: $extent, in: 0.05...1, step: 0.05) {
                Text(
                    "\(L("component.indeterminateEditor.extent")) "
                        + "\(Int((extent * 100).rounded()))%")
            }
            .disabled(!usesExtent)

            HStack(spacing: 2) {
                Toggle("component.indeterminateEditor.colors", isOn: $tinted)
                Button("component.trackEditor.editGradient") { editingStops = true }
                    .disabled(!tinted)
            }
            Text("component.trackEditor.comboHint")
                .foregroundStyle(.palette.foregroundSecondary)

            ProgressView()
                .indeterminateStyle(.custom(configuration))
                .frame(maxWidth: .infinity)
        }
        .modal(isPresented: $editingStops) {
            GradientEditorPanel(
                "component.indeterminateEditor.colorsTitle",
                gradient: stopsBinding,
                isPresented: $editingStops)
        }
    }

    /// One labelled combo field — the same shape as ``TrackStyleEditor``'s, and
    /// for the same reason: free text entry over a menu of the pre-defined
    /// values with the persisted recents under a divider.
    @ViewBuilder private func comboField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        width: Int,
        predefined: [String],
        recentsJSON: Binding<String>
    ) -> some View {
        let recents = RecentValues.list(from: recentsJSON.wrappedValue)
            .filter { !predefined.contains($0) }
        let record = {
            let value = text.wrappedValue
            guard !predefined.contains(value) else { return }
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
                    if !recents.isEmpty {
                        Divider()
                        ForEach(recents, id: \.self) { Text($0) }
                    }
                }
                .frame(width: width)
        }
    }
}
