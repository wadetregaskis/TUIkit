//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerForEachTagTests.swift
//
//  SwiftUI: "ForEach automatically assigns a tag to the selection views using
//  each option's id." Without that, Apple's own first worked example of
//  iterating a picker compiled, drew its label, and offered nothing at all to
//  select — a plain Text is not a PickerOptionProvider, so every element
//  contributed zero options.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("picker options from a ForEach")
struct PickerForEachTagTests {
    private enum Flavor: String, CaseIterable, Identifiable {
        case chocolate, vanilla, strawberry
        var id: Self { self }
    }

    private func lines<V: View>(_ view: V) -> [String] {
        let context = makeRenderContext(width: 40, height: 10)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    private func shows<V: View>(_ view: V, _ text: String) -> Bool {
        lines(view).contains { $0.contains(text) }
    }

    @Test("Apple's untagged ForEach idiom offers its options")
    func untaggedForEachProducesOptions() {
        let picker = Picker("Flavor", selection: .constant(Flavor.vanilla)) {
            ForEach(Flavor.allCases) { Text($0.rawValue.capitalized) }
        }
        .pickerStyle(.radioGroup)

        #expect(shows(picker, "Chocolate"), "\(lines(picker))")
        #expect(shows(picker, "Vanilla"))
        #expect(shows(picker, "Strawberry"))
    }

    @Test("The synthesised tag is the element's id, so selection binds")
    func synthesisedTagSelects() {
        // Radio group marks the selected option; which one is marked is the
        // proof that the id became the tag rather than some placeholder.
        func marked(_ selection: Flavor) -> String? {
            let picker = Picker("Flavor", selection: .constant(selection)) {
                ForEach(Flavor.allCases) { Text($0.rawValue.capitalized) }
            }
            .pickerStyle(.radioGroup)
            return lines(picker).first { $0.contains(TerminalSymbols.radioSelected) }
        }
        #expect(marked(.chocolate)?.contains("Chocolate") == true, "\(marked(.chocolate) ?? "nil")")
        #expect(marked(.strawberry)?.contains("Strawberry") == true, "\(marked(.strawberry) ?? "nil")")
    }

    @Test("An explicit tag still wins over the element's id")
    func explicitTagWins() {
        // Tagging by rawValue against a String selection must bind, which it
        // could not do if the id (a Flavor) had overridden the tag.
        let picker = Picker("Flavor", selection: .constant("vanilla")) {
            ForEach(Flavor.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
        }
        .pickerStyle(.radioGroup)
        let marked = lines(picker).first { $0.contains(TerminalSymbols.radioSelected) }
        #expect(marked?.contains("Vanilla") == true, "\(marked ?? "nil"); \(lines(picker))")
    }
}
