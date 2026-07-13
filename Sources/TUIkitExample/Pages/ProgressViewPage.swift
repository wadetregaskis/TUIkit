//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ProgressViewPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Returns a value in `0...1` that ramps from 0 to 1 over `period`
/// seconds and then wraps back to 0. The page's render is driven by
/// ``PulseTimer`` (~10 Hz), so reading this on each render produces a
/// smooth slow animation in the determinate bars without anything in
/// the page having to remember state. The default `period` of 50 s
/// is the user's requested "1% every half-second" pace.
private func animatedFraction(period: Double = 50) -> Double {
    let now = Date().timeIntervalSinceReferenceDate
    return now.truncatingRemainder(dividingBy: period) / period
}

/// Progress-view demo page.
///
/// Shows ``ProgressView`` in its determinate (a known fraction) and
/// indeterminate (no known total) modes, across every built-in style.
struct ProgressViewPage: View {
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

    /// Whether the gradient-editor dialog is up.
    @State private var editingGradient = false

    /// The `gradient(c)` row's stops, persisted across sessions as
    /// comma-separated hex (the editor's changes survive relaunch, like the
    /// track-style editor's selections). Default: the teal → violet demo.
    @AppStorage("progressDemo.gradientStops")
    private var gradientStopsRaw = "3CC8BE,506EF0,AA46DC"

    /// The persisted stops decoded to colours (invalid entries dropped; fewer
    /// than two falls back to the default so the row always shows a gradient).
    private var gradientStops: [Color] {
        let parsed = gradientStopsRaw.split(separator: ",").compactMap { Color.hex(String($0)) }
        return parsed.count >= 2 ? parsed : [.rgb(60, 200, 190), .rgb(80, 110, 240), .rgb(170, 70, 220)]
    }

    /// The editor's binding: decodes on read, re-encodes on write.
    private var gradientStopsBinding: Binding<[Color]> {
        Binding(
            get: { gradientStops },
            set: { gradientStopsRaw = $0.map(Self.hexString).joined(separator: ",") })
    }

    private static func hexString(_ color: Color) -> String {
        guard let c = color.rgbComponents else { return "000000" }
        return String(format: "%02X%02X%02X", c.red, c.green, c.blue)
    }

    /// Decides whether the Determinate and Indeterminate sections sit
    /// side-by-side (wide terminals) or stack (narrow). An explicit width
    /// check rather than `ViewThatFits`: both sections hold width-flexible
    /// bars, and flexible content always "fits" whatever is proposed, so
    /// `ViewThatFits` would never reject the side-by-side variant.
    @Environment(\.terminalWidth) private var terminalWidth

