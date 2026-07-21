//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollAnchorPositionTests.swift
//
//  `.anchorPosition(_:)` — the bound anchor override. The load-bearing rule is
//  that `nil` and `.window` are DISTINCT: `nil` means "no departure from the
//  declared anchor" (so writing it restores the declaration), `.window` means
//  "explicitly released". That distinction is what lets an app tell "still
//  following the log" from "the user scrolled away".
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Scroll anchor position")
struct ScrollAnchorPositionTests {

    // MARK: - Precedence: nil falls back, non-nil overrides

    @Test("nil means no departure — the declared anchor stands")
    func nilFallsBackToDeclaration() {
        #expect(
            ScrollAnchorMode.effective(boundAnchor: nil, defaultScrollAnchor: .bottom) == .bottom)
        #expect(
            ScrollAnchorMode.effective(boundAnchor: nil, defaultScrollAnchor: .top) == .top)
        // No declaration either → Window, the spec's default.
        #expect(ScrollAnchorMode.effective(boundAnchor: nil, defaultScrollAnchor: nil) == .window)
    }

    @Test("A non-nil bound anchor overrides the declaration")
    func boundAnchorOverrides() {
        #expect(
            ScrollAnchorMode.effective(boundAnchor: .window, defaultScrollAnchor: .bottom)
                == .window)
        #expect(
            ScrollAnchorMode.effective(boundAnchor: .top, defaultScrollAnchor: .bottom) == .top)
        #expect(
            ScrollAnchorMode.effective(
                boundAnchor: .row(AnyHashable("r7")), defaultScrollAnchor: .bottom) == .row)
    }

    /// The question that motivated the optional: with a plain `Binding<ID?>`
    /// both of these would read `nil` and be indistinguishable.
    @Test("`.window` and nil are distinct — released vs never-left")
    func releasedIsDistinctFromNeverLeft() {
        let declared = UnitPoint.bottom

        // Never departed: still following the declared bottom.
        let stillFollowing = ScrollAnchorMode.effective(
            boundAnchor: nil, defaultScrollAnchor: declared)
        // Departed: the user scrolled away.
        let released = ScrollAnchorMode.effective(
            boundAnchor: .window, defaultScrollAnchor: declared)

        #expect(stillFollowing == .bottom)
        #expect(released == .window)
        #expect(stillFollowing != released, "an app can tell these apart")
    }

    // MARK: - The binding bridge (ID ↔ AnyHashable)

    @Test("A row anchor round-trips through the erased binding")
    func rowRoundTrips() {
        final class Box { var anchor: ScrollAnchor<String>? }
        let box = Box()
        let binding = Binding<ScrollAnchor<String>?>(
            get: { box.anchor }, set: { box.anchor = $0 })

        // Drive the same erasure the modifier builds.
        var erased: ErasedScrollAnchor?
        let bridge = Binding<ErasedScrollAnchor?>(
            get: { erased },
            set: { newValue in
                erased = newValue
                switch newValue {
                case .none: binding.wrappedValue = nil
                case .top: binding.wrappedValue = .top
                case .bottom: binding.wrappedValue = .bottom
                case .window: binding.wrappedValue = .window
                case .row(let id):
                    if let typed = id.base as? String { binding.wrappedValue = .row(typed) }
                }
            })

        bridge.wrappedValue = .row(AnyHashable("row-42"))
        #expect(box.anchor == .row("row-42"), "AnyHashable preserved the base value")

        bridge.wrappedValue = .window
        #expect(box.anchor == .window)

        bridge.wrappedValue = nil
        #expect(box.anchor == nil, "writing nil restores the declaration")
    }

    @Test("The erased row anchor exposes the ForEach-spelling key")
    func rowKeySpelling() {
        // Must match how ForEach builds child keys: String(describing:) of the id.
        #expect(ErasedScrollAnchor.row(AnyHashable("abc")).rowKey == "abc")
        #expect(ErasedScrollAnchor.row(AnyHashable(7)).rowKey == "7")
        #expect(ErasedScrollAnchor.window.rowKey == nil)
        #expect(ErasedScrollAnchor.bottom.rowKey == nil)
    }

    // MARK: - Edges are not rows

    /// Guards the design decision: `.top`/`.bottom` are positional, `.row` is
    /// identity, and they must not be interchangeable. If someone later
    /// "simplifies" the enum by encoding edges as sentinel rows, this fails.
    @Test("Edge anchors and row anchors resolve to different modes")
    func edgesAreNotRows() {
        let asRow = ScrollAnchorMode.effective(
            boundAnchor: .row(AnyHashable(0)), defaultScrollAnchor: nil)
        let asTop = ScrollAnchorMode.effective(boundAnchor: .top, defaultScrollAnchor: nil)
        #expect(asRow == .row)
        #expect(asTop == .top)
        #expect(asRow != asTop, "row 0 is not the same policy as 'stay at the top'")
    }

    // MARK: - Release on a USER scroll

    private func boundHandler() -> (ScrollViewHandler, () -> ScrollAnchor<AnyHashable>?) {
        final class Box { var anchor: ScrollAnchor<AnyHashable>? }
        let box = Box()
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.anchorPositionBinding = Binding(
            get: { box.anchor }, set: { box.anchor = $0 })
        return (handler, { box.anchor })
    }

    @Test("A user wheel scroll releases the anchor to .window")
    func wheelReleases() {
        let (handler, read) = boundHandler()
        #expect(read() == nil, "starts undeparted")

        _ = handler.handleWheelEvent(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0))
        #expect(read() == .window, "the user scrolled — the anchor is released")
    }

    /// The distinction is only useful if it survives a held wheel without
    /// churning `@State` — releasing twice must write once.
    @Test("Releasing is idempotent while already released")
    func releaseIsIdempotent() {
        final class Box {
            var anchor: ScrollAnchor<AnyHashable>?
            var writes = 0
        }
        let box = Box()
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.anchorPositionBinding = Binding(
            get: { box.anchor }, set: { box.anchor = $0; box.writes += 1 })

        handler.releaseAnchorOnUserScroll()
        handler.releaseAnchorOnUserScroll()
        handler.releaseAnchorOnUserScroll()
        #expect(box.anchor == .window)
        #expect(box.writes == 1, "a held wheel doesn't churn the binding")
    }

    /// The load-bearing negative: a scrollTo seek, a focus reveal, or a clamp
    /// after the data shrank must NOT look like the user scrolling away, or an
    /// app would appear to abandon its own declared anchor untouched.
    @Test("A programmatic move does NOT release the anchor")
    func programmaticMoveDoesNotRelease() {
        let (handler, read) = boundHandler()

        handler.scroll(by: 5)          // the path scrollTo / reveal / clamp use
        #expect(handler.scrollOffset > 0, "it really moved")
        #expect(read() == nil, "still following the declared anchor")

        handler.clampScrollOffset()
        #expect(read() == nil, "a clamp is not a user scroll either")
    }

    @Test("A wheel event that cannot move the viewport does not release")
    func blockedWheelDoesNotRelease() {
        final class Box { var anchor: ScrollAnchor<AnyHashable>? }
        let box = Box()
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 5      // fits entirely — nothing to scroll
        handler.viewportHeight = 10
        handler.anchorPositionBinding = Binding(
            get: { box.anchor }, set: { box.anchor = $0 })

        _ = handler.handleWheelEvent(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0))
        #expect(box.anchor == nil, "a wheel tick that moved nothing isn't a departure")
    }

    // MARK: - Release on a KEYBOARD scroll

    /// An anchored ScrollView re-derives its offset from the anchor every
    /// render, so an arrow key that only nudged `scrollOffset` was pulled
    /// straight back — the keys looked dead. A keyboard scroll must release the
    /// anchor exactly as the wheel does.
    @Test("An arrow-key scroll releases the anchor to .window")
    func arrowKeyReleases() {
        let (handler, read) = boundHandler()
        #expect(read() == nil, "starts undeparted")

        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))
        #expect(read() == .window, "the arrow key scrolled — the anchor is released")
    }

    @Test("Page and Home/End also release the anchor")
    func pageAndJumpKeysRelease() {
        for key in [Key.pageDown, .end, .home] {
            let (handler, read) = boundHandler()
            if key == .home { handler.scrollOffset = 5 }  // give Home somewhere to go
            _ = handler.handleKeyEvent(KeyEvent(key: key))
            #expect(read() == .window, "\(key) is a user scroll — releases the anchor")
        }
    }

    /// An arrow key that cannot move the viewport (content fits) must not
    /// release — matching the blocked-wheel rule, so browsing a short anchored
    /// view with the keyboard doesn't spuriously drop the anchor.
    @Test("An arrow key that cannot move the viewport does not release")
    func blockedArrowDoesNotRelease() {
        final class Box { var anchor: ScrollAnchor<AnyHashable>? }
        let box = Box()
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = 5      // fits entirely — nothing to scroll
        handler.viewportHeight = 10
        handler.anchorPositionBinding = Binding(
            get: { box.anchor }, set: { box.anchor = $0 })

        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))
        #expect(box.anchor == nil, "a key press that moved nothing isn't a departure")
    }

    // MARK: - Selection → Row (the §1.2 shadow-switch)

    private func listHandler(
        declared: ScrollAnchorMode, bound: ScrollAnchor<AnyHashable>? = nil
    ) -> (ItemListHandler<String>, () -> ScrollAnchor<AnyHashable>?) {
        final class Box { var anchor: ScrollAnchor<AnyHashable>? }
        let box = Box()
        let handler = ItemListHandler<String>(
            focusID: "list", itemCount: 5, viewportHeight: 5, selectionMode: .single)
        handler.itemIDs = ["a", "b", "c", "d", "e"]
        handler.declaredAnchorMode = declared
        box.anchor = bound
        handler.anchorPositionBinding = Binding(
            get: { box.anchor }, set: { box.anchor = $0 })
        return (handler, { box.anchor })
    }

    @Test("Selecting a row turns a declared Bottom anchor into Row on that row")
    func selectionSwitchesEdgeToRow() {
        let (handler, read) = listHandler(declared: .bottom)
        handler.focusedIndex = 2

        handler.handleSelectionKey(.space)
        #expect(read() == .row(AnyHashable("c")), "follow-the-log now holds the picked row")
    }

    @Test("A click selection switches too")
    func clickSwitchesEdgeToRow() {
        let (handler, read) = listHandler(declared: .top)
        handler.handleClickSelection(
            at: 3, event: MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        #expect(read() == .row(AnyHashable("d")))
    }

    /// Scoping negative 1 — the spec switches **Top/Bottom** to Row. A view
    /// already released to `.window` is being browsed freely; selecting there
    /// must not silently start holding a row.
    @Test("Selecting does NOT re-anchor a view already released to .window")
    func selectionLeavesReleasedViewAlone() {
        let (handler, read) = listHandler(declared: .bottom, bound: .window)
        handler.focusedIndex = 1

        handler.handleSelectionKey(.space)
        #expect(read() == .window, "the user is browsing; selection doesn't re-anchor")
    }

    /// Scoping negative 2 — with no edge declared there is no edge policy to
    /// switch away from, so Window stays Window.
    @Test("Selecting does NOT anchor when the declared mode is Window")
    func selectionDoesNotAnchorUndeclared() {
        let (handler, read) = listHandler(declared: .window)
        handler.focusedIndex = 1

        handler.handleSelectionKey(.space)
        #expect(read() == nil, "nothing was declared to depart from")
    }

    @Test("With no bound anchor, selection is inert (no crash, nothing to write)")
    func selectionWithoutBindingIsInert() {
        let handler = ItemListHandler<String>(
            focusID: "list", itemCount: 3, viewportHeight: 3, selectionMode: .single)
        handler.itemIDs = ["a", "b", "c"]
        handler.declaredAnchorMode = .bottom
        handler.focusedIndex = 1
        handler.handleSelectionKey(.space)  // must not trap
    }

    // MARK: - Rendering through the modifier

    @Test("A bound .window anchor reaches the render path and takes effect")
    func modifierReachesTheRenderPath() {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = FocusManager()

        let view = ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("row \($0)") }
            }
        }
        .defaultScrollAnchor(.bottom)
        .anchorPosition(.constant(ScrollAnchor<Int>.window))
        .frame(height: 6)

        var context = RenderContext(
            availableWidth: 20, availableHeight: 8, environment: env, tuiContext: tui)
        context.hasExplicitHeight = true
        let buffer = renderToBuffer(view, context: context)
        #expect(!buffer.lines.isEmpty, "renders with a bound anchor in scope")
    }
}
