//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PointerHoverAuditTests.swift
//
//  The three clickable things that had no answer to the pointer at all: a
//  scrollbar's arrows and thumb, a TabView's tabs, and a DatePicker's field.
//  Every other control lifts its foreground under the pointer
//  (`Palette.hoveredForeground(_:)`); these did nothing, so nothing said they
//  could be clicked.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Pointer hover audit")
struct PointerHoverAuditTests {

    /// Renders once to collect regions, points the pointer at `(x, y)`, and
    /// renders again — the two frames a hover takes.
    private func hovering(
        _ view: some View, at point: (x: Int, y: Int), width: Int = 40, height: Int = 12,
        pick: (HitTestRegion) -> Bool = { _ in true }
    ) -> (before: [String], after: [String]) {
        let context = makeRenderContext(width: width, height: height)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        let before = renderToBuffer(view, context: context)
        dispatcher.setRegions(before.hitTestRegions.filter(pick))
        _ = dispatcher.dispatch(
            MouseEvent(button: .none, phase: .moved, x: point.x, y: point.y))
        let after = renderToBuffer(view, context: context)
        return (before.lines, after.lines)
    }

    // MARK: - Scrollbar

    @Test("A scrollbar's arrow lifts under the pointer, and only that cell")
    func scrollbarArrowLifts() {
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("line \($0)") }
            }
        }
        .frame(width: 20, height: 6)
        // The bar is the last column; its first cell is the ▲.
        let frames = hovering(view, at: (x: 19, y: 0), width: 20, height: 6)
        #expect(frames.before != frames.after, "the pointer changed nothing")
        let changed = zip(frames.before, frames.after).filter { $0 != $1 }.count
        #expect(changed == 1, "\(changed) rows moved; only the arrow's should")
    }

    // MARK: - TabView

    @Test("A tab's label lifts under the pointer")
    func tabLabelLifts() {
        let view = TabView(selection: .constant(0)) {
            Tab("One", value: 0) { Text("first") }
            Tab("Two", value: 1) { Text("second") }
        }
        // Somewhere inside the second chip: "▐ One ▌▐ Two ▌".
        let frames = hovering(view, at: (x: 10, y: 0))
        #expect(frames.before.first != frames.after.first, "the strip did not answer the pointer")
    }

    // MARK: - DatePicker

    /// Parks the focus, so the field under test is rendered UNfocused — a
    /// focused one says so with its pulsing active block and the pointer must
    /// not fight that.
    private final class FocusSentinel: Focusable {
        let focusID = "hover-audit-sentinel"
        func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
    }

    @Test("A date field lifts under the pointer")
    func dateFieldLifts() {
        let view = DatePicker("", selection: .constant(Date(timeIntervalSince1970: 0)))
        let context = makeRenderContext(width: 40, height: 4)
        context.environment.focusManager!.register(FocusSentinel())
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        let before = renderToBuffer(view, context: context)
        dispatcher.setRegions(before.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        let after = renderToBuffer(view, context: context)
        #expect(before.lines.first != after.lines.first, "the field did not answer the pointer")
    }
}
