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

            DemoSection("Determinate") {
                // Both bars animate slowly via `animatedFraction` — they
                // share the same wall-clock phase so they stay in sync,
                // and the PulseTimer's ~10 Hz re-render makes the
                // animation look continuous despite being state-less.
                // The `s` shortcut cycles the style applied to just these two.
                VStack(alignment: .leading, spacing: 1) {
                    let fraction = animatedFraction()
                    ProgressView("Downloading files…", value: fraction)
                        .progressViewStyle(current.style)

                    ProgressView(value: fraction) {
                        Text("Build progress")
                            .foregroundStyle(.palette.foreground)
                    } currentValueLabel: {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                    .progressViewStyle(current.style)
                }
            }

            DemoSection("Indeterminate (no known total)") {
                VStack(alignment: .leading, spacing: 1) {
                    ProgressView("Connecting…")

                    ProgressView {
                        Text("Reticulating splines")
                            .foregroundStyle(.palette.foreground)
                    }

                    // Pure indeterminate, no label — useful inline against
                    // another control.
                    HStack(spacing: 1) {
                        Text("Working").dim()
                        ProgressView()
                    }
                }
            }

            DemoSection("Determinate styles") {
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
                }
            }

            DemoSection("Indeterminate animations") {
                VStack(alignment: .leading, spacing: 0) {
                    indeterminateRow(label: "sweep       ", style: .sweep)
                    indeterminateRow(label: "barberPole  ", style: .barberPole)
                    indeterminateRow(label: "pulse       ", style: .pulse)
                    indeterminateRow(label: "knightRider ", style: .knightRider)
                    indeterminateRow(label: "gradient    ", style: .gradient)
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Progress Views")
        }
        // Merges with the page's back / scroll items. Cycles only the top
        // "Determinate" section's style; the style catalogues below stay put.
        .statusBarItems {
            StatusBarItem(shortcut: "s", label: "style: \(current.name)") {
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
}
