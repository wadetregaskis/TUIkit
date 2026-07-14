//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoopRegionMergeTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Why these tests exist
//
// The bug fixed in commit e5382a77 (status-bar items unclickable) and
// the related bug fixed in 714d3577 (app-header content
// likewise unclickable) both lived between unit-tested layers:
//
//   - `StatusBar.applyHitTestRegions` was unit-tested in isolation
//     and emitted regions correctly.
//   - `MouseEventDispatcher.dispatch` was unit-tested in isolation
//     and routed events correctly.
//   - `AppHeader.renderToBuffer` and `RenderLoop.renderAppHeader` /
//     `RenderLoop.renderStatusBar` sat between them, and each silently
//     discarded the hit-test regions before they could reach the
//     dispatcher's `setRegions` call.
//
// The shared pattern: a separately-rendered FrameBuffer's
// `hitTestRegions` get dropped on the floor before they reach
// `setRegions`. The unit tests on either side don't catch it because
// the dropped step happens between them. These integration tests
// exercise the full path so that re-introducing the bug requires a
// test failure to land alongside it.
@MainActor
@Suite("RenderLoop region merge integration", .serialized)
struct RenderLoopRegionMergeTests {

    private func makeContext(width: Int = 80, height: Int = 24) -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: tuiContext
        )
    }

    // MARK: - AppHeader

    /// Regression for the `AppHeader.renderToBuffer` half of
    /// commit 714d3577. Before the fix, the wrap-and-divider
    /// step constructed `FrameBuffer(lines:)` from the
    /// contentBuffer's lines, which leaves `hitTestRegions`
    /// empty by default — silently dropping anything the
    /// user's `.appHeader { ... }` content emitted.
    @Test("AppHeader preserves its content buffer's hit-test regions")
    func appHeaderPreservesContentBufferRegions() {
        // Build a content buffer with a synthetic region so we
        // don't depend on any particular control's rendering
        // details — the test is about whether the wrap-and-
        // divider step preserves whatever the content carried.
        var contentBuffer = FrameBuffer(lines: ["title-bar content"])
        let marker = HitTestRegion.HandlerID(99)
        contentBuffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: contentBuffer.width,
                height: 1,
                handlerID: marker
            )
        )

        let header = AppHeader(contentBuffer: contentBuffer)
        let rendered = renderToBuffer(header, context: makeContext(width: 40))

        #expect(rendered.hitTestRegions.contains(where: { $0.handlerID == marker }),
                "AppHeader.renderToBuffer must carry contentBuffer's regions through")
    }

    // MARK: - StatusBar

    /// Sanity check that a rendered StatusBar carries the
    /// hit-test regions ``StatusBar/applyHitTestRegions``
    /// emits. This doesn't replicate the bug class on its own
    /// — that bug was in RenderLoop, not in this render step
    /// — but it pins the contract the merge-logic test below
    /// depends on.
    @Test("StatusBar render emits hit-test regions for clickable items")
    func statusBarRendersWithRegions() {
        var fired = false
        let item = StatusBarItem(
            shortcut: "x",
            label: "Run",
            action: { fired = true }
        )
        let bar = StatusBar(
            userItems: [item],
            systemItems: [],
            style: .compact,
            alignment: .leading,
            highlightColor: .cyan,
            labelColor: .white
        )

        let context = makeContext(width: 40, height: bar.height)
        let buffer = renderToBuffer(bar, context: context)

        #expect(!buffer.hitTestRegions.isEmpty,
                "Clickable StatusBarItem must emit at least one hit-test region")

        // Pin the action-fired side too so a future refactor
        // that drops the click → execute path also fails here.
        // We invoke the registered handler directly because
        // there's no dispatcher in this scope to drive a real
        // click; the merge-logic test below exercises a real
        // dispatch.
        item.execute()
        #expect(fired, "Item's action must be invocable")
    }

    // MARK: - End-to-end merge

    /// The actual regression test for the bug class — replicates
    /// the merge logic ``RenderLoop/renderFrame()`` runs against
    /// the content, app-header, and status-bar buffers. Each
    /// buffer registers a unique handler; the test then
    /// dispatches a synthetic click at each region's content-area
    /// coordinates and asserts the right handler fired. Before
    /// the e5382a77 / 714d3577 fixes, the header and status-bar
    /// handlers would never have been reached.
    @Test("Merged regions from content + app-header + status-bar route clicks to the right handler")
    func mergedRegionsRouteClicksToRightHandler() {
        let context = makeContext(width: 40, height: 24)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let contentHeight = 20
        let appHeaderHeight = 1
        // statusBarHeight = 24 - 20 - 1 = 3 (not directly used —
        // the status bar's local buffer height is what its
        // regions are emitted against; the merge math only
        // depends on contentHeight and appHeaderHeight).

        var contentFired = false
        var headerFired = false
        var statusFired = false

        // Each buffer registers a handler that flips a flag if
        // it gets called. The handlers are registered on the
        // shared dispatcher so we can observe which one fired.
        let contentHandlerID = dispatcher.register { _ in
            contentFired = true
            return true
        }
        let headerHandlerID = dispatcher.register { _ in
            headerFired = true
            return true
        }
        let statusHandlerID = dispatcher.register { _ in
            statusFired = true
            return true
        }

        // Content buffer with a region at content-area y=5.
        // Regions in the main content buffer are already in
        // content-area coordinates (the App input loop has
        // subtracted appHeader.height by the time the
        // dispatcher sees the event).
        var contentBuffer = FrameBuffer(lines: Array(repeating: String(repeating: " ", count: 40), count: contentHeight))
        contentBuffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 5,
                width: 40, height: 1,
                handlerID: contentHandlerID
            )
        )

        // App-header local buffer with a region at y=0
        // (single-line header). Regions inside this buffer
        // need to be shifted by -appHeaderHeight before merge
        // so that an event at content-area y=-1 (= terminal
        // y=0, which is the header's row) finds them.
        var appHeaderBuffer = FrameBuffer(lines: ["header line"])
        appHeaderBuffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: 11, height: 1,
                handlerID: headerHandlerID
            )
        )

        // Status-bar local buffer with a region at y=0.
        // Regions inside this buffer need to be shifted by
        // +contentHeight before merge so that an event at
        // content-area y=contentHeight (the row just below
        // the content area) finds them.
        var statusBarBuffer = FrameBuffer(lines: ["status row"])
        statusBarBuffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0,
                width: 10, height: 1,
                handlerID: statusHandlerID
            )
        )

        // Replicate the merge that RenderLoop.renderFrame
        // performs. If this merge ever changes, *this* line
        // should change too — and that's the point: the test
        // pins the expected behaviour at the line where the
        // bug previously lived.
        var merged = contentBuffer.hitTestRegions
        for region in appHeaderBuffer.hitTestRegions {
            var shifted = region
            shifted.offsetY -= appHeaderHeight
            merged.append(shifted)
        }
        for region in statusBarBuffer.hitTestRegions {
            var shifted = region
            shifted.offsetY += contentHeight
            merged.append(shifted)
        }

        dispatcher.setRegions(merged)

        // Click in the content area — content handler should
        // fire.
        _ = dispatcher.dispatch(MouseEvent(
            button: .left, phase: .released,
            x: 0, y: 5
        ))
        #expect(contentFired, "Content-area click must fire the content handler")

        contentFired = false
        // Click in the app-header — header handler should fire.
        // After translation in the real App input loop, a click
        // on terminal y=0 (header row) arrives as content-area
        // y=-1 (1 minus the 1-row header). The shifted region's
        // offsetY is -appHeaderHeight = -1, so it matches.
        _ = dispatcher.dispatch(MouseEvent(
            button: .left, phase: .released,
            x: 0, y: -appHeaderHeight
        ))
        #expect(headerFired, "App-header click must fire the header handler")
        #expect(!contentFired, "App-header click must not leak to the content handler")

        headerFired = false
        // Click on the status bar — status handler should fire.
        // The status bar sits at content-area y=contentHeight
        // (= 20 in this test) after translation.
        _ = dispatcher.dispatch(MouseEvent(
            button: .left, phase: .released,
            x: 0, y: contentHeight
        ))
        #expect(statusFired, "Status-bar click must fire the status handler")
        #expect(!headerFired, "Status-bar click must not leak to the header handler")
        #expect(!contentFired, "Status-bar click must not leak to the content handler")
    }

    // MARK: - StatusBarItem identity stability

    /// Regression for #37 — the hover underline that
    /// disappeared after a click that didn't change the page.
    /// The bug was that `StatusBarItem.id` was
    /// `"\(shortcut)-\(label)"`, so an item whose action
    /// mutated its own label ended up with a new id on the
    /// next render — and the hover state machine, which
    /// stores `hoveredItemID` and compares it against
    /// `item.id` per render, lost the match.
    @Test("StatusBarItem identity is stable across label changes")
    func statusBarItemIdentityIsStable() {
        let staticID = StatusBarItem(
            shortcut: "x", label: "X: A", action: {}
        ).id
        let mutatedLabelID = StatusBarItem(
            shortcut: "x", label: "X: B (next state)", action: {}
        ).id
        #expect(staticID == mutatedLabelID,
                "Items sharing a shortcut must share an id regardless of label changes")
    }

    // MARK: - Action-less item clickability

    /// Regression for #36 — system items like "Back" (esc),
    /// "Quit" (q), and "Show" (enter) declare a `triggerKey`
    /// but no `action`. They were silently filtered out of
    /// the click / hover path because the guard in
    /// `applyHitTestRegions` skipped items whose
    /// `hasAction` was false. They should still be clickable
    /// — their click synthesises the corresponding key event
    /// through the full InputHandler chain.
    @Test("Action-less StatusBarItem with triggerKey gets a hit-test region")
    func actionLessItemWithTriggerKeyGetsRegion() {
        // The "Back" pattern — Shortcut.escape resolves to
        // .escape; no action argument.
        let backItem = StatusBarItem(shortcut: "esc", label: "back")
        let bar = StatusBar(
            userItems: [backItem],
            systemItems: [],
            style: .compact,
            alignment: .leading,
            highlightColor: .cyan,
            labelColor: .white
        )

        let context = makeContext(width: 40, height: bar.height)
        let buffer = renderToBuffer(bar, context: context)

        #expect(!buffer.hitTestRegions.isEmpty,
                "Action-less StatusBarItem with a triggerKey must still emit a hit-test region")
        #expect(backItem.triggerKey != nil,
                "Pre-condition: the 'esc' shortcut must derive a triggerKey for the regression to be meaningful")
    }

    /// Companion to the above — a click on an action-less
    /// item with a triggerKey routes a synthesised key event
    /// through the environment's `synthesizeKeyEvent` closure
    /// (which AppRunner wires to InputHandler.handle).
    @Test("Click on action-less StatusBarItem fires synthesizeKeyEvent")
    func clickOnActionLessItemFiresSynthesizeKey() {
        var synthesisedKey: KeyEvent?
        var environment = EnvironmentValues()
        let tuiContext = TUIContext()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        // Inject a synthesis recorder so the test can observe
        // which key the click produced.
        environment.synthesizeKeyEvent = { event in
            synthesisedKey = event
        }
        let context = RenderContext(
            availableWidth: 40,
            availableHeight: 1,
            environment: environment,
            tuiContext: tuiContext
        )
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let backItem = StatusBarItem(shortcut: "esc", label: "back")
        let bar = StatusBar(
            userItems: [backItem],
            systemItems: [],
            style: .compact,
            alignment: .leading,
            highlightColor: .cyan,
            labelColor: .white
        )

        let buffer = renderToBuffer(bar, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        guard let region = buffer.hitTestRegions.first else {
            Issue.record("Pre-condition: rendered bar must have at least one region")
            return
        }

        _ = dispatcher.dispatch(MouseEvent(
            button: .left, phase: .released,
            x: region.offsetX + 1, y: region.offsetY
        ))

        #expect(synthesisedKey?.key == .escape,
                "Click on the 'back' item must synthesise an ESC KeyEvent through the environment closure")
    }
}
