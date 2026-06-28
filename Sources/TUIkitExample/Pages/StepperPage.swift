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

    var colors: [String] {
        [L("page.stepper.colorRed"), L("page.stepper.colorGreen"), L("page.stepper.colorBlue"),
         L("page.stepper.colorYellow"), L("page.stepper.colorPurple")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.stepper.basicSection")) {
                // The label renders inline (SwiftUI parity); no separate Text needed.
                Stepper(L("page.stepper.quantity"), value: $quantity)
                    // .stepperTextStyle re-themes the stepper's text (arrows unaffected).
                    .stepperTextStyle { $0.bold = true; $0.foreground = .palette.accent }
            }

            DemoSection(L("page.stepper.rangeSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Stepper(L("page.stepper.rating"), value: $rating, in: 1...5)
                    Stepper(L("page.stepper.volume"), value: $volume, in: 0...100, step: 10)
                }
            }

            DemoSection(L("page.stepper.callbacksSection")) {
                HStack(spacing: 1) {
                    Stepper(
                        L("page.stepper.color"),
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

            DemoSection(L("page.stepper.currentValuesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("\(L("page.stepper.quantity")):", "\(quantity)")
                    ValueDisplayRow("\(L("page.stepper.ratingLabel")):", "\(rating)")
                    ValueDisplayRow("\(L("page.stepper.volumeLabel")):", "\(volume)")
                    ValueDisplayRow("\(L("page.stepper.colorLabel")):", colors[colorIndex])
                }
            }

            KeyboardHelpSection(shortcuts: [
                "[<-] [->] \(L("page.stepper.helpStep"))",
                "[-] [+] \(L("page.stepper.helpStep"))",
                "[Home] \(L("page.stepper.helpHome"))",
                "[End] \(L("page.stepper.helpEnd"))",
                "[Tab] \(L("page.stepper.helpTab"))",
            ])

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.stepper.title"))
        }
    }
}
