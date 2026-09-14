//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusEffectDisabledTests.swift
//
//  `.focusEffectDisabled()` has to be all-or-nothing across the controls, and
//  that is exactly what a partial implementation cannot be told from: six
//  controls going quiet while two keep shouting reads as a bug in those two.
//
//  So the assertion is a SWEEP, and its baseline is a control that is
//  genuinely unfocused — a live focus manager with the focus parked on a
//  sibling — rather than one that was never offered focus at all. Comparing
//  against "focused, effects off" then answers the only question the modifier
//  makes: are these the same picture?
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("focusEffectDisabled suppresses every control's focus indication")
struct FocusEffectDisabledTests {

    /// A subject and a sibling to park the focus on, rendered together so the
    /// focus manager has a real choice to make.
    private func rendered(
        _ subject: some View, focusOnSubject: Bool, effectsDisabled: Bool, frames: Int = 1,
        skippingRows: Int = 0
    ) -> [String] {
        // The animation services matter here: a control whose focus
        // indication is a PULSE produces none without them, and the sweep
        // would then compare two identical unfocused pictures and pass.
        let context = makeRenderContext(width: 44, height: 10) { environment, _ in
            environment.animationScheduler = AnimationScheduler()
            environment.volatileReadTracker = VolatileReadTracker()
        }
        // Focus is placed by ORDER rather than by id: a fresh focus manager
        // auto-focuses the first focusable it is offered, so putting the
        // sibling first is how the subject is genuinely unfocused — a real
        // focus manager with the focus really elsewhere, which is the baseline
        // that makes this comparison mean anything.
        //
        // More than one frame for a view that only knows what it looks like
        // after it has seen itself once: a `ScrollView`'s first pass reports
        // its extent as its viewport, so its bar is an inert gutter that
        // indicates nothing either way. The last frame is the one compared.
        var buffer = FrameBuffer()
        for _ in 0..<max(1, frames) {
            // The pulse only advances inside a driven frame; without this the
            // cycle never animates and leaves no run.
            let scheduler = context.environment.animationScheduler
            scheduler?.beginFrame()
            context.environment.focusManager?.beginRenderPass()
            if focusOnSubject {
                buffer = renderToBuffer(
                    VStack {
                        subject.focusEffectDisabled(effectsDisabled)
                        Button("sibling") {}
                    }, context: context)
            } else {
                buffer = renderToBuffer(
                    VStack {
                        Button("sibling") {}
                        subject.focusEffectDisabled(effectsDisabled)
                    }, context: context)
            }
            context.environment.focusManager?.endRenderPass()
            scheduler?.endFrame()
        }

        // Lines AND runs. A control whose focus indication is a pulse puts it
        // in `animatedCells` — the still frame is identical either way — so a
        // comparison of lines alone reports `Toggle` and `RadioButtonGroup` as
        // never indicating focus at all, which is how a sweep passes while
        // doing nothing.
        //
        // Both have to be scoped to the SUBJECT. The sibling is a focusable
        // too, so in the unfocused arrangement it is the one that pulses, and
        // counting its runs made every control look like it indicated focus
        // when suppressed and not when not — the diff read backwards. Runs are
        // also re-based on the subject's first row, because the subject sits
        // at a different row in the two arrangements.
        let siblingRow = buffer.lines.firstIndex { $0.stripped.contains("sibling") }
        let subjectRows = buffer.lines.indices.filter { $0 != siblingRow }
        let origin = subjectRows.first ?? 0
        // `skippingRows` drops the subject's first rows, lines and runs alike,
        // for a view that keeps something on them that is not a focus effect.
        let lines = subjectRows.dropFirst(skippingRows).map { buffer.lines[$0] }
        let runs = buffer.animatedCells
            .filter { $0.offsetY != siblingRow && $0.offsetY - origin >= skippingRows }
            .map { "run@\($0.offsetX),\($0.offsetY - origin)×\($0.width) \($0.frames)" }
            .sorted()
        return lines + runs
    }

