//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmptyChromeRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Render tests for the "empty label / title / header" bug class: a view given
//  no (or blank) chrome must not draw a blank line or a gap in its border.
//  (See also PickerRenderTests for the Picker case.)

import Testing

@testable import TUIkit

@MainActor
@Suite("Empty chrome rendering")
struct EmptyChromeRenderTests {

    private func lines(_ v: some View, w: Int = 24, h: Int = 6) -> [String] {
        renderToBuffer(v, context: makeRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    // MARK: - Bordered containers (Panel / Card / Dialog share BorderRenderer)

    @Test("A Panel with an empty title draws a continuous top border")
    func panelEmptyTitleContinuousBorder() {
        let top = lines(Panel("") { Text("x") }).first ?? ""
        #expect(!top.contains("  "), "no gap where the title would be: \(top)")
        #expect(top.contains("╭") && top.contains("╮"))
        // Sanity: a titled panel DOES show its title.
        let titled = lines(Panel("Hi") { Text("x") }).first ?? ""
        #expect(titled.contains("Hi"))
    }

    @Test("A Card with an empty title draws a continuous top border")
    func cardEmptyTitleContinuousBorder() {
        let top = lines(Card(title: "") { Text("x") }).first ?? ""
        #expect(!top.contains("  "), "got: \(top)")
        let titled = lines(Card(title: "Hi") { Text("x") }).first ?? ""
        #expect(titled.contains("Hi"))
    }

    @Test("A Dialog with an empty title draws a continuous top border")
    func dialogEmptyTitleContinuousBorder() {
        let top = lines(Dialog(title: "") { Text("x") }, w: 18, h: 5).first ?? ""
        #expect(!top.contains("  "), "got: \(top)")
    }

    // MARK: - Section

    @Test("A Section with an empty header shows no blank line above the body")
    func sectionEmptyHeaderNoBlankLine() {
        let out = lines(Section { Text("body") } header: { Text("") })
        #expect(out.first == "body", "got: \(out)")
        #expect(out.count == 1)
    }

    @Test("A Section with a real header shows it above the body")
    func sectionHeaderShown() {
        let out = lines(Section { Text("body") } header: { Text("Head") })
        #expect(out.first?.contains("Head") == true)
        #expect(out.contains("body"))
    }

    // MARK: - ProgressView

    @Test("A ProgressView with an empty label is one line (just the bar)")
    func progressEmptyLabelOneLine() {
        let out = lines(ProgressView("", value: 0.5), w: 20, h: 4)
            .filter { !$0.allSatisfy(\.isWhitespace) }
        #expect(out.count == 1, "only the bar: \(out)")
    }

    @Test("A labelled ProgressView shows the label above the bar")
    func progressLabelledTwoLines() {
        let out = lines(ProgressView("Down", value: 0.5), w: 20, h: 4)
            .filter { !$0.allSatisfy(\.isWhitespace) }
        #expect(out.count == 2)
        #expect(out.first?.contains("Down") == true)
    }
}
