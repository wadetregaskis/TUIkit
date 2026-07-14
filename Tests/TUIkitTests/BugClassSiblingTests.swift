//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BugClassSiblingTests.swift
//
//  Regression pins for UNTESTED SIBLINGS of previously-fixed bug classes,
//  found by auditing the codebase for the same shapes:
//
//  - measure-pass side effects (class fixed in List/ScrollView/SplitView):
//    Menu key handlers, the alert ESC handler, and _ImageCore's lifecycle
//    mutations must not fire when an ancestor measures by rendering.
//  - border clicks are chrome (List got the x-guard in a6ba424d): Table's
//    container handler needs the same guard.
//  - asymmetric press/release: DatePicker must claim its press (drag capture);
//    a legacy X10 "any release" (decoded .left) must clear a right-button
//    capture; a stray release must not inherit a stale modifier.
//  - cells-not-characters clip shortfall: DropdownMenu.fit and
//    BorderRenderer content lines must pad the straddled-wide-char gap.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Bug-class siblings")
struct BugClassSiblingTests {

    // MARK: - Measure-pass side effects

    @Test("Measuring an interactive Menu registers no phantom key handler")
    func menuMeasureRegistersNoKeyHandler() {
        final class Box { var sel = 0 }
        let box = Box()
        let menu = Menu(
            items: (1...5).map { MenuItem(label: "Item \($0)", shortcut: nil) },
            selection: Binding(get: { box.sel }, set: { box.sel = $0 }))

        let tui = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: env, tuiContext: tui
        ).isolatingRenderCache()

        // MEASURE only (measureFixedByRendering renders with isMeasuring set) —
        // a menu measured but never shown (a ViewThatFits rejected candidate)
        // must not leave a handler that eats arrows against its binding.
        _ = measureChild(menu, proposal: ProposedSize(width: 40, height: 12), context: context)
        _ = tui.keyEventDispatcher.dispatch(KeyEvent(key: .down))
        #expect(box.sel == 0, "no phantom handler moved the selection, got \(box.sel)")

