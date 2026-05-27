//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ProgressViewPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Progress-view demo page.
///
/// Shows ``ProgressView`` in its determinate (a known fraction) and
/// indeterminate (no known total) modes, across every built-in style.
struct ProgressViewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Determinate") {
                VStack(alignment: .leading, spacing: 1) {
                    ProgressView("Downloading files…", value: 0.73)

                    ProgressView(value: 0.4) {
                        Text("Build progress")
                            .foregroundStyle(.palette.foreground)
                    } currentValueLabel: {
                        Text("40%").foregroundStyle(.palette.foregroundSecondary)
                    }
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

            DemoSection("Styles (determinate)") {
                VStack(alignment: .leading, spacing: 0) {
                    // Header and data rows share the same HStack layout so
                    // the columns line up. Each progress view gets an
                    // explicit `.frame(width:)` because progress bars are
                    // flexible by default — without a frame the two would
                    // share whatever space is left after the label,
                    // unevenly, and the "Indeterminate" header would land
                    // on the wrong column.
                    HStack(spacing: 1) {
                        Text("Style    ").dim()
                        Text("  Determinate     ").dim().frame(width: 20)
                        Text(" Indeterminate    ").dim().frame(width: 20)
                    }
                    styleRow(label: "block    ", style: .block)
                    styleRow(label: "blockFine", style: .blockFine)
                    styleRow(label: "shade    ", style: .shade)
                    styleRow(label: "bar      ", style: .bar)
                    styleRow(label: "dot      ", style: .dot)
                }
            }

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Progress Views")
        }
    }

    /// A `[label  | determinate bar | indeterminate bar]` row laid out at
    /// fixed column widths so the header matches the data columns.
    @ViewBuilder
    private func styleRow(label: String, style: TrackStyle) -> some View {
        HStack(spacing: 1) {
            Text(label).dim()
            ProgressView(value: 0.6).progressViewStyle(style).frame(width: 20)
            ProgressView().progressViewStyle(style).frame(width: 20)
        }
    }
}
