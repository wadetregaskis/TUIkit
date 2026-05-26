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
                    Text("Style       Determinate         Indeterminate").dim()
                    HStack(spacing: 1) {
                        Text("block    ").dim()
                        ProgressView(value: 0.6).progressViewStyle(.block)
                        ProgressView().progressViewStyle(.block)
                    }
                    HStack(spacing: 1) {
                        Text("blockFine").dim()
                        ProgressView(value: 0.6).progressViewStyle(.blockFine)
                        ProgressView().progressViewStyle(.blockFine)
                    }
                    HStack(spacing: 1) {
                        Text("shade    ").dim()
                        ProgressView(value: 0.6).progressViewStyle(.shade)
                        ProgressView().progressViewStyle(.shade)
                    }
                    HStack(spacing: 1) {
                        Text("bar      ").dim()
                        ProgressView(value: 0.6).progressViewStyle(.bar)
                        ProgressView().progressViewStyle(.bar)
                    }
                    HStack(spacing: 1) {
                        Text("dot      ").dim()
                        ProgressView(value: 0.6).progressViewStyle(.dot)
                        ProgressView().progressViewStyle(.dot)
                    }
                }
            }

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Progress Views")
        }
    }
}
