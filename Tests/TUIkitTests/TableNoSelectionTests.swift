//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableNoSelectionTests.swift
//
//  `Table(_:columns:)` — SwiftUI's selection-free table.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A Table with no selection")
struct TableNoSelectionTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        var name: String { id }
    }

    @MainActor
    private final class Fixture {
        let tui = TUIContext()
        var env = EnvironmentValues()
        let rows = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]

        init() {
            env.focusManager = FocusManager()
            env.scrollIndicatorStyle = .text
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        /// The three tables that differ only in whether a mark can ever
        /// appear beside a row.
        enum Kind {
            /// `Table(_:columns:)` — no selection binding at all.
            case plain
            /// `Table(_:selection:columns:)`, nothing selected.
            case selectable
            /// Selectable, but told to leave the mark off.
            case markHidden
        }

        func render(_ kind: Kind) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            let selectable = Table(rows.map(Row.init), selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.name)
            }
            let table: AnyView =
                switch kind {
                case .plain:
                    AnyView(
                        Table(rows.map(Row.init)) {
                            TableColumn<Row>("Name", value: \.name)
                        })
                case .selectable: AnyView(selectable)
                case .markHidden: AnyView(selectable.rowSelectionIndicator(.hidden))
                }
            var context = RenderContext(
                availableWidth: 22, availableHeight: 9, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(table.frame(width: 22, height: 7), context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        var handler: ItemListHandler<String>? {
            env.focusManager?.currentFocused as? ItemListHandler<String>
        }

        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.filter(\.isLetter) == label } ?? -1
        }

        func click(_ buffer: FrameBuffer, on label: String) {
            let y = rowY(buffer, label)
            tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: y))
            tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: 2, y: y))
        }
    }

    /// The same rows, in the same order, at the same width. What differs is
    /// where they start, which is the next test — here, only that nothing was
    /// dropped, reordered or re-wrapped by having no selection.
    @Test("It draws the same rows")
    func drawsTheRows() {
        let fixture = Fixture()
        let plain = fixture.render(.plain).lines.map(\.stripped)
        let selectable = fixture.render(.selectable).lines.map(\.stripped)
        #expect(plain.count == selectable.count)
        for (lhs, rhs) in zip(plain, selectable) {
            #expect(lhs.count == rhs.count, "both are the frame's width")
            #expect(
                lhs.filter { !$0.isWhitespace } == rhs.filter { !$0.isWhitespace },
                "\(lhs)\nvs\n\(rhs)")
        }
    }

    /// The mark's cell and the gap after it are not set aside by a table that
    /// can never draw a mark: its header and rows start one cell inside the
    /// border, like any other bordered content.
    ///
    /// Both structural ways of having no mark are here, because both are one
    /// answer from ``RowSelectionIndicator/isReserved(hasSelection:environment:)``
    /// and the second — `.rowSelectionIndicator(.hidden)` — used to promise the
    /// opposite in its own documentation.
    @Test("It keeps no room for a mark it can never draw")
    func spendsNothingOnTheGutter() {
        let fixture = Fixture()
        let selectable = fixture.render(.selectable).lines.map(\.stripped)
        for label in ["Name", "alpha", "charlie"] {
            #expect(
                indent(of: label, in: selectable) == 4,
                "\(label): the border, its pad, the mark's cell, the gap after it")
        }
        for kind in [Fixture.Kind.plain, .markHidden] {
            let lines = fixture.render(kind).lines.map(\.stripped)
            for label in ["Name", "alpha", "charlie"] {
                #expect(
                    indent(of: label, in: lines) == 2,
                    "\(kind) \(label): the border, its pad, and then the value")
            }
        }
    }

    /// Where `label` starts on whichever line carries it, or `nil` if no line
    /// does — which fails the comparison rather than passing it vacuously.
    private func indent(of label: String, in lines: [String]) -> Int? {
        for line in lines {
            if let range = line.range(of: label) {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
        }
        return nil
    }

    /// Still focusable, and still scrollable from the keyboard — which is the
    /// difference between this and `.disabled(true)`, and the reason it exists
    /// rather than being spelled that way.
    @Test("It still takes focus, so it can still be scrolled")
    func staysFocusable() {
        let fixture = Fixture()
        let buffer = fixture.render(.plain)
        fixture.click(buffer, on: "alpha")
        _ = fixture.render(.plain)
        #expect(fixture.handler != nil, "the table took focus")
        #expect(fixture.handler?.canBeFocused == true)
    }
}
