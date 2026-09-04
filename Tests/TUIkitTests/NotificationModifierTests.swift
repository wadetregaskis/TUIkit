//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NotificationModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Notification Tests", .serialized)
struct NotificationTests {

    /// Creates a test context with a fresh TUIContext.
    private func testContext(
        width: Int = 80,
        height: Int = 24,
        identity: ViewIdentity = ViewIdentity(path: "Root")
    ) -> RenderContext {
        RenderContext(
            availableWidth: width,
            availableHeight: height,
            tuiContext: TUIContext(),
            identity: identity
        ).isolatingRenderCache()
    }

    // MARK: - Fade Timing

    @Test("Opacity is 0 at elapsed 0")
    func opacityAtStart() {
        let opacity = NotificationTiming.opacity(elapsed: 0.0, visibleDuration: 3.0)
        #expect(opacity == 0.0)
    }

    @Test("Opacity ramps to 1.0 at end of fade-in")
    func opacityAfterFadeIn() {
        let fadeIn = NotificationTiming.fadeInDuration
        let opacity = NotificationTiming.opacity(elapsed: fadeIn, visibleDuration: 3.0)
        #expect(opacity == 1.0)
    }

    @Test("Opacity is 1.0 during visible phase")
    func opacityDuringVisible() {
        let fadeIn = NotificationTiming.fadeInDuration
        let opacity = NotificationTiming.opacity(elapsed: fadeIn + 1.5, visibleDuration: 3.0)
        #expect(opacity == 1.0)
    }

    @Test("Opacity drops during fade-out phase")
    func opacityDuringFadeOut() {
        let fadeIn = NotificationTiming.fadeInDuration
        let visible = 3.0
        let halfFadeOut = NotificationTiming.fadeOutDuration / 2
        let opacity = NotificationTiming.opacity(elapsed: fadeIn + visible + halfFadeOut, visibleDuration: visible)
        #expect(opacity > 0.0)
        #expect(opacity < 1.0)
    }

    @Test("Opacity is 0 after full animation completes")
    func opacityAfterDismiss() {
        let total = NotificationTiming.fadeInDuration + 3.0 + NotificationTiming.fadeOutDuration + 0.1
        let opacity = NotificationTiming.opacity(elapsed: total, visibleDuration: 3.0)
        #expect(opacity == 0.0)
    }

    @Test("Fade-in is a linear ramp from 0 to 1")
    func fadeInIsLinear() {
        let fadeIn = NotificationTiming.fadeInDuration
        let quarter = NotificationTiming.opacity(elapsed: fadeIn * 0.25, visibleDuration: 3.0)
        let half = NotificationTiming.opacity(elapsed: fadeIn * 0.5, visibleDuration: 3.0)
        let threeQuarter = NotificationTiming.opacity(elapsed: fadeIn * 0.75, visibleDuration: 3.0)

        #expect(quarter > 0.0)
        #expect(half > quarter)
        #expect(threeQuarter > half)
        #expect(threeQuarter < 1.0)
        #expect(abs(half - 0.5) < 0.01)
    }

    // MARK: - Word Wrap

    @Test("Short text stays on one line")
    func wordWrapShortText() {
        let lines = NotificationTiming.wordWrap("Hello world", maxWidth: 40)
        #expect(lines == ["Hello world"])
    }

    @Test("Long text wraps at word boundaries")
    func wordWrapLongText() {
        let text = "This is a longer message that should wrap across multiple lines"
        let lines = NotificationTiming.wordWrap(text, maxWidth: 20)
        #expect(lines.count > 1)
        for line in lines {
            #expect(line.count <= 20)
        }
    }

    @Test("Single word longer than maxWidth gets its own line")
    func wordWrapLongWord() {
        let lines = NotificationTiming.wordWrap("Supercalifragilistic", maxWidth: 10)
        #expect(lines == ["Supercalifragilistic"])
    }

