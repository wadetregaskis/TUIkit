//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PickerRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Buffer-level render tests for Picker in its configurations (menu / radio-
//  group / inline styles, labelled / unlabelled), asserting the rendered lines
//  look correct.

import Testing

@testable import TUIkit

@MainActor
@Suite("Picker rendering")
struct PickerRenderTests {

    private func lines(_ view: some View, width: Int = 30, height: Int = 8) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    // MARK: - Labels

    @Test("A labelled radio-group picker shows the label then the options")
    func radioGroupLabelled() {
        let view = Picker("Colour", selection: .constant(1)) {
            Text("Red").tag(1)
            Text("Green").tag(2)
        }
        .pickerStyle(.radioGroup)
        let out = lines(view).filter { !$0.allSatisfy(\.isWhitespace) }
        #expect(out.first?.contains("Colour") == true)
        #expect(out.contains { $0.contains("Red") })
        #expect(out.contains { $0.contains("Green") })
    }

    @Test("An unlabelled radio-group picker shows NO blank first line")
    func radioGroupUnlabelledHasNoBlankLine() {
        let view = Picker("", selection: .constant(1)) {
            Text("Red").tag(1)
            Text("Green").tag(2)
        }
        .pickerStyle(.radioGroup)
        let out = lines(view)
        // The first rendered line must be the first option, not a blank label row.
        #expect(out.first?.contains("Red") == true, "got: \(out)")
        #expect(!(out.first?.allSatisfy(\.isWhitespace) ?? true), "no leading blank line")
    }

    @Test("An unlabelled menu picker shows NO blank first line")
    func menuUnlabelledHasNoBlankLine() {
        let view = Picker("", selection: .constant(1)) {
            Text("Red").tag(1)
            Text("Green").tag(2)
        }
        let out = lines(view).filter { !$0.isEmpty }
        // First non-empty line is the collapsed menu control, showing the selection.
        #expect(out.first?.contains("Red") == true, "got: \(out)")
    }

    @Test("A labelled menu picker shows the label above the collapsed control")
    func menuLabelled() {
        let view = Picker("Pick", selection: .constant(1)) {
            Text("Red").tag(1)
            Text("Green").tag(2)
        }
        let out = lines(view).filter { !$0.allSatisfy(\.isWhitespace) }
        #expect(out.first?.contains("Pick") == true)
        #expect(out.contains { $0.contains("Red") }, "collapsed control shows the selection")
    }

    @Test("A whitespace-only label also collapses (no blank line)")
    func whitespaceLabelCollapses() {
        let view = Picker("   ", selection: .constant(1)) {
            Text("Red").tag(1)
            Text("Green").tag(2)
        }
        .pickerStyle(.radioGroup)
        let out = lines(view)
        #expect(out.first?.contains("Red") == true)
    }
}
