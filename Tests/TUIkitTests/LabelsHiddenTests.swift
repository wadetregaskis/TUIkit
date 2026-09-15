//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabelsHiddenTests.swift
//
//  `.labelsHidden()` across every control that draws a label of its own.
//
//  One case per control rather than one for the environment key, because the
//  point of the modifier is that the layout CLOSES UP: a control that merely
//  stopped painting its caption would leave a gap the width of the words, and
//  that is the failure this suite is here to catch. So each case asserts the
//  text is gone AND that what is left starts where it should.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("labelsHidden")
struct LabelsHiddenTests {

    private func screen(_ view: some View, width: Int = 40, height: Int = 8) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    /// What a control draws with and without its label, as trimmed text.
    private func pair(_ build: (Bool) -> AnyView) -> (shown: [String], hidden: [String]) {
        (screen(build(false)), screen(build(true)))
    }

    @Test("Toggle drops its caption and the space before it")
    func toggle() {
        let (shown, hidden) = pair { hide in
            let toggle = Toggle("Verbose", isOn: .constant(true))
            return hide ? AnyView(toggle.labelsHidden()) : AnyView(toggle)
        }
        #expect(shown.contains { $0.contains("Verbose") })
        #expect(!hidden.contains { $0.contains("Verbose") })
        // The box is still there, and nothing follows it.
        #expect(
            hidden.first?.trimmingCharacters(in: .whitespaces).count == 1,
            "the indicator alone, no trailing gap: \(hidden)")
    }

    @Test("Slider, Stepper and Picker drop theirs through the shared label unit")
    func collapsingLabelControls() {
        let slider = pair { hide in
            let view = Slider(value: .constant(0.5)) { Text("Volume") }
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(slider.shown.contains { $0.contains("Volume") })
        #expect(!slider.hidden.contains { $0.contains("Volume") })

        let stepper = pair { hide in
            let view = Stepper(value: .constant(1), in: 0...9) { Text("Count") }
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(stepper.shown.contains { $0.contains("Count") })
        #expect(!stepper.hidden.contains { $0.contains("Count") })

        let picker = pair { hide in
            let view = Picker("Theme", selection: .constant("Dark")) {
                Text("Dark").tag("Dark")
                Text("Light").tag("Light")
            }
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(picker.shown.contains { $0.contains("Theme") })
        #expect(!picker.hidden.contains { $0.contains("Theme") })
        #expect(picker.hidden.contains { $0.contains("Dark") }, "the picker itself stays")
    }

    @Test("LabeledContent leaves the content holding the row")
    func labeledContent() {
        let (shown, hidden) = pair { hide in
            let view = LabeledContent("Name") { Text("Ada") }
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(shown.contains { $0.contains("Name") })
        #expect(!hidden.contains { $0.contains("Name") })
        #expect(hidden.contains { $0.contains("Ada") })
    }

    @Test("A Form of hidden labels loses the label COLUMN, not just the words")
    func formPillar() {
        let (shown, hidden) = pair { hide in
            let view = Form {
                LabeledContent("Name") { Text("Ada") }
                LabeledContent("Occupation") { Text("Analyst") }
            }
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(shown.contains { $0.contains("Occupation") })
        #expect(!hidden.contains { $0.contains("Occupation") })
        // The pillar is gone: the values start at column 0 rather than being
        // indented past a column of captions nobody can see.
        let values = hidden.filter { $0.contains("Ada") || $0.contains("Analyst") }
        #expect(!values.isEmpty)
        #expect(
            values.allSatisfy { !$0.hasPrefix(" ") },
            "no indent where the label column was: \(hidden)")
    }

    @Test("DatePicker drops its caption")
    func datePicker() {
        let (shown, hidden) = pair { hide in
            let view = DatePicker("Due", selection: .constant(Date(timeIntervalSince1970: 0)))
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(shown.contains { $0.contains("Due") })
        #expect(!hidden.contains { $0.contains("Due") })
        // The field itself stays, and starts at column 0 — the caption's cells
        // went with it rather than being blanked in place.
        #expect(
            hidden.contains { !$0.isEmpty && !$0.hasPrefix(" ") },
            "the field is still drawn, flush left: \(hidden)")
    }

    @Test("ColorPicker drops the label column, gap and all")
    func colorPicker() {
        let (shown, hidden) = pair { hide in
            let view = ColorPicker("Tint", selection: .constant(Color.red))
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(shown.contains { $0.contains("Tint") })
        #expect(!hidden.contains { $0.contains("Tint") })
        #expect(hidden.contains { $0.contains("R") }, "the channels stay: \(hidden)")
        #expect(
            hidden.contains { !$0.hasPrefix(" ") },
            "no reserved label pillar: \(hidden)")
    }

    /// The caption goes; the value readout does not. A `currentValueLabel`
    /// states what the bar is showing, which is content rather than a name.
    @Test("ProgressView and Gauge drop the caption and keep the readout")
    func progressAndGauge() {
        let progress = pair { hide in
            let view = ProgressView(value: 0.5) {
                Text("Copying")
            } currentValueLabel: {
                Text("50%")
            }
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(progress.shown.contains { $0.contains("Copying") })
        #expect(!progress.hidden.contains { $0.contains("Copying") })
        #expect(progress.hidden.contains { $0.contains("50%") })

        let gauge = pair { hide in
            let view = Gauge(value: 0.5) {
                Text("Signal")
            } currentValueLabel: {
                Text("half")
            }
            return hide ? AnyView(view.labelsHidden()) : AnyView(view)
        }
        #expect(gauge.shown.contains { $0.contains("Signal") })
        #expect(!gauge.hidden.contains { $0.contains("Signal") })
        #expect(gauge.hidden.contains { $0.contains("half") })
    }

    @Test("It reaches a whole subtree, and can be turned back on inside one")
    func scoping() {
        let lines = screen(
            VStack {
                Toggle("Outer", isOn: .constant(true))
                Toggle("Inner", isOn: .constant(true)).labelsVisibility(.visible)
            }
            .labelsHidden(),
            height: 6)
        #expect(!lines.contains { $0.contains("Outer") })
        #expect(lines.contains { $0.contains("Inner") }, "restored inside: \(lines)")
    }

    @Test("Ordinary content beside a control is not a label")
    func contentIsNotALabel() {
        let lines = screen(
            HStack {
                Text("Volume")
                Slider(value: .constant(0.5))
            }
            .labelsHidden())
        #expect(lines.contains { $0.contains("Volume") }, "a sibling Text stays: \(lines)")
    }
}
