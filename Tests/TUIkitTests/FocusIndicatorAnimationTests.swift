//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusIndicatorAnimationTests.swift
//
//  Every control that breathes while focused is being converted from "read the
//  clock and re-render the screen" to "hand the run loop a finished cycle" (see
//  ``AnimatedCellRun``). Converting one wrong does not look like a bug — it
//  looks like a WIN, because the page's CPU drops to nothing. It has simply
//  stopped animating. That happened once already (47aa5420).
//
//  So each converted producer is pinned here on the same three points:
//
//  1. focused ⇒ it leaves an animating run,
//  2. unfocused / disabled ⇒ it leaves none (a still cap replayed on a clock is
//     bytes emitted for no change), and
//  3. replaying the CURRENT step is a no-op — which is what proves the run's
//     offset, width and frames actually describe the cells that were drawn. A
//     run in the wrong place is worse than no run at all: it repaints, forever,
//     over whatever is really there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Focus indicator animation")
struct FocusIndicatorAnimationTests {

    // MARK: - Shared assertions

    /// Renders `view` against a context whose fresh `FocusManager` auto-focuses
    /// the first focusable — i.e. the control under test.
    private func focused(_ view: some View, width: Int = 40) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 8))
    }

    /// Asserts the run describes the cells that were actually drawn.
    ///
    /// Splicing a run's *current* frame back over the buffer is precisely what
    /// the run loop does on a tick. At the step the view rendered at, that must
    /// change nothing — so any disagreement about where the run sits, or how
    /// wide it is, shows up here as shifted or clobbered glyphs.
    private func expectReplayIsIdentity(
        _ buffer: FrameBuffer, at step: Int = 0,
        _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let before = visible(buffer)
        for run in buffer.animatedCells {
            let replayed = buffer.composited(
                with: FrameBuffer(lines: [run.frame(at: step)]),
                at: (x: run.offsetX, y: run.offsetY))
            #expect(
                visible(replayed) == before, comment ?? "run \(run) moved the cells",
                sourceLocation: sourceLocation)
        }
    }

    /// A buffer's rows as the terminal shows them: no styling, and no trailing
    /// blanks — compositing squares a buffer's rows off to its widest line, so
    /// a short row picks up padding that never reaches the screen. Anything a
    /// misplaced run would actually do (shift a glyph, overwrite one, split a
    /// wide character) still shows up here.
    private func visible(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map { line in
            String(line.stripped.reversed().drop(while: { $0 == " " }).reversed())
        }
    }

    /// The full contract for a control that should be animating.
    private func expectAnimates(
        _ buffer: FrameBuffer, runs expected: Int,
        _ what: Comment, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            buffer.animatedCells.count == expected, "\(what): wrong number of runs",
            sourceLocation: sourceLocation)
        #expect(
            buffer.animatedCells.allSatisfy { $0.isAnimating }, "\(what): a run is a still picture",
            sourceLocation: sourceLocation)
        expectReplayIsIdentity(buffer, "\(what): the run does not match the drawn cells")
    }

    // MARK: - Button

    @Test("A focused bracketed button hands over both caps")
    func bracketedButtonCaps() {
        let buffer = focused(Button("Save") {})
        expectAnimates(buffer, runs: 2, "bracketed button")

        // The caps are the ends of the control and nothing between them.
        let width = buffer.lines[0].strippedLength
        #expect(buffer.animatedCells.map(\.offsetX).sorted() == [0, width - 1])
        #expect(buffer.animatedCells.allSatisfy { $0.width == 1 })
    }

    @Test("A focused plain button hands over its indicator prefix")
    func plainButtonPrefix() {
        let buffer = focused(Button("Save") {}.buttonStyle(.plain))
        expectAnimates(buffer, runs: 1, "plain button")
        #expect(buffer.animatedCells[0].offsetX == 0)
        #expect(buffer.animatedCells[0].width == BorderRenderer.focusIndicatorWidth)
    }

    @Test("A focused button with a view label hands over its caps too")
    func viewLabelButtonCaps() {
        // The `@ViewBuilder` path composes an HStack rather than assembling a
        // string, so it arrives at its geometry differently and is pinned
        // separately.
        let buffer = focused(Button {} label: { Text("Save") })
        expectAnimates(buffer, runs: 2, "view-label button")
        let width = buffer.lines[0].strippedLength
        #expect(buffer.animatedCells.map(\.offsetX).sorted() == [0, width - 1])
    }

    @Test("An unfocused button animates nothing")
    func unfocusedButtonIsStill() {
        // A sentinel takes the focus first, so the button renders unfocused.
        let context = makeRenderContext(width: 40, height: 8)
        context.environment.focusManager!.register(FocusSentinel())
        let buffer = renderToBuffer(Button("Save") {}, context: context)
        #expect(buffer.animatedCells.isEmpty, "an unfocused button must not animate")
    }

    @Test("A disabled button animates nothing, focus manager or not")
    func disabledButtonIsStill() {
        // Disabled controls never register for focus, but the style is handed
        // `isFocused` independently — so this pins the style's own guard.
        #expect(focused(Button("Save") {}.disabled(true)).animatedCells.isEmpty)
        #expect(
            focused(Button("Save") {}.buttonStyle(.plain).disabled(true)).animatedCells.isEmpty)
    }

    @Test("A button whose style does not animate hands over nothing")
    func steadyStyleIsStill() {
        // `.selectionIndicatorStyle(.none)` means focus is shown by colour
        // alone. There is no cycle, so there is nothing for the loop to replay
        // — and a one-frame run would cost bytes per tick to redraw what is
        // already on screen.
        let buffer = focused(Button("Save") {}.selectionIndicatorStyle(.none))
        #expect(buffer.animatedCells.isEmpty)
    }

    @Test("Every frame of a cap cycle is the same width")
    func capFramesAreUniformWidth() {
        // A frame that did not occupy exactly `width` cells would shove the
        // rest of the row sideways on some ticks and not others — the reflow
        // the whole mechanism exists to avoid.
        for run in focused(Button("Save") {}).animatedCells {
            #expect(run.frames.allSatisfy { $0.strippedLength == run.width }, "run: \(run)")
        }
    }

    // MARK: - Text cursor

    /// A focused field needs a real handler in state storage, so these build a
    /// context the field can register into and render it focused.
    private func focusedField(_ view: some View, width: Int = 30) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 6))
    }

    @Test("A focused text field hands over its caret cells")
    func textFieldCaret() {
        let text = Binding.constant("Ada")
        let buffer = focusedField(TextField("Name", text: text))
        expectAnimates(buffer, runs: 1, "text field caret")
        // Past the opening cap, and one cell wide for a narrow character.
        #expect(buffer.animatedCells[0].offsetX >= 1)
        #expect(buffer.animatedCells[0].width == 1)
    }

    @Test("A secure field's caret animates too, over the mask")
    func secureFieldCaret() {
        let text = Binding.constant("hunter2")
        expectAnimates(focusedField(SecureField("Password", text: text)), runs: 1, "secure field")
    }

    @Test("An unfocused text field animates nothing")
    func unfocusedFieldIsStill() {
        let context = makeRenderContext(width: 30, height: 6)
        context.environment.focusManager!.register(FocusSentinel())
        let buffer = renderToBuffer(
            TextField("Name", text: Binding.constant("Ada")), context: context)
        #expect(buffer.animatedCells.isEmpty)
    }

    @Test("A steady cursor style hands over nothing")
    func steadyCursorIsStill() {
        // `.textCursor(.none)` shows the caret without animating it. One frame
        // is a still picture the render already drew.
        let buffer = focusedField(
            TextField("Name", text: Binding.constant("Ada"))
                .textCursor(TextCursorStyle(shape: .block, animation: .none)))
        #expect(buffer.animatedCells.isEmpty)
    }

    @Test("Every caret shape and animation keeps a constant cell width")
    func caretFramesAreUniformWidth() {
        // A frame that did not occupy exactly `width` cells would shove the
        // rest of the field sideways on some ticks and not others — and a text
        // field is the one control where that would be unmissable.
        for shape in [TextCursorStyle.Shape.block, .bar, .underscore] {
            for animation in [TextCursorStyle.Animation.blink, .pulse] {
                let buffer = focusedField(
                    TextField("Name", text: Binding.constant("Ada"))
                        .textCursor(TextCursorStyle(shape: shape, animation: animation)))
                for run in buffer.animatedCells {
                    #expect(
                        run.frames.allSatisfy { $0.strippedLength == run.width },
                        "\(shape)/\(animation): \(run)")
                }
                expectReplayIsIdentity(buffer, "\(shape)/\(animation)")
            }
        }
    }

    @Test("A caret over a WIDE character covers it whole")
    func caretOverWideCharacter() {
        // The caret's cells and the character's cells have to agree, or the
        // replay repaints one cell of a two-cell glyph and splits it.
        //
        // Driven through the renderer rather than a live field because a field
        // opens with its caret at the END of the text; putting it over the
        // emoji is the whole point of the test.
        let renderer = TextFieldContentRenderer(
            prompt: nil,
            isDisabled: false,
            displayCharacter: { index, text in text[text.index(text.startIndex, offsetBy: index)] },
            contentForeground: nil)
        let content = renderer.buildContent(
            text: "😃ab",
            cursorPosition: 0,
            selectionRange: nil,
            isFocused: true,
            palette: SystemPalette(.green),
            cursorStyle: TextCursorStyle(),
            cursorTimer: nil,
            contentWidth: 10)

        #expect(content.caret?.width == 2, "got: \(String(describing: content.caret))")
        // And every frame still fills exactly those two cells.
        #expect(content.caret?.frames.allSatisfy { $0.strippedLength == 2 } ?? false)
    }

    @Test("A blink cycle really does blink")
    func blinkCycleHasBothHalves() {
        // The whole point of pre-rendering the cycle: it has to contain the
        // caret-on AND caret-off pictures, or the field renders a frozen block.
        let buffer = focusedField(
            TextField("Name", text: Binding.constant("Ada"))
                .textCursor(TextCursorStyle(shape: .block, animation: .blink)))
        let distinct = Set(buffer.animatedCells.first?.frames ?? [])
        #expect(distinct.count == 2, "a blink has exactly two pictures, got \(distinct.count)")
    }

    // MARK: - Radio bullet

    private func radioGroup(
        _ orientation: RadioButtonOrientation = .vertical
    ) -> RadioButtonGroup<String> {
        RadioButtonGroup(selection: .constant("a"), orientation: orientation) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
            RadioButtonItem("c", "Charlie")
        }
    }

    /// Renders twice: the first pass registers the group's handler, the second
    /// reads back whatever `move` did to it. That is also the real sequence —
    /// a key moves the focus and the next frame draws it.
    private func radioBuffer(
        _ orientation: RadioButtonOrientation = .vertical,
        focusedFirst: Bool = true,
        move: (FocusManager) -> Void = { _ in }
    ) -> FrameBuffer {
        let group = radioGroup(orientation)
        let context = makeRenderContext(width: 40, height: 8)
        if !focusedFirst { context.environment.focusManager!.register(FocusSentinel()) }
        _ = renderToBuffer(group, context: context)
        move(context.environment.focusManager!)
        return renderToBuffer(group, context: context)
    }

    @Test("A focused radio group hands over its bullet")
    func radioBullet() {
        let buffer = radioBuffer()
        // One run for the whole group: at most one item holds the focus, so a
        // second run would mean an item is animating that isn't focused.
        expectAnimates(buffer, runs: 1, "radio bullet")
        let run = buffer.animatedCells[0]
        #expect(run.offsetX == 0, "the bullet opens the row")
        #expect(run.offsetY == 0, "the first item has the focus")
        #expect(run.width == TerminalSymbols.radioSelected.strippedLength)
        #expect(run.frames.allSatisfy { $0.strippedLength == run.width })
    }

    @Test("The bullet moves down the group with the focus")
    func radioBulletFollowsFocus() {
        // Each item is its own row, so a vertical group is the case where a run
        // left at row 0 would repaint the wrong item forever — and still look
        // plausible, because something would be pulsing.
        let buffer = radioBuffer { _ = $0.dispatchKeyEvent(KeyEvent(key: .down)) }
        expectAnimates(buffer, runs: 1, "radio bullet after Down")
        #expect(buffer.animatedCells[0].offsetY == 1)
    }

    @Test("A horizontal group's bullet sits at its own item's column")
    func radioBulletHorizontal() {
        // All three items share one row here, so the bullet's column is the
        // only thing distinguishing them.
        let buffer = radioBuffer(.horizontal) { _ = $0.dispatchKeyEvent(KeyEvent(key: .right)) }
        expectAnimates(buffer, runs: 1, "horizontal radio bullet")
        let run = buffer.animatedCells[0]
        #expect(run.offsetY == 0, "a horizontal group is one row")
        #expect(run.offsetX > 0, "the second item does not start at column 0")
    }

    @Test("An unfocused or disabled radio group animates nothing")
    func radioBulletStill() {
        #expect(radioBuffer(focusedFirst: false).animatedCells.isEmpty)
        // A disabled group never registers for focus, and its indicator is
        // drawn from the disabled branch — which has no cycle at all.
        let disabled = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Bravo")
        }.disabled(true)
        #expect(focused(disabled).animatedCells.isEmpty)
    }

    // MARK: - Tab chip

    /// A tab strip claims the focus on its FIRST render, so its focused
    /// appearance is only visible on the second — against the same context.
    private func focusedTabs(_ style: TabViewStyle) -> FrameBuffer {
        let view = TabView(selection: .constant(0)) {
            Tab("Alpha", value: 0) { Text("A") }
            Tab("Bravo", value: 1) { Text("B") }
        }.tabViewStyle(style)
        let context = makeRenderContext(width: 40, height: 10)
        _ = renderToBuffer(view, context: context)
        return renderToBuffer(view, context: context)
    }

    @Test("A focused tab strip hands over its active chip, in either style")
    func tabChip() {
        // Only the active chip: an inactive one is not animating, and a run
        // over it would repaint a colour it never had.
        let compact = focusedTabs(.compact)
        expectAnimates(compact, runs: 1, "compact tab chip")
        #expect(compact.animatedCells[0].offsetY == 0, "the compact strip's only row")

        // The bordered strip puts its labels UNDER a row of tab tops and inside
        // the box's left wall, so its chip is the case where an unshifted run
        // would land on chrome.
        let bordered = focusedTabs(.bordered)
        expectAnimates(bordered, runs: 1, "bordered tab chip")
        #expect(bordered.animatedCells[0].offsetY == 1, "under the tab tops")
        #expect(bordered.animatedCells[0].offsetX > 0, "inside the left wall")
    }

    @Test("An unfocused tab strip animates nothing")
    func unfocusedTabsAreStill() {
        let view = TabView(selection: .constant(0)) {
            Tab("Alpha", value: 0) { Text("A") }
            Tab("Bravo", value: 1) { Text("B") }
        }
        let context = makeRenderContext(width: 40, height: 10)
        context.environment.focusManager!.register(FocusSentinel())
        _ = renderToBuffer(view, context: context)
        #expect(renderToBuffer(view, context: context).animatedCells.isEmpty)
    }

    // MARK: - Toggle indicator

    @Test("A focused toggle hands over its indicator, in every style")
    func toggleIndicator() {
        // Checkbox (brackets or a self-contained glyph) and switch (a coloured
        // track) animate different things, so each is pinned. All of them open
        // the toggle's row, so all of them anchor at the origin.
        for (name, view) in [
            ("checkbox", AnyView(Toggle("On", isOn: .constant(true)))),
            (
                "ascii checkbox",
                AnyView(Toggle("On", isOn: .constant(true)).toggleCharacterSet(.ascii))
            ),
            ("switch", AnyView(Toggle("On", isOn: .constant(true)).toggleStyle(.switch))),
            (
                "ascii switch",
                AnyView(
                    Toggle("On", isOn: .constant(true)).toggleStyle(.switch)
                        .toggleCharacterSet(.ascii))
            ),
        ] {
            let buffer = focused(view)
            expectAnimates(buffer, runs: 1, "\(name) toggle")
            #expect(buffer.animatedCells[0].offsetX == 0, "\(name): the indicator opens the row")
            #expect(buffer.animatedCells[0].offsetY == 0, "\(name): on the first row")
            #expect(
                buffer.animatedCells[0].frames.allSatisfy {
                    $0.strippedLength == buffer.animatedCells[0].width
                }, "\(name): every frame is the same width")
        }
    }

    @Test("An unfocused or disabled toggle animates nothing")
    func toggleIndicatorStill() {
        let context = makeRenderContext(width: 40, height: 8)
        context.environment.focusManager!.register(FocusSentinel())
        #expect(
            renderToBuffer(Toggle("On", isOn: .constant(true)), context: context)
                .animatedCells.isEmpty)
        // A disabled toggle never registers for focus, and its indicator is
        // drawn from the disabled branch, which has no cycle at all.
        #expect(focused(Toggle("On", isOn: .constant(true)).disabled(true)).animatedCells.isEmpty)
    }

    // MARK: - Picker

    @Test("A focused picker hands over its end caps")
    func pickerCaps() {
        // The collapsed control is a bracketed button in all but name, so it
        // shares `ButtonCapCycle` — and must pin the same geometry.
        let buffer = focused(
            Picker("Fruit", selection: .constant("a")) {
                Text("Apple").tag("a")
                Text("Banana").tag("b")
            })
        expectAnimates(buffer, runs: 2, "picker caps")
        // A picker draws its label BEFORE the control, so the caps do not sit
        // at the row's ends — they bracket the control wherever it landed.
        // (`expectAnimates` proves they land on the cells actually drawn.)
        let offsets = buffer.animatedCells.map(\.offsetX).sorted()
        #expect(offsets[0] > 0, "the label precedes the control: \(offsets)")
        #expect(offsets[1] > offsets[0], "one cap at each end of the control")
        #expect(buffer.animatedCells.allSatisfy { $0.offsetY == 0 && $0.width == 1 })
    }

    @Test("An unfocused or disabled picker animates nothing")
    func pickerCapsStill() {
        let context = makeRenderContext(width: 40, height: 8)
        context.environment.focusManager!.register(FocusSentinel())
        let picker = Picker("Fruit", selection: .constant("a")) {
            Text("Apple").tag("a")
            Text("Banana").tag("b")
        }
        #expect(renderToBuffer(picker, context: context).animatedCells.isEmpty)
        #expect(focused(picker.disabled(true)).animatedCells.isEmpty)
    }

    // MARK: - Menu row

    @Test("A focused menu row hands over its whole bar")
    func menuRowBar() {
        // The other producers hand over a mark — a cap, a bullet, a caret. A
        // menu row hands over the ROW: the highlight spans it, so the run has
        // to be as wide as the row is and start at its first cell, or the
        // replay leaves a strip of the previous colour behind.
        let buffer = focused(
            Menu("Demos") {
                Button("First") {}
                Button("Second") {}
            }
            .menuStyle(.inline))
        #expect(buffer.animatedCells.count == 1, "one bar, on the focused row only")
        expectAnimates(buffer, runs: 1, "menu row bar")
        let run = buffer.animatedCells[0]
        // The bar is as wide as the ROW — the rows share a width, so the
        // focused one's bar reaches past its own label to the widest — and it
        // sits inside the menu's frame rather than at the buffer's edge.
        // (`expectAnimates` is what proves it covers the cells actually drawn.)
        #expect(run.offsetX > 0, "the menu's border and padding precede the row")
        #expect(
            run.width >= "Second".count,
            "the bar spans the row, not just its own label: \(run.width)")
        #expect(
            run.frames.allSatisfy { $0.strippedLength == run.width },
            "every frame is the same width")
    }

    @Test("The menu bar moves down the menu with the focus")
    func menuRowBarFollowsFocus() {
        // A menu is a list, so a run left on row 0 repaints the wrong item
        // forever — and still looks plausible, because every row's bar is the
        // same colour. Only its position tells them apart.
        let menu = Menu("Demos") {
            Button("First") {}
            Button("Second") {}
            Button("Third") {}
        }
        .menuStyle(.inline)
        let context = makeRenderContext(width: 40, height: 8)
        _ = renderToBuffer(menu, context: context)  // registers the rows
        context.environment.focusManager?.focusNext()
        let buffer = renderToBuffer(menu, context: context)
        #expect(buffer.animatedCells.count == 1)
        #expect(buffer.animatedCells[0].offsetY > 0, "the bar followed the focus down")
        expectReplayIsIdentity(buffer, "the moved bar does not match the drawn row")
    }

    @Test("An unfocused or disabled menu row animates nothing")
    func menuRowBarStill() {
        let menu = Menu("Demos") {
            Button("First") {}
            Button("Second") {}
        }
        .menuStyle(.inline)
        let context = makeRenderContext(width: 40, height: 8)
        context.environment.focusManager!.register(FocusSentinel())
        #expect(renderToBuffer(menu, context: context).animatedCells.isEmpty)
        #expect(focused(menu.disabled(true)).animatedCells.isEmpty)
    }

    @Test("A button keeps its runs through the tree a page wraps it in")
    func capsSurviveRealChrome() {
        // The producer and the propagation both have to hold for the page to
        // animate; this is the two of them together, which is what the live
        // app actually exercises.
        let page = ScrollView {
            VStack {
                Text("Header")
                Button("Save") {}.padding().border()
            }
        }
        let buffer = focused(page)
        expectAnimates(buffer, runs: 2, "button inside real chrome")
        // Indented by the padding and border it is wrapped in, so this is not
        // accidentally passing on an un-shifted run.
        #expect(buffer.animatedCells.allSatisfy { $0.offsetX > 0 && $0.offsetY > 0 })
    }

    // MARK: - Composers that assemble rows by hand

    // A container that concatenates child STRINGS gets none of what the child
    // buffers carried — every hit region, overlay and run has to be lifted by
    // name. Three of them lifted the regions (clicks worked) and dropped the
    // runs, so a focused button in a button row or a dialog footer went bold
    // and then sat perfectly still: the loop keeps its clock alive from the
    // runs on the final buffer, so a run that never arrives is a freeze.

    @Test("A ButtonRow carries its focused button's caps")
    func buttonRowLiftsRuns() {
        let buffer = focused(
            ButtonRow {
                Button("Cancel") {}
                Button("OK") {}
            })
        expectAnimates(buffer, runs: 2, "focused button in a ButtonRow")
    }

    @Test("A dialog's horizontal button row carries them too")
    func alertButtonRowLiftsRuns() {
        let buffer = focused(
            AlertButtonRow(buttons: [Button("Delete") {}, Button("Cancel") {}]))
        expectAnimates(buffer, runs: 2, "focused button in an alert row")
    }

    @Test("A dialog's stacked button column carries them too")
    func alertButtonColumnLiftsRuns() {
        let buffer = focused(
            AlertButtonColumn(buttons: [Button("Delete") {}, Button("Cancel") {}]))
        expectAnimates(buffer, runs: 2, "focused button in an alert column")
    }

    @Test("A TabView carries its content's runs as well as its own chip's")
    func tabViewLiftsContentRuns() {
        // Both styles assembled their panel and then ASSIGNED the strip's runs
        // over whatever the content had contributed, so every focused control
        // inside a tab stopped moving. The chip and the button must both be
        // animating, and the button's run must be shifted down past the strip.
        for style in [TabViewStyle.compact, .bordered] {
            let view = TabView(selection: .constant(0)) {
                Tab("Alpha", value: 0) { Button("Save") {} }
                Tab("Bravo", value: 1) { Text("B") }
            }.tabViewStyle(style)
            let context = makeRenderContext(width: 40, height: 12)
            _ = renderToBuffer(view, context: context)  // the strip claims focus
            let ring = context.environment.focusManager?.registeredFocusIDsInActiveSection() ?? []
            let buttonID = ring.first { $0.hasPrefix("button") }
            #expect(buttonID != nil, "\(style): no button in the ring: \(ring)")
            context.environment.focusManager?.focus(id: buttonID ?? "")
            let buffer = renderToBuffer(view, context: context)

            // Two caps from the button; the chip is no longer focused, so it
            // contributes none.
            expectAnimates(buffer, runs: 2, "\(style): button inside a tab")
            #expect(
                buffer.animatedCells.allSatisfy { $0.offsetY > 0 },
                "\(style): a content run was left at the strip's row")
        }
    }

    @Test("A row lifts the runs of the button that actually has focus")
    func rowRunsSitOnTheFocusedButton() {
        // Two buttons, one focused: the runs must land on the focused one's
        // cells, not the first one's. A composer that forgot the x-shift would
        // pass the count check above and put both caps on the wrong button —
        // which `expectAnimates`'s replay check would catch as a glyph moving,
        // so this pins the *identity* instead: the caps sit either side of "OK".
        let context = makeRenderContext(width: 40, height: 8)
        let row = ButtonRow {
            Button("Cancel") {}
            Button("OK") {}
        }
        _ = renderToBuffer(row, context: context)  // register the ring
        let ring = context.environment.focusManager?.registeredFocusIDsInActiveSection() ?? []
        #expect(ring.count == 2, "two buttons, two focus ids: \(ring)")
        context.environment.focusManager?.focus(id: ring[1])
        let buffer = renderToBuffer(row, context: context)

        expectAnimates(buffer, runs: 2, "second button focused")
        let line = buffer.lines[0].stripped
        let okStart = line.range(of: "OK").map { line.distance(from: line.startIndex, to: $0.lowerBound) }
        #expect(okStart != nil, "line: \(line.debugDescription)")
        let columns = buffer.animatedCells.map(\.offsetX).sorted()
        #expect(columns.allSatisfy { $0 > 2 }, "caps landed on the first button: \(columns)")
    }
}

/// Claims auto-focus before the control under test renders, so that control
/// renders in its un-focused state.
private final class FocusSentinel: Focusable {
    let focusID = "focus-indicator-animation-sentinel"
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}
