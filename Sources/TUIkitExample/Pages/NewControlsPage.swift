//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NewControlsPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Demonstrates the SwiftUI-parity controls added most recently: ``Gauge``,
/// ``Link``, ``TextEditor``, and ``DatePicker``.
///
/// The section headers are the control type names (an API surface, left
/// untranslated); the surrounding copy is localized.
struct NewControlsPage: View {
    @State private var gaugeValue: Double = 0.42
    @State private var notes: String = L("page.newControls.editorSample")
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // Gauge — a value within a range, driven live by the slider below.
            DemoSection("Gauge") {
                VStack(alignment: .leading, spacing: 1) {
                    Gauge(value: gaugeValue) {
                        Text(L("page.newControls.gaugeLabel"))
                    } currentValueLabel: {
                        Text("\(Int((gaugeValue * 100).rounded()))%")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("100")
                    }
                    Text(L("page.newControls.gaugeHint")).foregroundStyle(.palette.foregroundSecondary)
                    Slider(value: $gaugeValue, in: 0...1)
                }
            }

            // Link — focusable, opens a URL on activation.
            DemoSection("Link") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.newControls.linkHint")).foregroundStyle(.palette.foregroundSecondary)
                    Link("swift.org", destination: URL(string: "https://swift.org")!)
                    Link(destination: URL(string: "https://github.com/apple/swift")!) {
                        Label("apple/swift", systemImage: "swift")
                    }
                }
            }

            // TextEditor — multi-line editable text.
            DemoSection("TextEditor") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.newControls.editorHint")).foregroundStyle(.palette.foregroundSecondary)
                    TextEditor(text: $notes)
                        .frame(height: 5)
                        .border()
                }
            }

            // DatePicker — an inline editable date/time field, in its variants.
            DemoSection("DatePicker") {
                VStack(alignment: .leading, spacing: 1) {
                    DatePicker(L("page.newControls.dateBoth"), selection: $date)
                    DatePicker(L("page.newControls.dateOnly"), selection: $date, displayedComponents: .date)
                    DatePicker(L("page.newControls.timeOnly"), selection: $date, displayedComponents: .hourAndMinute)
                }
            }

            KeyboardHelpSection(shortcuts: [
                "[Tab] \(L("page.newControls.helpNav"))",
                "[<-] [->] [Up] [Down] \(L("page.newControls.helpEdit"))",
            ])

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.newControls.title"), subtitle: "Gauge · Link · TextEditor · DatePicker")
        }
    }
}
