//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProgressViewPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// The demo's determinate pace: **1% every half-second**, so 0 to 1 over 50 s.
///
/// The update rate is the DATA's rate, not a frame rate, and that is the whole
/// point of the number. A bar sixty cells wide advances one cell every 0.83 s at
/// this pace, so ticking ten times a second would draw nine identical screens
/// out of every ten — and each of those is a full render of the page. A
/// determinate bar should be advanced when its value changes, and no more often.
private enum DemoProgress {
    static let interval: Duration = .milliseconds(500)

    /// How many steps make a full sweep.
    ///
    /// A COUNT rather than a `Double` step, because 0.01 is not exact in binary
    /// and a hundred additions of it come to 1.0000000000000007 — past the wrap
    /// test, so the demo reset one step early and never once showed 100%. The
    /// fraction is `Double(step) / Double(steps)` instead, which hits both ends
    /// exactly.
    static let steps = 100
}

/// Progress-view demo page.
///
/// Shows ``ProgressView`` in its determinate (a known fraction) and
/// indeterminate (no known total) modes, across every built-in style.
struct ProgressViewPage: View {
    /// The determinate demo's value, advanced by ``runDemoProgress()``.
    ///
    /// State, driven by a task — NOT a wall-clock read at render time, which is
    /// what this was. Reading `Date()` while rendering produces a value that
    /// changes without anything having asked to be re-rendered, so it advances
    /// only for as long as something ELSE on the page happens to be forcing
    /// renders. It worked here because the indeterminate bars were demanding 30
    /// frames a second; the moment they stopped (they leave an
    /// `AnimatedCellRun` behind instead), these bars froze — while still
    /// looking, in a screenshot, exactly as they had.
    ///
    /// A real app's determinate bar is driven by its data. This is the
    /// demo's data.
    @State private var demoStep = 0

    /// The demo's value: the step count as a fraction, so 0 and 1 are both
    /// reachable exactly.
    private var demoFraction: Double { Double(demoStep) / Double(DemoProgress.steps) }

    /// The determinate track styles the top "Determinate" section cycles
    /// through with the `s` shortcut. The "Determinate styles" section below
    /// shows the full catalogue in parallel and is unaffected by this.
    private static let cyclableStyles: [(name: String, style: TrackStyle)] = [
        ("block", .block),
        ("blockFine", .blockFine),
        ("shade", .shade),
        ("bar", .bar),
        ("dot", .dot),
        ("braille", .braille),
    ]

    /// Which style the top "Determinate" section is currently showing.
    @State private var determinateStyleIndex = 0

    /// Whether the gradient rows below measure their ramp across the whole bar
    /// (the default, so a colour always marks the same value) or across the
    /// lit part (so it follows the fill). Watch `shadeRamp(g)` as it changes.
    @State private var gradientScaling = TrackGradientScaling.track

    /// Whether ramps on this page go to the terminal as PICTURES where it
    /// draws them — the block tracks, the indeterminate `gradient` motion —
    /// or as cells. Greyed on a terminal with no graphics, where it is moot.
    @State private var gradientGraphics = true

    /// Whether the gradient-editor dialog is up.
    @State private var editingGradient = false

    /// The `gradient(c)` row's stops, persisted across sessions as
    /// comma-separated hex (the editor's changes survive relaunch, like the
    /// track-style editor's selections). Default: the teal → violet demo.
    @AppStorage("progressDemo.gradientStops")
    private var gradientStopsRaw = "3CC8BE,506EF0,AA46DC"

    /// The persisted stops decoded to colours (invalid entries dropped; fewer
    /// than two falls back to the default so the row always shows a gradient).
    private var gradientStops: Gradient {
        GradientStopsCodec.decode(
            gradientStopsRaw,
            fallback: Gradient(colors: [
                .rgb(60, 200, 190), .rgb(80, 110, 240), .rgb(170, 70, 220),
            ]))
    }

    /// The editor's binding: decodes on read, re-encodes on write.
    private var gradientStopsBinding: Binding<Gradient> {
        Binding(
            get: { gradientStops },
            set: { gradientStopsRaw = GradientStopsCodec.encode($0) })
    }

    /// Decides whether the Determinate and Indeterminate sections sit
    /// side-by-side (wide terminals) or stack (narrow). An explicit width
    /// check rather than `ViewThatFits`: both sections hold width-flexible
    /// bars, and flexible content always "fits" whatever is proposed, so
    /// `ViewThatFits` would never reject the side-by-side variant.
    @Environment(\.terminalWidth) private var terminalWidth

