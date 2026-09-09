//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollableEnvironmentWiringTests.swift
//
//  Every scrollable row view captures the same environment into its handler at
//  render, because that is where events read it from — a mouse wheel or a key
//  arrives long after the environment is out of reach. There are four places
//  that capture (List, single-line Table, multi-line Table, ScrollView) and
//  nothing but review has ever kept them in step, which is how `.scrollDisabled`
//  reached only one Table path when it shipped, and how the two values asserted
//  here reached three of the four.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scrollables capture the same environment")
struct ScrollableEnvironmentWiringTests {

    private struct Row: Identifiable {
        let id: Int
        var name: String
        var note: String
    }

    private static let rows = (1...12).map {
        Row(id: $0, name: "row \($0)", note: "note \($0) with several words to wrap")
    }

    /// Two rows in a six-line frame: nothing is hidden, whatever the app asked
    /// for. The `rows` fixture above is twelve in six and always overflows.
    private static let fewRows = Array(rows.prefix(2))

    /// Renders `view` with a drag session and a zero chaining delay in scope,
    /// Tabs to focus it, and hands back whichever `ItemListHandler` that is —
    /// the one the view's own events will consult.
    private func focusedRowHandler(
        _ view: some View, session: DragAndDropSession, height: Int = 8
    ) -> ItemListHandler<Int>? {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.dragAndDropSession = session

        var context = RenderContext(
            availableWidth: 40, availableHeight: height, environment: environment,
            tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true

        _ = renderToBuffer(view.scrollChainingDelay(.zero), context: context)
        let focus = environment.focusManager!
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        return focus.currentFocused as? ItemListHandler<Int>
    }

    /// The three viewports, by index, each wrapped in the same non-default
    /// environment — which is the whole point: an assertion against a value that
    /// is ALSO the default passes whether the capture happened or not, and this
    /// suite exists to catch a capture that did not.
    ///
    /// The session is created by the CALLER and passed in, because
    /// ``ItemListHandler/dragSession`` is `weak`: built and dropped here it would
    /// be gone before the assertions run, and the case would report a defect that
    /// is not there.
    private func handler(
        _ which: Int, session: DragAndDropSession
    ) -> ItemListHandler<Int>? {
        func wrapped(_ view: some View) -> some View {
            view
                .shiftStepMultiplier(9)
                .scrollGranularity(.row)
                .scrollFollowMargin(.steps(2))
                .rowReorderFeedback(.dimmed)
        }
        return switch which {
        case 0: focusedRowHandler(wrapped(singleLineTable()), session: session)
        case 1: focusedRowHandler(wrapped(multiLineTable()), session: session)
        default: focusedRowHandler(wrapped(list()), session: session)
        }
    }

    /// The three viewports as `@Test` arguments. `nonisolated` because the
    /// `@Test` macro reads it outside the suite's actor.
    nonisolated static let arms = [
        ("single-line Table", 0), ("multi-line Table", 1), ("List", 2),
    ]

    private func singleLineTable() -> some View {
        Table(Self.rows, selection: .constant(Set<Int>())) {
            TableColumn("Name", value: \Row.name).width(.flexible)
        }
        .frame(height: 6)
    }

    private func multiLineTable() -> some View {
        Table(Self.rows, selection: .constant(Set<Int>())) {
            TableColumn("Note", value: \Row.note).width(.flexible).lineLimit(3)
        }
        .frame(height: 6)
    }

    private func list() -> some View {
        List(selection: .constant(Set<Int>())) {
            ForEach(Self.rows) { Text($0.name) }
        }
        .frame(height: 6)
    }

    /// `.scrollChainingDelay(_:)` documents itself as reaching "List, Table,
    /// ScrollView, both axes". A view that misses it keeps the 500 ms default
    /// forever: an app asking for immediate chaining (or a longer hold) is
    /// simply not answered, and nothing says so.
    @Test(
        "The chaining delay reaches every row view",
        arguments: [("single-line Table", 0), ("multi-line Table", 1), ("List", 2)])
    func chainingDelayReachesEveryRowView(name: String, which: Int) {
        let session = DragAndDropSession()
        let handler: ItemListHandler<Int>? =
            switch which {
            case 0: focusedRowHandler(singleLineTable(), session: session)
            case 1: focusedRowHandler(multiLineTable(), session: session)
            default: focusedRowHandler(list(), session: session)
            }
        guard let handler else {
            Issue.record("\(name): expected the row view to take focus")
            return
        }
        #expect(
            handler.wheelEdgeHold.delayNanos == 0,
            "\(name): the modifier is what decides the grace period, not the default")
    }

