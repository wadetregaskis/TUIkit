//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListTitleHeightTests.swift
//
//  A bordered container draws a List's title INSIDE its top border row, so the
//  title costs no line of its own — `ContainerView`'s chrome budget counts the
//  borders and the footer separator and nothing else. `_ListCore` charged a
//  line for it anyway, so a titled List showed one row fewer than fits and left
//  a blank line at the bottom of its slot. A BORDERLESS (`.plain`) list does
//  render the title as its own row, and there the line is real.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A title costs a line only where one is drawn")
struct ListTitleHeightTests {

    /// The rendered lines of a 30-row list in a `height`-line slot.
    private func lines(title: String?, style: any ListStyle, height: Int = 20) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.listStyle = style
        environment.applyRuntimeServices(from: tui)

        let rows = (0..<30).map { "row \($0)" }
        let list: any View =
            title.map { titleText in
                List(titleText, selection: .constant(String?.none)) {
                    ForEach(rows, id: \.self) { Text($0) }
                }
            } ?? List(selection: .constant(String?.none)) {
                ForEach(rows, id: \.self) { Text($0) }
            }

        var context = RenderContext(
            availableWidth: 30, availableHeight: height, environment: environment,
            tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        tui.stateStorage.beginRenderPass()
        return renderToBuffer(AnyView(list), context: context).lines.map { $0.stripped }
    }

    private func rowCount(_ lines: [String]) -> Int {
        lines.filter { $0.contains("row ") }.count
    }

    @Test("A bordered title takes the border row, not a content row")
    func borderedTitleCostsNoRow() {
        let titled = lines(title: "Files", style: .insetGrouped)
        let untitled = lines(title: nil, style: .insetGrouped)
        #expect(
            rowCount(titled) == rowCount(untitled),
            "the title lives in the border: \(rowCount(titled)) rows vs \(rowCount(untitled))")
        #expect(titled.first?.contains("Files") == true, "…and it is drawn there: \(titled.first ?? "")")
    }

    @Test("A bordered titled list fills its slot")
    func borderedTitledListFillsTheSlot() {
        let titled = lines(title: "Files", style: .insetGrouped)
        #expect(titled.count == 20, "the box occupies the whole slot, got \(titled.count)")
    }

    /// The borderless twin genuinely spends a row on its title, so it shows one
    /// row fewer — that is correct and must stay.
    @Test("A borderless title does take a row")
    func borderlessTitleCostsARow() {
        let titled = lines(title: "Files", style: .plain)
        let untitled = lines(title: nil, style: .plain)
        #expect(
            rowCount(titled) == rowCount(untitled) - 1,
            "\(rowCount(titled)) rows vs \(rowCount(untitled))")
    }
}