        // A real RENDER still wires the keys.
        _ = renderToBuffer(menu, context: context)
        _ = tui.keyEventDispatcher.dispatch(KeyEvent(key: .down))
        #expect(box.sel == 1, "the rendered menu's handler works, got \(box.sel)")
    }

    @Test("Measuring a presented alert registers no duplicate ESC handler")
    func alertMeasureRegistersNoEscHandler() {
        let view = Text("base")
            .alert("Title", isPresented: .constant(true)) {
                Button("OK") {}
            } message: {
                Text("message")
            }

        let tui = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = FocusManager()
        let render = RenderContext(
            availableWidth: 60, availableHeight: 20, environment: env, tuiContext: tui
        ).isolatingRenderCache()

        let before = tui.keyEventDispatcher.handlerCount
        // Simulate an ancestor's measure-BY-RENDERING (a Card's container
        // measure): the presented branch runs with `isMeasuring` set and must
        // not register a phantom duplicate ESC handler.
        var measuring = render
        measuring.isMeasuring = true
        _ = renderToBuffer(view, context: measuring)
        #expect(
            tui.keyEventDispatcher.handlerCount == before,
            "measure-by-rendering registered no ESC handler")

        _ = renderToBuffer(view, context: render)
        #expect(
            tui.keyEventDispatcher.handlerCount > before,
            "render registers the alert's ESC handler")
    }

    // MARK: - Table border clicks are chrome (List's a6ba424d sibling)

    private struct Row: Identifiable {
        let id: Int
        let name: String
    }

    @Test("Table border-column clicks never select the y-aligned row")
    func tableBorderClicksAreChrome() {
        final class Box { var sel: Set<Int> = [] }
        let box = Box()
        let rows = (1...5).map { Row(id: $0, name: "row-\($0)") }
        let view = Table(rows, selection: Binding(get: { box.sel }, set: { box.sel = $0 })) {
            TableColumn("Name", value: \Row.name)
        }
        .frame(height: 10)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        guard let rowY = buffer.lines.firstIndex(where: { $0.stripped.contains("row-2") }) else {
            Issue.record("row-2 not rendered")
            return
        }
        func click(x: Int) {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: rowY))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: rowY))
        }
        // Left border: chrome — focus only, no selection.
        click(x: 0)
        #expect(box.sel.isEmpty, "left-border click must not select, got \(box.sel)")
        // Right border: chrome too.
        click(x: buffer.width - 1)
        #expect(box.sel.isEmpty, "right-border click must not select, got \(box.sel)")
        // Sanity: a content click still selects.
        click(x: 4)
        #expect(box.sel == [2], "content clicks still select, got \(box.sel)")
    }

    // MARK: - Asymmetric press/release

    @Test("DatePicker claims its press so the release is drag-captured")
    func datePickerClaimsPress() {
        var captured = false
        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 4, environment: env, tuiContext: tui)
        let view = DatePicker("Date", selection: .constant(Date(timeIntervalSince1970: 0)))
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        // Press inside the picker's FIELD (the region starts after the label)
        // must be CONSUMED (captured) so a release over a neighbouring control
        // routes back here instead of clicking it.
        guard let region = buffer.hitTestRegions.first else {
            Issue.record("no DatePicker region registered")
            return
        }
        captured = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX + 1, y: region.offsetY))
        #expect(captured, "the DatePicker claims its press")
    }

    @Test("A legacy 'any release' (.left) clears a right-button capture")
    func legacyReleaseClearsForeignCapture() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var got: [MousePhase] = []
        let id = dispatcher.register { event in
            got.append(event.phase)
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 2, handlerID: id)
        ])

        // SGR right-button press captures…
        _ = dispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 1, y: 0))
        // …but Terminal.app can emit the RELEASE as an X10 'any release', which
        // the parser decodes as .left. The capture must still end.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 1, y: 0))
        #expect(got == [.pressed, .released], "the capture saw its release: \(got)")

        // The right-button capture is gone: a later right event routes fresh
        // (hit-tested), not to a stale capture.
        got.removeAll()
        _ = dispatcher.dispatch(MouseEvent(button: .right, phase: .dragged, x: 50, y: 50))
        #expect(got.isEmpty, "no stale capture swallowed an off-region drag: \(got)")
    }

    @Test("A stray release does not inherit a stale modifier from a finished click")
    func strayReleaseInheritsNoStaleModifier() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var releases: [MouseEvent] = []
        let id = dispatcher.register { event in
            if event.phase == .released { releases.append(event) }
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 20, height: 2, handlerID: id)
        ])

        // A complete meta-click…
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0, meta: true))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 1, y: 0, meta: true))
        #expect(releases.last?.meta == true)

        // …then a STRAY release with no in-flight press: it must arrive bare,
        // not stamped with the finished click's meta (a phantom modifier-click
        // would toggle a multi-selection).
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 8, y: 1))
        #expect(releases.last?.meta == false, "stray release stays unmodified")
    }

    // MARK: - Wide-char clip shortfall

    @Test(
        "DropdownMenu.fit yields EXACTLY the requested columns",
        arguments: [
            ("🍎🍎🍎", 5),  // clip lands mid-apple → prefix is 4 cells, must pad to 5
            ("🍎🍎🍎", 4),  // exact wide boundary
            ("ab🍎cd", 3),  // clip right before the apple
            ("中文标题", 5),  // CJK mid-clip
            ("plain", 10),  // pad path
        ])
    func dropdownFitExactWidth(text: String, width: Int) {
        let fitted = DropdownMenu.fit(text, to: width)
        #expect(
            fitted.strippedLength == width,
            "fit(\"\(text)\", to: \(width)) → \(fitted.strippedLength) cells")
    }

    @Test("A bordered content line clipping mid-wide-char keeps its right border aligned")
    func borderedWideCharClipAligned() {
        // Feed the border renderer an over-wide line whose clip lands INSIDE a
        // wide char (5 apples = 10 cells into a 5-cell interior → the third
        // apple straddles column 5): the shortfall must be padded or the right
        // border shifts a column left.
        let line = BorderRenderer.standardContentLine(
            content: "🍎🍎🍎🍎🍎", innerWidth: 5, style: .rounded, color: .white)
        #expect(
            line.strippedLength == 7,  // │ + 5 interior cells + │
            "the bordered line is exactly innerWidth+2 cells: '\(line.stripped)' (\(line.strippedLength))")
        #expect(line.stripped.hasSuffix("│"), "the right border survives: '\(line.stripped)'")
    }
}