    /// The session is how a handler reaches anything outside itself mid-gesture:
    /// the view under the pointer for the navigators, and the floating preview
    /// to take it down on a cancel. Without it a handler can only ever answer
    /// with itself.
    @Test(
        "The drag session reaches every row view",
        arguments: [("single-line Table", 0), ("multi-line Table", 1), ("List", 2)])
    func dragSessionReachesEveryRowView(name: String, which: Int) {
        let session = DragAndDropSession()
        let handler: ItemListHandler<Int>? =
            switch which {
            case 0: focusedRowHandler(singleLineTable(), session: session)
            case 1: focusedRowHandler(multiLineTable(), session: session)
            default: focusedRowHandler(list(), session: session)
            }
        guard let handler else {
            Issue.record("\(name): expected the row view to take focus")
            return
        }
        #expect(
            handler.dragSession === session,
            "\(name): the handler holds the session its gestures run in")
    }

    /// The captures that are the same on all three paths. One case rather than
    /// one per property, because the failure mode being guarded is "a viewport
    /// missed the block", not "a viewport got one line wrong" — and a single case
    /// is what makes the whole block's absence show up as one clear failure.
    ///
    /// Not asserted here, for stated reasons rather than by omission:
    /// `shortcuts` is a `RowShortcutLookup`, which is not `Equatable` and whose
    /// `.default` answers every chord anyway, so only a behavioural oracle would
    /// mean anything (`RowShortcutsTests` has one); and `anchorPositionBinding`
    /// is a `Binding`, likewise not comparable. `wheelEdgeHold` and `dragSession`
    /// have their own cases above.
    @Test("The shared environment captures reach every row view", arguments: arms)
    func sharedCapturesReachEveryRowView(name: String, which: Int) {
        let session = DragAndDropSession()
        guard let handler = handler(which, session: session) else {
            Issue.record("\(name): expected the row view to take focus")
            return
        }
        #expect(handler.shiftStepMultiplier == 9, "\(name): shiftStepMultiplier")
        #expect(handler.scrollGranularity == .row, "\(name): scrollGranularity")
        #expect(handler.followMargin == .steps(2), "\(name): followMargin")
        #expect(handler.canFloatDraggedRow, "\(name): canFloatDraggedRow")
        #expect(handler.isScrollEnabled, "\(name): isScrollEnabled")
    }

    /// `.scrollDisabled(true)` is the one shared capture whose non-default value
    /// cannot share a fixture with the case above — it is a gate the other
    /// assertions would then be measured through.
    @Test("Scroll disabling reaches every row view", arguments: arms)
    func scrollDisabledReachesEveryRowView(name: String, which: Int) {
        let session = DragAndDropSession()
        let view: any View =
            switch which {
            case 0: singleLineTable().scrollDisabled(true)
            case 1: multiLineTable().scrollDisabled(true)
            default: list().scrollDisabled(true)
            }
        guard let handler = focusedRowHandler(AnyView(view), session: session) else {
            Issue.record("\(name): expected the row view to take focus")
            return
        }
        #expect(!handler.isScrollEnabled, "\(name): .scrollDisabled did not reach the handler")
    }

    /// The three values that legitimately DIFFER per viewport, which is why
    /// `syncFrameInputs` takes them as required arguments rather than reading
    /// them all from the environment.
    ///
    /// The fixture puts `.dimmed` in the environment deliberately. Both the
    /// handler's default and the environment's default are `.live`, so a case
    /// that asserted `.live` on the multi-line arm from a default fixture would
    /// pass with the assignment deleted — it has to assert `.live` DESPITE an
    /// environment asking for `.dimmed`, and `.dimmed` on the two arms that
    /// honour it.
    @Test("The per-path values are what each path says they are", arguments: arms)
    func perPathValuesDifferAsIntended(name: String, which: Int) {
        let session = DragAndDropSession()
        guard let handler = handler(which, session: session) else {
            Issue.record("\(name): expected the row view to take focus")
            return
        }
        let isMultiLineTable = which == 1
        #expect(
            handler.reorderFeedback == (isMultiLineTable ? .live : .dimmed),
            """
            \(name): a multi-line Table forces .live because its composer draws \
            no slot; every other viewport honours the app's choice
            """)
        #expect(
            handler.keyboardMoveIsLive == isMultiLineTable,
            "\(name): keyboardMoveIsLive follows the same rule, on every path")
        #expect(
            (handler.rowHeight == nil) == (which == 0),
            """
            \(name): only uniform single-line rows may answer nil, where the \
            scroll arithmetic counts rows instead of lines
            """)
    }

    /// `drawsScrollIndicators` has to mean the same thing on all three viewports,
    /// because one rule reads it: `ScrollRowWindow` reserves a content line when
    /// it is true.
    ///
    /// Its documented meaning is "whether this frame's render SPENDS content
    /// lines on the indicators" — so a view with nothing hidden must report
    /// false, however loudly the app asked for indicators. `Table` folded
    /// `overflowing` in on both its paths; `_ListCore` did not, and reported true
    /// on a list that reserved nothing.
    ///
    /// The fixture asks for `.visible` deliberately. Under the default
    /// `.automatic`, `ScrollIndicatorVisibility.showsIndicator` returns
    /// `overflowing` itself, so all three agree already and the case would pass
    /// against the bug. `.visible` is the one visibility that says "yes" without
    /// consulting the content.
    @Test(
        "Whether indicators spend lines means the same on every row view",
        arguments: arms, [false, true])
    func indicatorSpendMeansOneThing(arm: (name: String, which: Int), overflows: Bool) {
        let session = DragAndDropSession()
        let data = overflows ? Self.rows : Self.fewRows
        // `.visible` + text: the affordance is unconditional, so a line comes out
        // of the content area whether or not anything is hidden — that is what
        // `.visible` is for, a viewport that does not resize under the reader.
        // (It used to consult the content here, which is `.automatic`'s job; the
        // sibling test below pins that one.)
        func loud(_ view: some View) -> some View {
            view.scrollIndicators(.visible).scrollIndicatorStyle(.text)
        }
        let handler: ItemListHandler<Int>? =
            switch arm.which {
            case 0:
                focusedRowHandler(
                    loud(
                        Table(data, selection: .constant(Set<Int>())) {
                            TableColumn("Name", value: \Row.name).width(.flexible)
                        }
                        .frame(height: 6)), session: session)
            case 1:
                focusedRowHandler(
                    loud(
                        Table(data, selection: .constant(Set<Int>())) {
                            TableColumn("Note", value: \Row.note).width(.flexible).lineLimit(3)
                        }
                        .frame(height: 6)), session: session)
            default:
                focusedRowHandler(
                    loud(
                        List(selection: .constant(Set<Int>())) {
                            ForEach(data) { Text($0.name) }
                        }
                        .frame(height: 6)), session: session)
            }
        guard let handler else {
            Issue.record("\(arm.name): expected the row view to take focus")
            return
        }
        #expect(
            handler.drawsScrollIndicators,
            """
            \(arm.name), \(overflows ? "overflowing" : "everything fits"): reported \
            \(handler.drawsScrollIndicators). The flag is "does a line come out of \
            the content area this frame", and one shared window rule reserves on it.
            """)
        #expect(
            handler.alwaysReservesIndicatorLines,
            "\(arm.name): `.visible` reserves both lines at every offset")
    }

    /// The `.automatic` half of the same rule, on the same three views: there the
    /// indicator IS a hint, so a line comes out only when something is hidden.
    /// Without this, "`.visible` always reserves" could be satisfied by every
    /// visibility always reserving.
    @Test(
        "Automatic indicators spend a line only when the content overflows",
        arguments: arms, [false, true])
    func automaticIndicatorsSpendOnOverflow(
        arm: (name: String, which: Int), overflows: Bool
    ) {
        let session = DragAndDropSession()
        let data = overflows ? Self.rows : Self.fewRows
        func quiet(_ view: some View) -> some View {
            view.scrollIndicators(.automatic).scrollIndicatorStyle(.text)
        }
        let handler: ItemListHandler<Int>? =
            switch arm.which {
            case 0:
                focusedRowHandler(
                    quiet(
                        Table(data, selection: .constant(Set<Int>())) {
                            TableColumn("Name", value: \Row.name).width(.flexible)
                        }
                        .frame(height: 6)), session: session)
            case 1:
                focusedRowHandler(
                    quiet(
                        Table(data, selection: .constant(Set<Int>())) {
                            TableColumn("Note", value: \Row.note).width(.flexible).lineLimit(3)
                        }
                        .frame(height: 6)), session: session)
            default:
                focusedRowHandler(
                    quiet(
                        List(selection: .constant(Set<Int>())) {
                            ForEach(data) { Text($0.name) }
                        }
                        .frame(height: 6)), session: session)
            }
        guard let handler else {
            Issue.record("\(arm.name): expected the row view to take focus")
            return
        }
        #expect(
            handler.drawsScrollIndicators == overflows,
            "\(arm.name), \(overflows ? "overflowing" : "everything fits")")
        #expect(
            !handler.alwaysReservesIndicatorLines,
            "\(arm.name): `.automatic` reserves only what it has something to say about")
    }
}
