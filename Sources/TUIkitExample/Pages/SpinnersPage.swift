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

            DemoSection("Dots (Braille Rotation)") {
                Spinner("Loading data...")
            }

            DemoSection("Line (ASCII Rotation)") {
                Spinner("Compiling...", style: .line)
            }

            DemoSection("Bouncing (Knight Rider)") {
                Spinner("Processing...", style: .bouncing)
            }

            DemoSection("Custom Color") {
                // A literal colour, deliberately distinct from the theme accent
                // (the default spinner colour) so the customisation is visible —
                // the green theme's `.palette.success` is nearly identical to its
                // `.palette.accent`, which made this look uncustomised.
                Spinner("Installing...", style: .bouncing, color: .magenta)
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Spinners")
        }
    }
}
