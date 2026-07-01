//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SpinnersPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A demo page showing all Spinner styles.
struct SpinnersPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.spinners.dotsSection")) {
                Spinner(L("page.spinners.loadingData"))
            }

            DemoSection(L("page.spinners.lineSection")) {
                Spinner(L("page.spinners.compiling"), style: .line)
            }

            DemoSection(L("page.spinners.bouncingSection")) {
                Spinner(L("page.spinners.processing"), style: .bouncing)
            }

            // The full style catalogue. The labels are the API case names (an
            // API surface, left untranslated), like the ProgressView catalogue.
            DemoSection(L("page.spinners.moreSection")) {
                VStack(alignment: .leading, spacing: 0) {
                    spinnerRow("pie", .pie)
                    spinnerRow("beachball", .beachball)
                    spinnerRow("box", .box)
                    spinnerRow("bars", .bars)
                    spinnerRow("blockWedge", .blockWedge)
                    spinnerRow("moon", .moon)
                    spinnerRow("earth", .earth)
                    spinnerRow("clock", .clock)
                    spinnerRow("custom(\"123432\")", .custom("123432"))
                }
            }

            DemoSection(L("page.spinners.customColorSection")) {
                // A literal colour, deliberately distinct from the theme accent
                // (the default spinner colour) so the customisation is visible —
                // the green theme's `.palette.success` is nearly identical to its
                // `.palette.accent`, which made this look uncustomised.
                Spinner(L("page.spinners.installing"), style: .bouncing, color: .magenta)
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.spinners.title"))
        }
    }

    /// A `[spinner  style-name]` row for the style catalogue.
    @ViewBuilder
    private func spinnerRow(_ name: String, _ style: SpinnerStyle) -> some View {
        HStack(spacing: 1) {
            Spinner(style: style)
            Text(name).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