    /// Advances ``demoFraction`` on its own, so the determinate bars keep
    /// moving whatever else is (or is not) driving renders. Cancelled
    /// automatically when the page goes away.
    private func runDemoProgress() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: DemoProgress.interval)
            demoStep = (demoStep + 1) % (DemoProgress.steps + 1)
        }
    }

    var body: some View {
        let current = Self.cyclableStyles[determinateStyleIndex]
        VStack(alignment: .leading, spacing: 1) {

            // Two columns of the same shape: each mode, then that mode's
            // catalogue of styles directly under it.
            //
            // A wider threshold than the `>= 80` this took when only the two
            // top sections were side by side. Those hold width-flexible bars
            // and shrink to whatever column they are given; the catalogues
            // below them are fixed-width rows (24 cells for a determinate bar,
            // 36 for an indeterminate one) and cannot.
            if terminalWidth >= Self.twoColumnWidth {
                HStack(alignment: .top, spacing: 2) {
                    VStack(alignment: .leading, spacing: 1) {
                        determinateSection(style: current.style)
                        determinateStylesSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        indeterminateSection
                        indeterminateStylesSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                determinateSection(style: current.style)
                determinateStylesSection
                indeterminateSection
                indeterminateStylesSection
            }

            // Build-your-own TrackConfiguration: every ingredient the named
            // presets are made of, applied live to a determinate bar.
            DemoSection("page.trackEditor.section") {
                TrackStyleEditor(preview: .progress)
            }

            // …and its twin for the other mode. The catalogue above shows what
            // the five named animations look like; this is what they are made
            // of, and every one of them is a preset of what these controls
            // build.
            DemoSection("page.indeterminateEditor.section") {
                IndeterminateStyleEditor()
            }

            // A Gauge is the sibling of ProgressView — it shows where a value
            // sits in a range rather than progress toward completion — so it
            // lives here. Its default shaded meter reads distinctly from the
            // ProgressView bars above; the `GaugeStyle` variants follow.
            DemoSection("page.progressView.gaugeSection") {
                VStack(alignment: .leading, spacing: 1) {
                    let fraction = demoFraction
                    Gauge(value: fraction, in: 0...1) {
                        Text("page.newControls.gaugeLabel")
                    } currentValueLabel: {
                        Text("\(Int((fraction * 100).rounded()))%")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("100")
                    }
                    gaugeRow(label: "accessoryLinear         ", fraction: fraction, style: .accessoryLinear)
                    gaugeRow(label: "accessoryLinearCapacity ", fraction: fraction, style: .accessoryLinearCapacity)
                    // The bare number in the plain ring, whose whole content is
                    // its read-out and whose four-cell interior "100%" fills
                    // corner to corner. Its two siblings keep the unit: the
                    // capacity ring is read as a proportion, which is what a
                    // percent sign says, and the tiny one puts its text OUTSIDE
                    // the glyph where there is room for it.
                    HStack(spacing: 3) {
                        circularGauge(
                            label: "accessoryCircular", fraction: fraction,
                            text: percent(fraction), style: .accessoryCircular)
                        circularGauge(
                            label: "…Capacity", fraction: fraction,
                            text: "\(percent(fraction))%", style: .accessoryCircularCapacity)
                        circularGauge(
                            label: "…Tiny", fraction: fraction,
                            text: "\(percent(fraction))%", style: .accessoryCircularTiny)
                    }

                    // Non-percentage read-outs: the same gauges over other
                    // ranges, exercising the label rendering with varied text
                    // widths — decimals ("0.62"), plain integers up to three
                    // digits, and signed degrees ("-12°").
                    Text("page.progressView.gaugeNonPercent")
                        .foregroundStyle(.palette.foregroundSecondary)
                    gaugeRow(
                        label: "0…1                     ", fraction: fraction,
                        text: String(format: "%.2f", fraction), style: .accessoryLinear)
                    gaugeRow(
                        label: "0…140                   ", fraction: fraction,
                        text: "\(Int((fraction * 140).rounded()))", style: .accessoryLinear)
                    gaugeRow(
                        label: "0…140 (capacity)        ", fraction: fraction,
                        text: "\(Int((fraction * 140).rounded()))", style: .accessoryLinearCapacity)
                    HStack(spacing: 3) {
                        circularGauge(
                            label: "0…1", fraction: fraction,
                            text: String(format: "%.2f", fraction), style: .accessoryCircular)
                        circularGauge(
                            label: "0…140", fraction: fraction,
                            text: "\(Int((fraction * 140).rounded()))", style: .accessoryCircular)
                        circularGauge(
                            label: "−20…40°", fraction: fraction,
                            text: "\(Int((-20 + fraction * 60).rounded()))°", style: .accessoryCircular)
                    }
                }
            }

            Spacer()
        }
        .gradientGraphics(gradientGraphics)
        .scrollableDemoPage()
        .task {
            await runDemoProgress()
        }
        .modal(isPresented: $editingGradient) {
            GradientEditorPanel(
                "page.progressView.gradientTitle",
                gradient: gradientStopsBinding,
                isPresented: $editingGradient)
        }
        .appHeader {
            DemoAppHeader("menu.item.progress")
        }
        // A page that declares status items declares the WHOLE bar — the app's
        // own "⎋ back" is replaced rather than merged with, which is why every
        // other page that has items of its own re-states it (Containers, Text
        // Input, both Image pages). This one did not, so its bar was the only
        // one in the app that did not say how to leave. Informational, with no
        // action: Escape is still handled above this page, which is why the key
        // worked all along and only the label was missing.
        //
        // Cycles only the top "Determinate" section's style; the style
        // catalogues below stay put.
        .statusBarItems {
            StatusBarItem(shortcut: Shortcut.escape, label: "status.back")
            StatusBarItem(shortcut: "s", label: "\(L("page.progressView.styleLabel")): \(current.name)") {
                determinateStyleIndex =
                    (determinateStyleIndex + 1) % Self.cyclableStyles.count
            }
        }
    }

    /// How wide the terminal has to be for the two catalogues to sit side
    /// by side. Their rows are fixed-width, so below this they stack rather
    /// than clip.
    private static let twoColumnWidth = 106

    /// The determinate catalogue: every built-in ``TrackStyle`` at the
    /// page's shared fraction, so they fill together.
    @ViewBuilder
    private var determinateStylesSection: some View {
        DemoSection("page.progressView.determinateStyles") {
            VStack(alignment: .leading, spacing: 0) {
                Picker("page.progressView.gradientScaling", selection: $gradientScaling) {
                    Text("page.progressView.gradientScalingTrack").tag(TrackGradientScaling.track)
                    Text("page.progressView.gradientScalingFill").tag(TrackGradientScaling.region)
                }
                Toggle("page.progressView.gradientGraphics", isOn: $gradientGraphics)
                    .disabled(!KittyGraphics.isSupported)
                .pickerStyle(.inline)
                HStack(spacing: 1) {
                    Text("Style        ").dim()
                    Text("    Progress       ").dim().frame(width: 24)
                }
                determinateRow(label: "block        ", style: .block)
                determinateRow(label: "blockFine    ", style: .blockFine)
                determinateRow(label: "shade        ", style: .shade)
                determinateRow(label: "bar          ", style: .bar)
                determinateRow(label: "dot          ", style: .dot)
                determinateRow(label: "braille      ", style: .braille)
                determinateRow(
                    label: "shadeRamp    ",
                    style: .shadeRamp(gradient: nil)
                )
                determinateRow(
                    label: "shadeRamp(g) ",
                    style: .shadeRamp(gradient: Gradient(colors: [
                        .rgb(255, 80, 80),
                        .rgb(255, 200, 80),
                        .rgb(80, 220, 120),
                    ]))
                )
                determinateRow(
                    label: "threeSegment ",
                    style: .threeSegment(
                        leading: "Sw",
                        middle: "i",
                        trailing: "ft",
                        backgroundPattern: "·"
                    )
                )
                // Segment colouring: one colour per segment…
                determinateRow(
                    label: "threeSeg(per)",
                    style: .threeSegment(
                        leading: "Sw", middle: "i", trailing: "ft", backgroundPattern: "·",
                        coloring: .perSegment(
                            leading: .rgb(255, 120, 60),
                            middle: .rgb(220, 220, 220),
                            trailing: .rgb(80, 160, 255))
                    )
                )
                // …or a per-cell gradient across the whole lit span.
                determinateRow(
                    label: "threeSeg(gr) ",
                    style: .threeSegment(
                        leading: "Sw", middle: "i", trailing: "ft", backgroundPattern: "·",
                        coloring: .gradient(Gradient(colors: [
                            .rgb(255, 80, 80), .rgb(255, 200, 80), .rgb(80, 220, 120),
                        ]))
                    )
                )
                // A hand-rolled `.custom` recipe: a shade-ramp fill with a
                // solid background — a combination
                // no named preset provides (showcasing TrackConfiguration).
                determinateRow(
                    label: "custom       ",
                    style: .custom(
                        TrackConfiguration(
                            fullGlyph: "█", leadingEdge: ["░", "▒", "▓"],
                            background: .solid))
                )
            }
            .trackGradientScaling(gradientScaling)
        }
    }

    /// The indeterminate catalogue — the peer of
    /// ``determinateStylesSection``, and the second column's lower half.
    @ViewBuilder
    private var indeterminateStylesSection: some View {
        DemoSection("page.progressView.indeterminateStyles") {
            VStack(alignment: .leading, spacing: 0) {
                indeterminateRow(label: "sweep        ", style: .sweep)
                indeterminateRow(label: "barberPole   ", style: .barberPole)
                indeterminateRow(label: "pulse        ", style: .pulse)
                indeterminateRow(label: "knightRider  ", style: .knightRider)
                indeterminateRow(label: "gradient     ", style: .gradient())
                // The same slide with caller-supplied stops: any ≥2 RGB
                // colours, cyclically wrapped — editable via the gradient
                // editor below (teal → violet until you change it).
                indeterminateRow(
                    label: "gradient(c)  ",
                    style: .gradient(gradientStops))
                HStack(spacing: 1) {
                    ForEach(Array(gradientStops.stops.enumerated()), id: \.offset) { _, stop in
                        Text("██").foregroundStyle(stop.color)
                    }
                    Button("page.progressView.editGradient") { editingGradient = true }
                }
            }
        }
    }

    /// The "Determinate" section — two labelled bars animating via the shared
    /// wall-clock fraction (they stay in sync; the animation clock's 20 Hz
    /// re-render makes the animation look continuous despite being
    /// state-less). The `s` shortcut cycles the style applied to just these.
    @ViewBuilder
    private func determinateSection(style: TrackStyle) -> some View {
        DemoSection("page.progressView.determinate") {
            VStack(alignment: .leading, spacing: 1) {
                let fraction = demoFraction
                ProgressView("page.progressView.downloadingFiles", value: fraction)
                    .progressViewStyle(style)

                ProgressView(value: fraction) {
                    Text("page.progressView.buildProgress")
                        .foregroundStyle(.palette.foreground)
                } currentValueLabel: {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
                .progressViewStyle(style)
            }
        }
    }

    /// The "Indeterminate" section — labelled, custom-label and bare spinners.
    @ViewBuilder
    private var indeterminateSection: some View {
        DemoSection("page.progressView.indeterminate") {
            VStack(alignment: .leading, spacing: 1) {
                ProgressView("page.progressView.connecting")

                ProgressView {
                    Text("page.progressView.reticulatingSplines")
                        .foregroundStyle(.palette.foreground)
                }

                // Pure indeterminate, no label — useful inline against
                // another control.
                HStack(spacing: 1) {
                    Text("page.progressView.working").dim()
                    ProgressView()
                }
            }
        }
    }

    /// A `[label | determinate bar]` row at a fixed column width.
    /// Uses the page's shared animated fraction so every determinate
    /// example fills together — a single visual cue rather than a wall
    /// of static-looking bars at different fixed values.
    @ViewBuilder
    private func determinateRow(label: String, style: TrackStyle) -> some View {
        HStack(spacing: 1) {
            Text(label).dim()
            ProgressView(value: demoFraction)
                .progressViewStyle(style)
                .frame(width: 24)
        }
    }

    /// A `[label | indeterminate bar]` row at a fixed column width,
    /// publishing the chosen indeterminate animation via the env modifier.
    @ViewBuilder
    private func indeterminateRow(label: String, style: IndeterminateStyle) -> some View {
        HStack(spacing: 1) {
            Text(label).dim()
            ProgressView().frame(width: 36).indeterminateStyle(style)
        }
    }

    /// A `[style name | linear gauge]` row, echoing the ProgressView catalogue.
    /// `text` overrides the read-out (default: the fraction as a percentage).
    @ViewBuilder
    private func gaugeRow(
        label: String, fraction: Double, text: String? = nil, style: GaugeStyle
    ) -> some View {
        HStack(spacing: 1) {
            Text(label).dim()
            Gauge(value: fraction) { EmptyView() } currentValueLabel: {
                Text(text ?? "\(Int((fraction * 100).rounded()))%")
            }
            .gaugeStyle(style)
            .frame(width: 28)
        }
    }

    /// A circular gauge with its style name below it.
    ///
    /// `text` is required rather than defaulted: a ring has four cells for its
    /// read-out, so what goes in one is always a decision.
    @ViewBuilder
    private func circularGauge(
        label: String, fraction: Double, text: String, style: GaugeStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Gauge(value: fraction) { EmptyView() } currentValueLabel: {
                Text(text)
            }
            .gaugeStyle(style)
            Text(label).dim()
        }
    }

    /// `fraction` as a whole number of percent, with no unit — the read-out
    /// the ring gauges take.
    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))"
    }
}
