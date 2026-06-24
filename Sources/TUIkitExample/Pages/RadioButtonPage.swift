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

            DemoSection("Color Selection (Vertical)") {
                RadioButtonGroup(selection: $colorChoice) {
                    RadioButtonItem("red", "Red")
                    RadioButtonItem("green", "Green")
                    RadioButtonItem("blue", "Blue")
                    RadioButtonItem("yellow", "Yellow")
                }
            }

            DemoSection("Size Selection (Vertical)") {
                RadioButtonGroup(selection: $sizeChoice) {
                    RadioButtonItem("small", "Small")
                    RadioButtonItem("medium", "Medium")
                    RadioButtonItem("large", "Large")
                }
            }

            DemoSection("Layout Style (Horizontal, + .radioButtonTextStyle)") {
                RadioButtonGroup(selection: $layoutChoice, orientation: .horizontal) {
                    RadioButtonItem("vertical", "Vertical")
                    RadioButtonItem("horizontal", "Horizontal")
                }
                // .radioButtonTextStyle re-themes the labels (●/○ indicator unaffected).
                .radioButtonTextStyle { $0.bold = true; $0.foreground = .palette.accent }
            }

            DemoSection("Disabled Group") {
                // Several items so both disabled states show: the selected one
                // (●, dimmed) and the unselected ones (◌, the dotted "not
                // pickable" circle).
                RadioButtonGroup(selection: Binding(get: { "selected" }, set: { _ in })) {
                    RadioButtonItem("selected", "This group is disabled (selected)")
                    RadioButtonItem("a", "An unavailable option")
                    RadioButtonItem("b", "Another unavailable option")
                }
                .disabled()
            }

            DemoSection("Current Selections") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("Color:", colorChoice)
                    ValueDisplayRow("Size:", sizeChoice)
                    ValueDisplayRow("Layout:", layoutChoice)
                }
            }

            KeyboardHelpSection(
                "Focus Navigation",
                shortcuts: [
                    "Use [↑/↓] to navigate vertically",
                    "Use [←/→] to navigate horizontally",
                    "Use [Enter] or [Space] to select",
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Radio Buttons Demo")
        }
    }
}
