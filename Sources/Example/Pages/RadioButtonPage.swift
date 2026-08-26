//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RadioButtonPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Radio button group demo page.
///
/// Shows interactive radio button features including:
/// - Vertical layout (default)
/// - Horizontal layout
/// - Single-selection with binding
/// - Disabled radio groups
/// - Focus navigation with arrow keys
/// - Live state changes demonstrating `@State` persistence across re-renders
struct RadioButtonPage: View {
    @State var colorChoice: String = "blue"
    @State var sizeChoice: String = "medium"
    @State var layoutChoice: String = "vertical"

    // The five sections, each named once and placed by whichever arrangement
    // fits. Extracted rather than duplicated per arrangement: `ViewThatFits`
    // builds every candidate, so a section written out four times would be four
    // separate pieces of state to keep in step.

    @ViewBuilder
    private var colorGroup: some View {
        DemoSection("page.radioButton.section.colorVertical") {
            RadioButtonGroup(selection: $colorChoice) {
                RadioButtonItem("red", "page.radioButton.red")
                RadioButtonItem("green", "page.radioButton.green")
                RadioButtonItem("blue", "page.radioButton.blue")
                RadioButtonItem("yellow", "page.radioButton.yellow")
            }
        }
    }

    @ViewBuilder
    private var sizeGroup: some View {
        DemoSection("page.radioButton.section.sizeVertical") {
            RadioButtonGroup(selection: $sizeChoice) {
                RadioButtonItem("small", "page.radioButton.small")
                RadioButtonItem("medium", "page.radioButton.medium")
                RadioButtonItem("large", "page.radioButton.large")
            }
        }
    }

    @ViewBuilder
    private var layoutGroup: some View {
        DemoSection("page.radioButton.section.layoutHorizontal") {
            RadioButtonGroup(selection: $layoutChoice, orientation: .horizontal) {
                RadioButtonItem("vertical", "page.radioButton.vertical")
                RadioButtonItem("horizontal", "page.radioButton.horizontal")
            }
            // .radioButtonTextStyle re-themes the labels (●/○ indicator unaffected).
            .radioButtonTextStyle { $0.bold = true; $0.foreground = .palette.accent }
        }
    }

    @ViewBuilder
    private var disabledGroup: some View {
        DemoSection("page.radioButton.section.disabled") {
            // Several items so both disabled states show: the selected one
            // (●, dimmed) and the unselected ones (◌, the dotted "not
            // pickable" circle).
            RadioButtonGroup(selection: Binding(get: { "selected" }, set: { _ in })) {
                RadioButtonItem("selected", "page.radioButton.disabledSelected")
                RadioButtonItem("a", "page.radioButton.unavailable")
                RadioButtonItem("b", "page.radioButton.anotherUnavailable")
            }
            .disabled()
        }
    }

    @ViewBuilder
    private var currentSelections: some View {
        DemoSection("page.radioButton.section.currentSelections") {
            VStack(alignment: .leading, spacing: 1) {
                ValueDisplayRow("\(L("page.radioButton.color")):", colorChoice)
                ValueDisplayRow("\(L("page.radioButton.size")):", sizeChoice)
                ValueDisplayRow("\(L("page.radioButton.layout")):", layoutChoice)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // Five short groups that used to run straight down the page, using
            // a third of a wide terminal and none of the rest. Preferred
            // arrangement first, then progressively narrower ones — the
            // `ViewThatFits(in: .horizontal)` shape the Animation page and the
            // track editor use. The groups are paired by kind: the two plain
            // vertical groups, then the two that demonstrate a variation
            // (horizontal orientation, disabled), then the readout.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    colorGroup
                    sizeGroup
                    layoutGroup
                    disabledGroup
                    currentSelections
                }
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        colorGroup
                        sizeGroup
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        layoutGroup
                        disabledGroup
                    }
                    currentSelections
                }
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        colorGroup
                        sizeGroup
                        layoutGroup
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        disabledGroup
                        currentSelections
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    colorGroup
                    sizeGroup
                    layoutGroup
                    disabledGroup
                    currentSelections
                }
            }

            KeyboardHelpSection(
                "page.radioButton.section.focusNav",
                shortcuts: [
                    "page.radioButton.help.navVertical",
                    "page.radioButton.help.navHorizontal",
                    "page.radioButton.help.jump",
                    "page.radioButton.help.fast",
                    "page.radioButton.help.select",
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.radioButtons")
        }
    }
}
