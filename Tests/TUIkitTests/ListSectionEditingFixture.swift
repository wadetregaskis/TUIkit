//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSectionEditingFixture.swift
//
//  The shared harness for the List section-editing suites: a live `List`
//  rendered through the real focus manager, with the two gestures that mutate
//  a row's collection — Delete, and the Ctrl-R pick-up — driven the way the
//  run loop drives them.
//
//  Shared rather than duplicated because the four suites that sit on it ask
//  the same list the same questions from different sides (what the wiring
//  does, what it refuses, what a `Group` in the way changes, where it leaves
//  the cursor), and each copy of a harness is a place they can drift apart
//  about what they are testing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Apple's multidimensional-list shape: a region owns its rows, and the
/// outer `ForEach` iterates the regions while the `List`'s rows are seas.
struct EditableRegion: Identifiable, Hashable {
    let id: String
    var seas: [String]
}

/// A rendered `List` plus the gestures that edit it, holding the focus
/// manager the rows registered with so a key press reaches the same handler
/// the render installed.
@MainActor
final class ListSectionEditingFixture {
    let tui = TUIContext()
    var env = EnvironmentValues()

    init() {
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
    }

    var handler: ItemListHandler<String>? {
        env.focusManager?.currentFocused as? ItemListHandler<String>
    }

    /// The focused list's handler for a selection type other than `String`
    /// — an `Int`-selected list, whose rows take their ORDINALS as ids and
    /// so can be reached by the cursor where a `String`-selected list's
    /// same rows cannot. Same lookup as ``handler``, which stays for the
    /// `String` lists the rest of this suite builds.
    func handler<Value: Hashable>(_ valueType: Value.Type) -> ItemListHandler<Value>? {
        env.focusManager?.currentFocused as? ItemListHandler<Value>
    }

    @discardableResult
    func render(_ view: some View) -> FrameBuffer {
        tui.stateStorage.beginRenderPass()
        env.focusManager?.beginRenderPass()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 16, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        env.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    /// Presses Delete on the row at `row`, having first checked that the
    /// row really is the one named — a delete aimed at the wrong row is
    /// the very failure these tests exist to catch.
    func pressDelete(onRow row: Int, named id: String) -> Bool {
        guard let handler = focusedRow(row, named: id) else { return false }
        return handler.handleKeyEvent(KeyEvent(key: .delete))
    }

    /// The keyboard reorder, end to end: Ctrl-R picks `row` up, Down moves
    /// its landing slot `steps` times, Return places it. Reports whether
    /// the pick-up was accepted — `false` is a row nothing can move, which
    /// must leave the chord to whatever else wants it.
    func pickUpMoveAndPlace(row: Int, named id: String, by steps: Int) -> Bool {
        guard let handler = focusedRow(row, named: id) else { return false }
        guard handler.handleKeyEvent(KeyEvent(key: .character("r"), ctrl: true)) else {
            return false
        }
        for _ in 0..<steps { _ = handler.handleKeyEvent(KeyEvent(key: .down)) }
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        return true
    }

    /// The id of the row the cursor stands on, or `nil` when it stands on
    /// chrome — a header or a footer, which carry no selection value and
    /// so are the answer this suite is watching for.
    var focusedRowID: String? {
        handler.flatMap { $0.id(at: $0.focusedIndex) }
    }

    /// The published band for a list row, from the last render.
    func band(row: Int) -> ItemListHandler<String>.RowBand? {
        handler?.visibleRowBands.first { $0.rowIndex == row && $0.isContent }
    }

    /// Puts the cursor on `row`, having first checked the row really is the
    /// one named: a gesture aimed at the wrong row would pass these tests
    /// for the wrong reason.
    private func focusedRow(_ row: Int, named id: String) -> ItemListHandler<String>? {
        guard let handler else {
            Issue.record("the list took focus")
            return nil
        }
        #expect(
            handler.id(at: row) == id,
            "row \(row) is \(String(describing: handler.id(at: row))), not \(id)")
        handler.focusedIndex = row
        return handler
    }
}

/// Two deletable `Section`s, the second's `.onDelete` optional — the shape
/// both the several-Sections series and the cursor-landing series build on,
/// where every offset is ambiguous between the two collections unless the
/// row's own `ForEach` resolves it.
@MainActor
func twoSections(
    alpha: MainActorBox<[String]>, beta: MainActorBox<[String]>, betaEditable: Bool
) -> some View {
    List(selection: .constant(String?.none)) {
        Section("Alpha") {
            ForEach(alpha.value, id: \.self) { Text($0) }
                .onDelete { alpha.value.remove(atOffsets: $0) }
        }
        Section("Beta") {
            ForEach(beta.value, id: \.self) { Text($0) }
                .onDelete(perform: betaEditable ? { beta.value.remove(atOffsets: $0) } : nil)
        }
    }
    .frame(height: 12)
}
