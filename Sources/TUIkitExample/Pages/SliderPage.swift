//  TUIKit - Terminal UI Kit for Swift
//  SliderPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Slider demo page.
///
/// Shows interactive slider features including:
/// - Different track styles (block, shade, dot, bar)
/// - Various ranges and step sizes
/// - Keyboard controls
/// - Live value display
struct SliderPage: View {
    @State var volume: Double = 0.5
    @State var brightness: Double = 75
    @State var rating: Double = 3
    @State var precision: Double = 0.5

    var body: some View {
        ScrollView {
            content
        }
        .appHeader {
            DemoAppHeader(L("page.slider.title"))
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.slider.basicSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text(L("page.slider.volume")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $volume)
                    }
                }
            }

            DemoSection(L("page.slider.trackStylesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text(L("page.slider.block")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $volume).trackStyle(.block)
                    }
                    HStack(spacing: 1) {
                        Text(L("page.slider.shade")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $volume).trackStyle(.shade)
                    }
                    HStack(spacing: 1) {
                        Text(L("page.slider.dot")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $volume).trackStyle(.dot)
                    }
                    HStack(spacing: 1) {
                        Text(L("page.slider.bar")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $volume).trackStyle(.bar)
                    }
                }
            }

            DemoSection(L("page.slider.customRangesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text(L("page.slider.brightnessLabel")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $brightness, in: 0...100, step: 5)
                    }
                    HStack(spacing: 1) {
                        Text(L("page.slider.ratingLabel")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $rating, in: 1...5, step: 1)
                    }
                    HStack(spacing: 1) {
                        Text(L("page.slider.precisionLabel")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $precision, in: 0...1, step: 0.05)
                    }
                }
            }

            DemoSection(L("page.slider.currentValuesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow(L("page.slider.volume"), String(format: "%.0f%%", volume * 100))
                    ValueDisplayRow(L("page.slider.brightness"), String(format: "%.0f", brightness))
                    ValueDisplayRow(L("page.slider.rating"), String(format: "%.0f", rating))
                    ValueDisplayRow(L("page.slider.precision"), String(format: "%.2f", precision))
                }
            }

            DemoSection(L("page.slider.themedSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    // .sliderTextStyle re-themes only the percentage read-out;
                    // the track and arrows are unaffected. Shown directly below a
                    // default slider (same value) so the difference is visible:
                    // the themed "%" is bold, underlined and success-coloured.
                    HStack(spacing: 1) {
                        Text(L("page.slider.default")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $volume)
                    }
                    HStack(spacing: 1) {
                        Text(L("page.slider.themed")).foregroundStyle(.palette.foregroundSecondary)
                        Slider(value: $volume)
                            .sliderTextStyle {
                                $0.bold = true
                                $0.underline = true
                                $0.foreground = .palette.success
                            }
                    }
                }
            }

            KeyboardHelpSection(shortcuts: [
                L("page.slider.help.arrows"),
                L("page.slider.help.plusMinus"),
                L("page.slider.help.home"),
                L("page.slider.help.end"),
                L("page.slider.help.tab"),
            ])
        }
    }
}
