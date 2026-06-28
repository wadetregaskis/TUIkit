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
    @State var number: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.picker.menuStyle")) {
                Picker(L("page.picker.favouriteFruit"), selection: $fruit) {
                    Text(L("page.picker.apple")).tag("apple")
                    Text(L("page.picker.banana")).tag("banana")
                    Text(L("page.picker.cherry")).tag("cherry")
                    Text(L("page.picker.dragonfruit")).tag("dragonfruit")
                }
            }

            DemoSection(L("page.picker.longMenu")) {
                // More options than fit the screen: the drop-down windows them and
                // shows a scrollbar (wheel, arrows, Home/End, and the bar all scroll).
                Picker(L("page.picker.pickANumber"), selection: $number) {
                    ForEach(1...200, id: \.self) { value in
                        Text("\(L("page.picker.number")) \(value)").tag(value)
                    }
                }
            }

            DemoSection(L("page.picker.radioGroupStyle")) {
                Picker(L("page.picker.tshirtSize"), selection: $size) {
                    Text(L("page.picker.small")).tag("small")
                    Text(L("page.picker.medium")).tag("medium")
                    Text(L("page.picker.large")).tag("large")
                }
                .pickerStyle(.radioGroup)
            }

            DemoSection(L("page.picker.inlineStyle")) {
                Picker(L("page.picker.priority"), selection: $priority) {
                    ForEach(1..<4) { level in
                        Text("\(L("page.picker.level")) \(level)").tag(level)
                    }
                }
                .pickerStyle(.inline)
                // .pickerTextStyle re-themes the picker's label + option text.
                .pickerTextStyle { $0.foreground = .palette.accent }
            }

            DemoSection(L("page.picker.currentSelections")) {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow(L("page.picker.fruitLabel"), fruit)
                    ValueDisplayRow(L("page.picker.sizeLabel"), size)
                    ValueDisplayRow(L("page.picker.priorityLabel"), "\(priority)")
                    ValueDisplayRow(L("page.picker.numberLabel"), "\(number)")
                }
            }

            KeyboardHelpSection(
                L("page.picker.pickerNavigation"),
                shortcuts: [
                    L("page.picker.help.moveFocus"),
                    L("page.picker.help.openMenu"),
                    L("page.picker.help.moveChoose"),
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.picker.title"))
        }
    }
}
