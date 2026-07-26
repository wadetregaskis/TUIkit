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
            DemoAppHeader(L("menu.item.sliders"))
        }
    }

    /// A slider's own label, in the page's quiet caption colour.
    private func caption(_ text: String) -> some View {
        Text(text).foregroundStyle(.palette.foregroundSecondary)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            // Each row's caption is the SLIDER'S OWN label, not a `Text`
            // alongside it: a slider draws its label to the left of the track
            // and shortens the track to fit, as macOS SwiftUI does. Written as
            // an adjacent `Text` in an HStack these rows looked identical, but
            // hand-rolled what the control now does itself.
            DemoSection(L("page.slider.basicSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Slider(value: $volume, label: { caption(L("page.slider.volume")) })
                }
            }

            DemoSection(L("page.slider.trackStylesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Slider(value: $volume, label: { caption(L("page.slider.block")) })
                        .trackStyle(.block)
                    // Truth in labelling: the row that says "shade" renders
                    // `.shade`, exactly as the ProgressView demo's "shade"
                    // row does — a style name must look the same on every
                    // control. (`.shade`'s ▓ fill reads close to `.block`
                    // on most fonts by design; the visibly graded look is
                    // the separate `.shadeRamp` row below.)
                    Slider(value: $volume, label: { caption(L("page.slider.shade")) })
                        .trackStyle(.shade)
                    Slider(value: $volume, label: { caption(L("page.slider.shadeRamp")) })
                        .trackStyle(.shadeRamp())
                    Slider(value: $volume, label: { caption(L("page.slider.dot")) })
                        .trackStyle(.dot)
                    Slider(value: $volume, label: { caption(L("page.slider.bar")) })
                        .trackStyle(.bar)
                }
            }

            // The same custom-style editor as the Progress page, previewing on
            // a Slider — one TrackConfiguration drives both controls.
            DemoSection(L("page.trackEditor.section")) {
                TrackStyleEditor(preview: .slider)
            }

            DemoSection(L("page.slider.customRangesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Slider(
                        value: $brightness, in: 0...100, step: 5,
                        label: { caption(L("page.slider.brightnessLabel")) })
                    Slider(
                        value: $rating, in: 1...5, step: 1,
                        label: { caption(L("page.slider.ratingLabel")) })
                    Slider(
                        value: $precision, in: 0...1, step: 0.05,
                        label: { caption(L("page.slider.precisionLabel")) })
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
                    // Three sliders at the same value so the differences show:
                    //  • default;
                    //  • .sliderTextStyle re-themes only the "%" read-out (bold,
                    //    underlined, success-coloured — the underline sits under
                    //    the digits only, not the padded field);
                    //  • .tint recolours the slider ITSELF — the filled rail and
                    //    the knob draw in the tint (the empty rail stays quiet).
                    Slider(value: $volume, label: { caption(L("page.slider.default")) })
                    Slider(value: $volume, label: { caption(L("page.slider.themed")) })
                        .sliderTextStyle {
                            $0.bold = true
                            $0.underline = true
                            $0.foreground = .palette.success
                        }
                    Slider(value: $volume, label: { caption(L("page.slider.tinted")) })
                        .tint(.rgb(255, 130, 40))
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
