//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RevealFocusedContainerTests.swift
//
//  Reveal-on-focus when the focused control is a CONTAINER (Table, List)
//  rather than a leaf control. A ScrollView locates the focused control by
//  scanning its content buffer's hit-test regions for one whose `focusID`
//  matches `FocusManager.currentFocusedID` — so a focusable container must
//  stamp its focusID onto the region it emits, or tabbing to an off-screen
//  Table/List silently leaves the viewport where it was (the stress app's
//  "Tables in a ScrollView" scenario made this visible).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("reveal focused containers (Table/List in a ScrollView)")
struct RevealFocusedContainerTests {
    private struct Item: Identifiable {
        let id: Int
        let label: String
    }

    private static func items(table: Int) -> [Item] {
        (0..<5).map { Item(id: table * 100 + $0, label: "t\(table)r\($0)") }
    }

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager,
        width: Int = 40, height: Int = 8
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("Tabbing to an off-screen Table scrolls the ScrollView to it")
    func tablesInScrollViewFollowFocus() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(0..<4, id: \.self) { table in
                    Table(Self.items(table: table), selection: Binding<Int?>.constant(nil)) {
                        TableColumn("Label") { (row: Item) in row.label }
                    }
                }
            }
        }
        .frame(height: 8)

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("t0r0") }, "starts at the top: \(first)")
        #expect(!first.contains { $0.contains("t3r") }, "the last table starts off-screen")

        let tables = focusManager.registeredFocusIDsInActiveSection()
            .filter { $0.hasPrefix("table-") }
        #expect(tables.count == 4, "all four tables registered: \(tables)")
        guard tables.count == 4 else { return }

        // Jump straight to the last table (Tab would land there eventually;
        // the direct focus isolates the reveal from ring-order details).
        focusManager.focus(id: tables[3])
        let revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            revealed.contains { $0.contains("t3r") },
            "focusing the off-screen table scrolled it into view: \(revealed)")
        #expect(!revealed.contains { $0.contains("t0r0") }, "the top scrolled away")

        // And back up.
        focusManager.focus(id: tables[0])
        let back = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            back.contains { $0.contains("t0r0") },
            "focusing the first table scrolls back: \(back)")
    }

    @Test("Tabbing to an off-screen List scrolls the ScrollView to it")
    func listsInScrollViewFollowFocus() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(0..<4, id: \.self) { list in
                    List(
                        Self.items(table: list),
                        selection: Binding<Int?>.constant(nil)
                    ) { item in
                        Text(item.label)
                    }
                }
            }
        }
        .frame(height: 8)

        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.contains { $0.contains("t0r0") }, "starts at the top: \(first)")
        #expect(!first.contains { $0.contains("t3r") }, "the last list starts off-screen")

        let lists = focusManager.registeredFocusIDsInActiveSection()
            .filter { $0.hasPrefix("list-") }
        #expect(lists.count == 4, "all four lists registered: \(lists)")
        guard lists.count == 4 else { return }

        focusManager.focus(id: lists[3])
        let revealed = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            revealed.contains { $0.contains("t3r") },
            "focusing the off-screen list scrolled it into view: \(revealed)")
        #expect(!revealed.contains { $0.contains("t0r0") }, "the top scrolled away")
    }

    @Test("A List carries its rows' focusIDs on the re-emitted regions")
    func listRowRegionsKeepFocusIDs() {
        // Rows render into standalone buffers whose regions the List
        // translates and re-emits. Dropping `focusID` in that carry would
        // orphan any focusable child inside a row — an enclosing ScrollView
        // could never locate it to reveal it.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = List {
            ForEach(0..<3, id: \.self) { i in
                Button("row \(i)") {}
            }
        }
        .frame(height: 8)

        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 8,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()

        let carried = buffer.hitTestRegions.compactMap(\.focusID)
            .filter { $0.hasPrefix("button-") }
        #expect(
            carried.count == 3,
            "every row button's region keeps its focusID: \(buffer.hitTestRegions)")
    }
}
