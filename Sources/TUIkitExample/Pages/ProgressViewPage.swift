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

    var body: some View {
        let current = Self.cyclableStyles[determinateStyleIndex]
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.progressView.determinate")) {
                // Both bars animate slowly via `animatedFraction` — they
                // share the same wall-clock phase so they stay in sync,
                // and the PulseTimer's ~10 Hz re-render makes the
                // animation look continuous despite being state-less.
                // The `s` shortcut cycles the style applied to just these two.
                VStack(alignment: .leading, spacing: 1) {
                    let fraction = animatedFraction()
                    ProgressView(L("page.progressView.downloadingFiles"), value: fraction)
                        .progressViewStyle(current.style)

                    ProgressView(value: fraction) {
                        Text(L("page.progressView.buildProgress"))
                            .foregroundStyle(.palette.foreground)
                    } currentValueLabel: {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                    .progressViewStyle(current.style)
                }
            }

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

            DemoSection(L("page.progressView.determinateStyles")) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 1) {
                        Text("Style       ").dim()
                        Text("    Progress       ").dim().frame(width: 24)
                    }
                    determinateRow(label: "block       ", style: .block)
                    determinateRow(label: "blockFine   ", style: .blockFine)
                    determinateRow(label: "shade       ", style: .shade)
                    determinateRow(label: "bar         ", style: .bar)
                    determinateRow(label: "dot         ", style: .dot)
                    determinateRow(label: "braille     ", style: .braille)
                    determinateRow(
                        label: "shadeRamp   ",
                        style: .shadeRamp(gradient: nil)
                    )
                    determinateRow(
                        label: "shadeRamp(g)",
                        style: .shadeRamp(gradient: [
                            .rgb(255, 80, 80),
                            .rgb(255, 200, 80),
                            .rgb(80, 220, 120),
                        ])
                    )
                    determinateRow(
                        label: "threeSegment",
                        style: .threeSegment(
                            leading: "Sw",
                            middle: "i",
                            trailing: "ft",
                            emptyFill: "·"
                        )
                    )
                    // A hand-rolled `.custom` recipe: a shade-ramp fill with a
                    // solid background for the unfilled region — a combination
                    // no named preset provides (showcasing TrackConfiguration).
                    determinateRow(
                        label: "custom      ",
                        style: .custom(
                            TrackConfiguration(
                                fullGlyph: "█", partialRamp: ["░", "▒", "▓"],
                                emptyStyle: .background))
                    )
                }
            }

            DemoSection(L("page.progressView.indeterminateAnimations")) {
                VStack(alignment: .leading, spacing: 0) {
                    indeterminateRow(label: "sweep       ", style: .sweep)
                    indeterminateRow(label: "barberPole  ", style: .barberPole)
                    indeterminateRow(label: "pulse       ", style: .pulse)
                    indeterminateRow(label: "knightRider ", style: .knightRider)
                    indeterminateRow(label: "gradient    ", style: .gradient)
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
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
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
    @ViewBuilder
    private func gaugeRow(label: String, fraction: Double, style: GaugeStyle) -> some View {
        HStack(spacing: 1) {
            Text(label).dim()
            Gauge(value: fraction) { EmptyView() } currentValueLabel: {
                Text("\(Int((fraction * 100).rounded()))%")
            }
            .gaugeStyle(style)
            .frame(width: 28)
        }
    }

    /// A circular gauge with its style name below it.
    @ViewBuilder
    private func circularGauge(label: String, fraction: Double, style: GaugeStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Gauge(value: fraction) { EmptyView() } currentValueLabel: {
                Text("\(Int((fraction * 100).rounded()))%")
            }
            .gaugeStyle(style)
            Text(label).dim()
        }
    }
}
