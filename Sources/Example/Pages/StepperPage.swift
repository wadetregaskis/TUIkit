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
    @State var bigValue: Int = 0

    var colors: [String] {
        [L("page.stepper.colorRed"), L("page.stepper.colorGreen"), L("page.stepper.colorBlue"),
         L("page.stepper.colorYellow"), L("page.stepper.colorPurple")]
    }

    // The five sections, named once and placed by whichever arrangement fits.
    // `ViewThatFits` builds every candidate, so writing a section out per
    // arrangement would be several copies of the same bindings to keep in step.

    @ViewBuilder
    private var basicSection: some View {
        DemoSection("page.stepper.basicSection") {
            // The label renders inline (SwiftUI parity); no separate Text needed.
            Stepper("page.stepper.quantity", value: $quantity)
                // .stepperTextStyle re-themes the stepper's text (arrows unaffected).
                .stepperTextStyle { $0.bold = true; $0.foreground = .palette.accent }
        }
    }

    @ViewBuilder
    private var rangeSection: some View {
        DemoSection("page.stepper.rangeSection") {
            VStack(alignment: .leading, spacing: 1) {
                Stepper("page.stepper.rating", value: $rating, in: 1...5)
                Stepper("page.stepper.volume", value: $volume, in: 0...100, step: 10)
            }
        }
    }

    @ViewBuilder
    private var callbacksSection: some View {
        DemoSection("page.stepper.callbacksSection") {
            HStack(spacing: 1) {
                Stepper(
                    "page.stepper.color",
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
    }

    @ViewBuilder
    private var shiftSection: some View {
        DemoSection("page.stepper.shiftSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.stepper.shiftDescription")
                    .foregroundStyle(.palette.foregroundSecondary)
                // .shiftStepMultiplier scales the step while Shift is held,
                // so a Shift+arrow jumps by 10× the normal step (1 → 10 here).
                Stepper("page.stepper.bigValue", value: $bigValue, in: 0...1000, step: 1)
                    .shiftStepMultiplier(10)
                ValueDisplayRow("page.stepper.bigValueLabel", "\(bigValue)")
            }
        }
    }

    @ViewBuilder
    private var currentValues: some View {
        DemoSection("page.stepper.currentValuesSection") {
            VStack(alignment: .leading, spacing: 1) {
                ValueDisplayRow("\(L("page.stepper.quantity")):", "\(quantity)")
                ValueDisplayRow("\(L("page.stepper.ratingLabel")):", "\(rating)")
                ValueDisplayRow("\(L("page.stepper.volumeLabel")):", "\(volume)")
                ValueDisplayRow("\(L("page.stepper.colorLabel")):", colors[colorIndex])
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // Five short sections that ran straight down the page and used a
            // third of a wide terminal. Preferred arrangement first, then
            // progressively narrower ones — the `ViewThatFits(in: .horizontal)`
            // shape the Animation page and the track editor use. The shift
            // section carries a sentence of prose, so it keeps a column of its
            // own until there is no room for one.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        basicSection
                        rangeSection
                        callbacksSection
                    }
                    shiftSection
                    currentValues
                }
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        basicSection
                        rangeSection
                        callbacksSection
                        shiftSection
                    }
                    currentValues
                }
                VStack(alignment: .leading, spacing: 1) {
                    basicSection
                    rangeSection
                    callbacksSection
                    shiftSection
                    currentValues
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
            DemoAppHeader("menu.item.steppers")
        }
    }
}
