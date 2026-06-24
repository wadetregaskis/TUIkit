//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PickerPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Picker demo page.
///
/// Shows the `Picker` control across its styles:
/// - Menu style — a collapsed control that opens a drop-down list
/// - Radio-group style — every option shown inline
/// - Inline style with `ForEach`-generated options
/// - Live state changes demonstrating `@State` persistence across re-renders
struct PickerPage: View {
    @State var fruit: String = "apple"
    @State var size: String = "medium"
    @State var priority: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Menu Style (Drop-down)") {
                Picker("Favourite Fruit", selection: $fruit) {
                    Text("Apple").tag("apple")
                    Text("Banana").tag("banana")
                    Text("Cherry").tag("cherry")
                    Text("Dragonfruit").tag("dragonfruit")
                }
            }

            DemoSection("Radio-group Style") {
                Picker("T-shirt Size", selection: $size) {
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
                .pickerStyle(.radioGroup)
            }

            DemoSection("Inline Style (+ .pickerTextStyle)") {
                Picker("Priority", selection: $priority) {
                    ForEach(1..<4) { level in
                        Text("Level \(level)").tag(level)
                    }
                }
                .pickerStyle(.inline)
                // .pickerTextStyle re-themes the picker's label + option text.
                .pickerTextStyle { $0.foreground = .palette.accent }
            }

            DemoSection("Current Selections") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("Fruit:", fruit)
                    ValueDisplayRow("Size:", size)
                    ValueDisplayRow("Priority:", "\(priority)")
                }
            }

            KeyboardHelpSection(
                "Picker Navigation",
                shortcuts: [
                    "Use [Tab] to move focus between pickers",
                    "Use [Enter], [Space] or [↓] to open a menu picker",
                    "Use [↑/↓] to move, [Enter] to choose, [Esc] to cancel",
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Picker Demo")
        }
    }
}
