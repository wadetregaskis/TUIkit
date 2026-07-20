//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.radioButton.section.colorVertical")) {
                RadioButtonGroup(selection: $colorChoice) {
                    RadioButtonItem("red", L("page.radioButton.red"))
                    RadioButtonItem("green", L("page.radioButton.green"))
                    RadioButtonItem("blue", L("page.radioButton.blue"))
                    RadioButtonItem("yellow", L("page.radioButton.yellow"))
                }
            }

            DemoSection(L("page.radioButton.section.sizeVertical")) {
                RadioButtonGroup(selection: $sizeChoice) {
                    RadioButtonItem("small", L("page.radioButton.small"))
                    RadioButtonItem("medium", L("page.radioButton.medium"))
                    RadioButtonItem("large", L("page.radioButton.large"))
                }
            }

            DemoSection(L("page.radioButton.section.layoutHorizontal")) {
                RadioButtonGroup(selection: $layoutChoice, orientation: .horizontal) {
                    RadioButtonItem("vertical", L("page.radioButton.vertical"))
                    RadioButtonItem("horizontal", L("page.radioButton.horizontal"))
                }
                // .radioButtonTextStyle re-themes the labels (●/○ indicator unaffected).
                .radioButtonTextStyle { $0.bold = true; $0.foreground = .palette.accent }
            }

            DemoSection(L("page.radioButton.section.disabled")) {
                // Several items so both disabled states show: the selected one
                // (●, dimmed) and the unselected ones (◌, the dotted "not
                // pickable" circle).
                RadioButtonGroup(selection: Binding(get: { "selected" }, set: { _ in })) {
                    RadioButtonItem("selected", L("page.radioButton.disabledSelected"))
                    RadioButtonItem("a", L("page.radioButton.unavailable"))
                    RadioButtonItem("b", L("page.radioButton.anotherUnavailable"))
                }
                .disabled()
            }

            DemoSection(L("page.radioButton.section.currentSelections")) {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("\(L("page.radioButton.color")):", colorChoice)
                    ValueDisplayRow("\(L("page.radioButton.size")):", sizeChoice)
                    ValueDisplayRow("\(L("page.radioButton.layout")):", layoutChoice)
                }
            }

            KeyboardHelpSection(
                L("page.radioButton.section.focusNav"),
                shortcuts: [
                    L("page.radioButton.help.navVertical"),
                    L("page.radioButton.help.navHorizontal"),
                    L("page.radioButton.help.select"),
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.radioButton.header"))
        }
    }
}