    /// The whole contract, per control: focused-with-effects-off must be
    /// byte-for-byte what genuinely-unfocused looks like.
    private func expectIndistinguishable(
        _ subject: some View, _ name: String, frames: Int = 1,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let unfocused = rendered(subject, focusOnSubject: false, effectsDisabled: false, frames: frames)
        let suppressed = rendered(subject, focusOnSubject: true, effectsDisabled: true, frames: frames)
        #expect(
            suppressed == unfocused,
            """
            \(name) still indicates focus with the effect disabled:
              unfocused   \(unfocused.map(\.debugDescription).joined(separator: "\n              "))
              suppressed  \(suppressed.map(\.debugDescription).joined(separator: "\n              "))
            """,
            sourceLocation: sourceLocation)
    }

    /// …and the control must ALSO still look different when it is focused and
    /// the effect is on, or the case above passes for a control that never
    /// indicated anything.
    private func expectDistinguishable(
        _ subject: some View, _ name: String, frames: Int = 1,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let unfocused = rendered(subject, focusOnSubject: false, effectsDisabled: false, frames: frames)
        let focused = rendered(subject, focusOnSubject: true, effectsDisabled: false, frames: frames)
        #expect(
            focused != unfocused,
            "\(name) does not indicate focus at all, so the suppression case proves nothing",
            sourceLocation: sourceLocation)
    }

    @Test("Button")
    func button() {
        expectDistinguishable(Button("press") {}, "Button")
        expectIndistinguishable(Button("press") {}, "Button")
    }

    @Test("Toggle")
    func toggle() {
        expectDistinguishable(Toggle("on", isOn: .constant(true)), "Toggle")
        expectIndistinguishable(Toggle("on", isOn: .constant(true)), "Toggle")
    }

    @Test("Slider")
    func slider() {
        expectDistinguishable(Slider(value: .constant(0.5)), "Slider")
        expectIndistinguishable(Slider(value: .constant(0.5)), "Slider")
    }

    @Test("Stepper")
    func stepper() {
        expectDistinguishable(Stepper("n", value: .constant(5), in: 0...10), "Stepper")
        expectIndistinguishable(Stepper("n", value: .constant(5), in: 0...10), "Stepper")
    }

    @Test("RadioButtonGroup")
    func radioButtons() {
        let group = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Beta")
        }
        expectDistinguishable(group, "RadioButtonGroup")
        expectIndistinguishable(group, "RadioButtonGroup")
    }

    /// A `List`'s cursor row is a focus indication — which row the keys will
    /// act on — so it goes. Its SELECTION mark does not: being selected is not
    /// being focused, and the mark is what says so (see `RowSelectionIndicator`).
    @Test("List")
    func list() {
        let list = List(selection: .constant("a")) {
            ForEach(["a", "b"], id: \.self) { Text($0) }
        }
        .frame(width: 20, height: 4)
        expectDistinguishable(list, "List")
        expectIndistinguishable(list, "List")
    }

    /// A `DatePicker`'s active-field marker goes with everything else.
    ///
    /// It looks like a caret and is not one: a caret says where TYPING goes,
    /// and there is no typing here — the field is active only because the
    /// control is focused, which makes the mark an announcement of focus like
    /// a `Button`'s bold.
    @Test("DatePicker")
    func datePicker() {
        let picker = DatePicker("when", selection: .constant(Date(timeIntervalSince1970: 0)))
        expectDistinguishable(picker, "DatePicker")
        expectIndistinguishable(picker, "DatePicker")
    }

    /// A `TabView`'s active chip BREATHES when the strip is focused — that is
    /// the whole of `ActiveChipCycle`'s job — so the breath goes with every
    /// other indication. The selected chip's own surface stays: which tab is
    /// showing is not which control has the keyboard.
    @Test("TabView")
    func tabView() {
        let tabs = TabView(selection: .constant(0)) {
            Tab("Alpha", value: 0) { Text("A") }
            Tab("Bravo", value: 1) { Text("B") }
        }
        expectDistinguishable(tabs, "TabView")
        expectIndistinguishable(tabs, "TabView")
    }

    /// A menu-style `Picker` — the default style — draws its collapsed value in
    /// the accent, bold, between breathing caps when focused. All three are
    /// announcements of focus.
    @Test("Picker")
    func picker() {
        let picker = Picker("Theme", selection: .constant("dark")) {
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }
        expectDistinguishable(picker, "Picker")
        expectIndistinguishable(picker, "Picker")
    }

    /// A focused `ScrollView`'s scrollbar IS its focus indication — the thumb
    /// and arrows breathe the accent — so it goes, on both axes. The bar itself
    /// stays: where you are in the content is not which control has the keys.
    @Test("ScrollView's scrollbars")
    func scrollViewScrollbars() {
        let vertical = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { Text("L\($0)") }
            }
        }
        .scrollIndicators(.visible)
        .scrollIndicatorStyle(.scrollbar)
        .frame(width: 12, height: 5)
        expectDistinguishable(vertical, "vertical ScrollView", frames: 2)
        expectIndistinguishable(vertical, "vertical ScrollView", frames: 2)

        let horizontal = ScrollView(.horizontal) {
            Text(String(repeating: "abcdefghij", count: 6))
        }
        .scrollIndicators(.visible)
        .scrollIndicatorStyle(.scrollbar)
        .frame(width: 12, height: 3)
        expectDistinguishable(horizontal, "horizontal ScrollView", frames: 2)
        expectIndistinguishable(horizontal, "horizontal ScrollView", frames: 2)
    }

    /// The "N more above/below" lines breathe while the scroll view is focused,
    /// for the same reason the bar does.
    @Test("ScrollView's text indicators")
    func scrollViewTextIndicators() {
        let scroll = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { Text("L\($0)") }
            }
        }
        .scrollIndicators(.visible)
        .scrollIndicatorStyle(.text)
        .frame(width: 20, height: 6)
        expectDistinguishable(scroll, "ScrollView text indicators", frames: 2)
        expectIndistinguishable(scroll, "ScrollView text indicators", frames: 2)
    }

    /// A `TextEditor`'s scrollbar breathes like a `ScrollView`'s and goes the
    /// same way — but its CARET stays (see `textFieldKeepsItsCaret`), so the
    /// whole picture cannot match an unfocused editor's. The comparison drops
    /// the caret's row, the first, and keeps every other row and every run on
    /// them. Eight lines in four rows make the thumb two rows tall, so the row
    /// below the caret still carries a thumb cell and its run.
    @Test("TextEditor's scrollbar")
    func textEditorScrollbar() {
        let editor = TextEditor(text: .constant((1...8).map { "line \($0)" }.joined(separator: "\n")))
            .frame(width: 12, height: 4)
        let unfocused = rendered(editor, focusOnSubject: false, effectsDisabled: false, skippingRows: 1)
        let focused = rendered(editor, focusOnSubject: true, effectsDisabled: false, skippingRows: 1)
        let suppressed = rendered(editor, focusOnSubject: true, effectsDisabled: true, skippingRows: 1)
        #expect(focused != unfocused, "the editor's bar does not indicate focus, so the case below proves nothing")
        #expect(
            suppressed == unfocused,
            """
            TextEditor's scrollbar still indicates focus with the effect disabled:
              unfocused   \(unfocused.map(\.debugDescription).joined(separator: "\n              "))
              suppressed  \(suppressed.map(\.debugDescription).joined(separator: "\n              "))
            """)
    }

    /// A `TextField` is the documented exception, and the exception is
    /// specific: the CARET survives, because it is the insertion point rather
    /// than an announcement of focus — which is what SwiftUI keeps too. So
    /// this asserts the opposite of the sweep, deliberately.
    @Test("A TextField keeps its caret, which is not a focus effect")
    func textFieldKeepsItsCaret() {
        let field = TextField("name", text: .constant("abc"))
        let unfocused = rendered(field, focusOnSubject: false, effectsDisabled: false)
        let suppressed = rendered(field, focusOnSubject: true, effectsDisabled: true)
        #expect(
            suppressed != unfocused,
            "the caret went away with the focus effects; it is the insertion point")
    }
}
