//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PickerPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
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
    @State var number: Int = 1
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.picker.menuStyle") {
                Picker("page.picker.favouriteFruit", selection: $fruit) {
                    Text("page.picker.apple").tag("apple")
                    Text("page.picker.banana").tag("banana")
                    Text("page.picker.cherry").tag("cherry")
                    Text("page.picker.dragonfruit").tag("dragonfruit")
                }
            }

            DemoSection("page.picker.longMenu") {
                // More options than fit the screen: the drop-down windows them and
                // shows a scrollbar (wheel, arrows, Home/End, and the bar all scroll).
                Picker("page.picker.pickANumber", selection: $number) {
                    ForEach(1...200, id: \.self) { value in
                        Text("\(L("page.picker.number")) \(value)").tag(value)
                    }
                }
            }

            DemoSection("page.picker.radioGroupStyle") {
                Picker("page.picker.tshirtSize", selection: $size) {
                    Text("page.picker.small").tag("small")
                    Text("page.picker.medium").tag("medium")
                    Text("page.picker.large").tag("large")
                }
                .pickerStyle(.radioGroup)
            }

            DemoSection("page.picker.inlineStyle") {
                Picker("page.picker.priority", selection: $priority) {
                    ForEach(1..<4) { level in
                        Text("\(L("page.picker.level")) \(level)").tag(level)
                    }
                }
                .pickerStyle(.inline)
                // .pickerTextStyle re-themes the picker's label + option text.
                .pickerTextStyle { $0.foreground = .palette.accent }
            }

            // A DatePicker is a picker for a date/time, so it belongs here. It
            // renders as an inline field: Left/Right pick a component, Up/Down
            // or typing digits edit it, Page Up/Down move it by a coarse step
            // and Home/End to its limits (the active field pulses when focused).
            DemoSection("page.picker.dateSection") {
                VStack(alignment: .leading, spacing: 1) {
                    DatePicker("page.newControls.dateBoth", selection: $date)
                    DatePicker("page.newControls.dateOnly", selection: $date, displayedComponents: .date)
                    DatePicker("page.newControls.timeOnly", selection: $date, displayedComponents: .hourAndMinute)
                }
            }

            DemoSection("page.picker.currentSelections") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("page.picker.fruitLabel", fruit)
                    ValueDisplayRow("page.picker.sizeLabel", size)
                    ValueDisplayRow("page.picker.priorityLabel", "\(priority)")
                    ValueDisplayRow("page.picker.numberLabel", "\(number)")
                }
            }

            KeyboardHelpSection(
                "page.picker.pickerNavigation",
                shortcuts: [
                    "page.picker.help.moveFocus",
                    "page.picker.help.openMenu",
                    "page.picker.help.moveChoose",
                    "page.picker.help.dateFields",
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.picker")
        }
    }
}
