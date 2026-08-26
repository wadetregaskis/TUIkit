//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// Pickers that open a menu.
    @ViewBuilder
    private var menuColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            menuStyleSection
            longMenuSection
        }
    }

    /// Pickers that lay their options out in place.
    @ViewBuilder
    private var inPlaceColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            radioGroupSection
            inlineStyleSection
        }
    }

    @ViewBuilder
    private var menuStyleSection: some View {
            DemoSection("page.picker.menuStyle") {
                Picker("page.picker.favouriteFruit", selection: $fruit) {
                    Text("page.picker.apple").tag("apple")
                    Text("page.picker.banana").tag("banana")
                    Text("page.picker.cherry").tag("cherry")
                    Text("page.picker.dragonfruit").tag("dragonfruit")
                }
            }
    }

    @ViewBuilder
    private var longMenuSection: some View {
            DemoSection("page.picker.longMenu") {
                // More options than fit the screen: the drop-down windows them and
                // shows a scrollbar (wheel, arrows, Home/End, and the bar all scroll).
                Picker("page.picker.pickANumber", selection: $number) {
                    ForEach(1...200, id: \.self) { value in
                        Text("\(L("page.picker.number")) \(value)").tag(value)
                    }
                }
            }
    }

    @ViewBuilder
    private var radioGroupSection: some View {
            DemoSection("page.picker.radioGroupStyle") {
                Picker("page.picker.tshirtSize", selection: $size) {
                    Text("page.picker.small").tag("small")
                    Text("page.picker.medium").tag("medium")
                    Text("page.picker.large").tag("large")
                }
                .pickerStyle(.radioGroup)
            }
    }

    @ViewBuilder
    private var inlineStyleSection: some View {
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
    }

    @ViewBuilder
    private var dateSection: some View {
            DemoSection("page.picker.dateSection") {
                VStack(alignment: .leading, spacing: 1) {
                    DatePicker("page.newControls.dateBoth", selection: $date)
                    DatePicker("page.newControls.dateOnly", selection: $date, displayedComponents: .date)
                    DatePicker("page.newControls.timeOnly", selection: $date, displayedComponents: .hourAndMinute)
                }
            }
    }

    @ViewBuilder
    private var currentSelections: some View {
            DemoSection("page.picker.currentSelections") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("page.picker.fruitLabel", fruit)
                    ValueDisplayRow("page.picker.sizeLabel", size)
                    ValueDisplayRow("page.picker.priorityLabel", "\(priority)")
                    ValueDisplayRow("page.picker.numberLabel", "\(number)")
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // Six sections, none of them wider than about forty columns, that
            // ran straight down the page. Preferred arrangement first, then
            // progressively narrower ones — the `ViewThatFits(in: .horizontal)`
            // shape the Animation page and the track editor use. Grouped by how
            // a picker PRESENTS its choices: as a menu that opens, as options
            // laid out in place, and as a value read back.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    menuColumn
                    inPlaceColumn
                    dateSection
                    currentSelections
                }
                HStack(alignment: .top, spacing: 4) {
                    menuColumn
                    inPlaceColumn
                    VStack(alignment: .leading, spacing: 1) {
                        dateSection
                        currentSelections
                    }
                }
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        menuColumn
                        inPlaceColumn
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        dateSection
                        currentSelections
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    menuColumn
                    inPlaceColumn
                    dateSection
                    currentSelections
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
