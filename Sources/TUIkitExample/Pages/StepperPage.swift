//  TUIKit - Terminal UI Kit for Swift
//  StepperPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Stepper demo page.
///
/// Shows interactive stepper features including:
/// - Basic value stepping
/// - Range constraints
/// - Custom step sizes
/// - Custom callbacks
/// - Keyboard controls
struct StepperPage: View {
    @State var quantity: Int = 1
    @State var rating: Int = 3
    @State var volume: Int = 50
    @State var colorIndex: Int = 0

    let colors = ["Red", "Green", "Blue", "Yellow", "Purple"]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Basic Stepper (+ .stepperTextStyle)") {
                // The label renders inline (SwiftUI parity); no separate Text needed.
                Stepper("Quantity", value: $quantity)
                    // .stepperTextStyle re-themes the stepper's text (arrows unaffected).
                    .stepperTextStyle { $0.bold = true; $0.foreground = .palette.accent }
            }

            DemoSection("With Range Constraints") {
                VStack(alignment: .leading, spacing: 1) {
                    Stepper("Rating (1-5)", value: $rating, in: 1...5)
                    Stepper("Volume (0-100, step 10)", value: $volume, in: 0...100, step: 10)
                }
            }

            DemoSection("With Custom Callbacks") {
                HStack(spacing: 1) {
                    Stepper(
                        "Color",
                        onIncrement: {
                            colorIndex = (colorIndex + 1) % colors.count
                        },
                        onDecrement: {
                            colorIndex = (colorIndex - 1 + colors.count) % colors.count
                        }
                    )
                    Text(colors[colorIndex]).foregroundStyle(.palette.accent)
                }
            }

            DemoSection("Current Values") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("Quantity:", "\(quantity)")
                    ValueDisplayRow("Rating:", "\(rating)")
                    ValueDisplayRow("Volume:", "\(volume)")
                    ValueDisplayRow("Color:", colors[colorIndex])
                }
            }

            KeyboardHelpSection(shortcuts: [
                "[<-] [->] Decrease/Increase by step",
                "[-] [+] Decrease/Increase by step",
                "[Home] Jump to minimum (if range defined)",
                "[End] Jump to maximum (if range defined)",
                "[Tab] Move to next stepper",
            ])

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Stepper Demo")
        }
    }
}