    @Test("Empty text returns single empty line")
    func wordWrapEmpty() {
        let lines = NotificationTiming.wordWrap("", maxWidth: 40)
        #expect(lines == [""])
    }

    @Test("CJK text wraps at correct terminal width boundary")
    func wordWrapCJKText() {
        // "你好 世界" = "你好" (4 cells) + space + "世界" (4 cells) = 9 cells
        // With maxWidth 6, "你好 世界" won't fit on one line (9 > 6)
        // but each word alone fits (4 <= 6), so should wrap to 2 lines
        let lines = NotificationTiming.wordWrap("你好 世界", maxWidth: 6)
        #expect(lines.count == 2, "CJK text should wrap to 2 lines at width 6, got \(lines.count)")
        #expect(lines[0] == "你好")
        #expect(lines[1] == "世界")
    }

    // MARK: - NotificationService

    @Test("Post adds an entry to the service")
    func postAddsEntry() {
        let service = NotificationService()
        service.post("Hello")

        let entries = service.activeEntries()
        #expect(entries.count == 1)
        #expect(entries[0].message == "Hello")
    }

    @Test("Multiple posts stack entries in order")
    func multiplePostsStack() {
        let service = NotificationService()
        service.post("First")
        service.post("Second")
        service.post("Third")

        let entries = service.activeEntries()
        #expect(entries.count == 3)
        #expect(entries[0].message == "First")
        #expect(entries[1].message == "Second")
        #expect(entries[2].message == "Third")
    }

    @Test("Clear removes all entries")
    func clearRemovesAll() {
        let service = NotificationService()
        service.post("One")
        service.post("Two")
        service.clear()

        let entries = service.activeEntries()
        #expect(entries.isEmpty)
    }

    @Test("Expired entries are pruned by activeEntries")
    func expiredEntriesPruned() {
        let service = NotificationService()
        // Post with a very short duration so it expires almost immediately.
        service.post("Quick", duration: 0.0)

        // Wait slightly longer than fade-in + fade-out.
        Thread.sleep(forTimeInterval: NotificationTiming.fadeInDuration + NotificationTiming.fadeOutDuration + 0.05)

        let entries = service.activeEntries()
        #expect(entries.isEmpty)
    }

    // MARK: - NotificationHostModifier Rendering

    @Test("Host renders base content when no notifications are active")
    func hostRendersBaseWhenEmpty() {
        let context = testContext()
        let service = NotificationService()
        var env = context.environment
        env.notificationService = service

        let view = NotificationHostModifier(
            content: Text("Base"),
            width: 40
        )

        let buffer = renderToBuffer(view, context: context.withEnvironment(env))
        #expect(buffer.lines[0].stripped == "Base")
        #expect(buffer.height == 1)
    }

    @Test("Host renders notification overlay when entries exist")
    func hostRendersNotification() {
        let context = testContext()
        let service = NotificationService()
        service.post("Alert!")
        var env = context.environment
        env.notificationService = service

        let view = NotificationHostModifier(
            content: Text("Base"),
            width: 40
        )

        // The toast is a LAYER at .notification — the topmost level — not
        // baked into the lines: baked in, a modal's dimming pass at the root
        // buried it. The text shows once the root composites.
        let buffer = renderToBuffer(view, context: context.withEnvironment(env))
        #expect(buffer.overlays.contains { $0.level == .notification })
        let screen = buffer.compositingOverlays(
            maxWidth: 40, maxHeight: 24, palette: context.environment.palette)
        #expect(screen.lines.joined().contains("Alert!"))
    }

    @Test(".notificationHost() modifier compiles and renders correctly")
    func modifierExtension() {
        let context = testContext()
        let service = NotificationService()
        service.post("Done!")
        var env = context.environment
        env.notificationService = service

        let view = Text("Content").notificationHost()

        let buffer = renderToBuffer(view, context: context.withEnvironment(env))
        let screen = buffer.compositingOverlays(
            maxWidth: 40, maxHeight: 24, palette: context.environment.palette)
        #expect(screen.lines.joined().contains("Done!"))
    }