    var body: some View {
        let current = Self.cyclableStyles[determinateStyleIndex]
        VStack(alignment: .leading, spacing: 1) {

            if terminalWidth >= 80 {
                HStack(alignment: .top, spacing: 2) {
                    determinateSection(style: current.style)
                        .frame(maxWidth: .infinity)
                    indeterminateSection
                        .frame(maxWidth: .infinity)
                }
            } else {
                determinateSection(style: current.style)
                indeterminateSection
            }

            DemoSection(L("page.progressView.determinateStyles")) {
                VStack(alignment: .leading, spacing: 0) {
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
                        style: .shadeRamp(gradient: [
                            .rgb(255, 80, 80),
                            .rgb(255, 200, 80),
                            .rgb(80, 220, 120),
                        ])
                    )
                    determinateRow(
                        label: "threeSegment ",
                        style: .threeSegment(
                            leading: "Sw",
                            middle: "i",
                            trailing: "ft",
                            emptyFill: "·"
                        )
                    )
                    // Segment colouring: one colour per segment…
                    determinateRow(
                        label: "threeSeg(per)",
                        style: .threeSegment(
                            leading: "Sw", middle: "i", trailing: "ft", emptyFill: "·",
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
                            leading: "Sw", middle: "i", trailing: "ft", emptyFill: "·",
                            coloring: .gradient([
                                .rgb(255, 80, 80), .rgb(255, 200, 80), .rgb(80, 220, 120),
                            ])
                        )
                    )
                    // A hand-rolled `.custom` recipe: a shade-ramp fill with a
                    // solid background for the unfilled region — a combination
                    // no named preset provides (showcasing TrackConfiguration).
                    determinateRow(
                        label: "custom       ",
                        style: .custom(
                            TrackConfiguration(
                                fullGlyph: "█", partialRamp: ["░", "▒", "▓"],
                                emptyStyle: .background))
                    )
                }
            }

            // Build-your-own TrackConfiguration: every ingredient the named
            // presets are made of, applied live to a determinate bar.
            DemoSection(L("page.trackEditor.section")) {
                TrackStyleEditor(preview: .progress)
            }

            DemoSection(L("page.progressView.indeterminateAnimations")) {
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
                        style: .gradient(colors: gradientStops))
                    HStack(spacing: 1) {
                        ForEach(Array(gradientStops.enumerated()), id: \.offset) { _, stop in
                            Text("██").foregroundStyle(stop)
                        }
                        Button(L("page.progressView.editGradient")) { editingGradient = true }
                    }
                }
            }

            // A Gauge is the sibling of ProgressView — it shows where a value
            // sits in a range rather than progress toward completion — so it
            // lives here. Its default shaded meter reads distinctly from the
            // ProgressView bars above; the `GaugeStyle` variants follow.
            DemoSection(L("page.progressView.gaugeSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    let fraction = animatedFraction()
                    Gauge(value: fraction, in: 0...1) {
                        Text(L("page.newControls.gaugeLabel"))
                    } currentValueLabel: {
                        Text("\(Int((fraction * 100).rounded()))%")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("100")
                    }
                    gaugeRow(label: "accessoryLinear         ", fraction: fraction, style: .accessoryLinear)
                    gaugeRow(label: "accessoryLinearCapacity ", fraction: fraction, style: .accessoryLinearCapacity)
                    HStack(spacing: 3) {
                        circularGauge(label: "accessoryCircular", fraction: fraction, style: .accessoryCircular)
                        circularGauge(label: "…Capacity", fraction: fraction, style: .accessoryCircularCapacity)
                        circularGauge(label: "…Tiny", fraction: fraction, style: .accessoryCircularTiny)
                    }

                    // Non-percentage read-outs: the same gauges over other
                    // ranges, exercising the label rendering with varied text
                    // widths — decimals ("0.62"), plain integers up to three
                    // digits, and signed degrees ("-12°").
                    Text(L("page.progressView.gaugeNonPercent"))
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
        .scrollableDemoPage()
        .modal(isPresented: $editingGradient) {
            GradientEditorPanel(
                L("page.progressView.gradientTitle"),
                stops: gradientStopsBinding,
                isPresented: $editingGradient)
        }
        .appHeader {
            DemoAppHeader(L("page.progressView.title"))
        }
        // Merges with the page's back / scroll items. Cycles only the top
        // "Determinate" section's style; the style catalogues below stay put.
        .statusBarItems {
            StatusBarItem(shortcut: "s", label: "\(L("page.progressView.styleLabel")): \(current.name)") {
                determinateStyleIndex =
                    (determinateStyleIndex + 1) % Self.cyclableStyles.count
            }
        }
    }

    /// The "Determinate" section — two labelled bars animating via the shared
    /// wall-clock fraction (they stay in sync; the PulseTimer's ~10 Hz
    /// re-render makes the animation look continuous despite being
    /// state-less). The `s` shortcut cycles the style applied to just these.
    @ViewBuilder
    private func determinateSection(style: TrackStyle) -> some View {
        DemoSection(L("page.progressView.determinate")) {
            VStack(alignment: .leading, spacing: 1) {
                let fraction = animatedFraction()
                ProgressView(L("page.progressView.downloadingFiles"), value: fraction)
                    .progressViewStyle(style)

                ProgressView(value: fraction) {
                    Text(L("page.progressView.buildProgress"))
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
        DemoSection(L("page.progressView.indeterminate")) {
            VStack(alignment: .leading, spacing: 1) {
                ProgressView(L("page.progressView.connecting"))

                ProgressView {
                    Text(L("page.progressView.reticulatingSplines"))
                        .foregroundStyle(.palette.foreground)
                }

                // Pure indeterminate, no label — useful inline against
                // another control.
                HStack(spacing: 1) {
                    Text(L("page.progressView.working")).dim()
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
            ProgressView(value: animatedFraction())
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

    /// A circular gauge with its style name below it. `text` overrides the
    /// read-out (default: the fraction as a percentage).
    @ViewBuilder
    private func circularGauge(
        label: String, fraction: Double, text: String? = nil, style: GaugeStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Gauge(value: fraction) { EmptyView() } currentValueLabel: {
                Text(text ?? "\(Int((fraction * 100).rounded()))%")
            }
            .gaugeStyle(style)
            Text(label).dim()
        }
    }
}