    /// The host's animation task is keyed on a fixed lifecycle token, and a
    /// token is only "still here" while something re-records it every frame.
    @Test("The animation token is re-recorded every frame, not just the first")
    func animationTokenSurvivesLaterFrames() {
        // `firesEffects: false` keeps the bookkeeping and suppresses the actual
        // task, so this asserts the token lifecycle and nothing timing-bound.
        let lifecycle = LifecycleManager(firesEffects: false)
        let tuiContext = TUIContext(
            lifecycle: lifecycle, keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage())
        let service = NotificationService()
        service.post("Toast")

        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        env.notificationService = service
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tuiContext)

        for frame in 1...3 {
            lifecycle.beginRenderPass()
            _ = renderToBuffer(Text("Base").notificationHost(), context: context)
            lifecycle.endRenderPass()
            #expect(
                lifecycle.hasAppeared(token: "notification-host-animation"),
                "frame \(frame) let the animation token disappear, cancelling the task")
        }
    }

    @Test("Multiple notifications stack vertically")
    func multipleNotificationsStack() {
        let context = testContext(width: 80, height: 24)
        let service = NotificationService()
        service.post("First")
        service.post("Second")
        var env = context.environment
        env.notificationService = service

        let view = Text("Base").notificationHost()

        let buffer = renderToBuffer(view, context: context.withEnvironment(env))
        let screen = buffer.compositingOverlays(
            maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
        let joined = screen.lines.joined()
        #expect(joined.contains("First"))
        #expect(joined.contains("Second"))
        // Both notifications should be on screen, stacked.
        #expect(screen.height > 3)
    }
}

/// The stacking the levels declare, proven at the root composite.
@MainActor
@Suite("Overlay level stacking")
struct OverlayLevelStackingTests {

    private func screen(_ overlays: [OverlayLayer]) -> String {
        var base = FrameBuffer(lines: Array(repeating: String(repeating: " ", count: 30), count: 9))
        base.overlays = overlays
        let context = makeRenderContext(width: 30, height: 9)
        return base.compositingOverlays(
            maxWidth: 30, maxHeight: 9, palette: context.environment.palette
        ).lines.joined()
    }

    @Test("An alert composites above a sheet, whichever presented first")
    func alertAboveSheet() {
        // An alert is the topmost interruption in every windowing
        // convention. With the old ordering (.alert below .modal) an alert
        // presented beside a sheet drew UNDER it — owning the keyboard while
        // the sheet's dimming pass buried it: an invisible dialog holding
        // the app.
        let sheet = OverlayLayer(
            offsetX: 0, offsetY: 0, content: FrameBuffer(text: "SHEET-FACE"),
            level: .modal, centered: true, dimsBackground: true)
        let alert = OverlayLayer(
            offsetX: 0, offsetY: 0, content: FrameBuffer(text: "ALERT-FACE"),
            level: .alert, centered: true, dimsBackground: true)

        for layers in [[sheet, alert], [alert, sheet]] {
            let joined = screen(layers)
            #expect(joined.contains("ALERT-FACE"), "\(joined)")
            #expect(!joined.contains("SHEET-FACE"), "the alert must cover the sheet")
        }
    }

    @Test("A toast composites above a modal")
    func toastAboveModal() {
        let modal = OverlayLayer(
            offsetX: 0, offsetY: 0, content: FrameBuffer(text: "DIALOG"),
            level: .modal, centered: true, dimsBackground: true)
        let toast = OverlayLayer(
            offsetX: 20, offsetY: 0, content: FrameBuffer(text: "TOAST-TEXT"),
            level: .notification)
        let joined = screen([toast, modal])
        #expect(joined.contains("TOAST-TEXT"), "the toast must survive the modal's dimming pass")
        #expect(joined.contains("DIALOG"))
    }
}
