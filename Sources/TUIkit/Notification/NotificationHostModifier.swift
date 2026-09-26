//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NotificationHostModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Notification Host Modifier

/// A modifier that renders all active notifications from the ``NotificationService``
/// as a stacked overlay.
///
/// Attach this modifier once at the root of your view tree. It reads the
/// active notification entries from the environment's ``NotificationService``,
/// renders each one as a bordered ``Box``, and stacks them vertically in the
/// top-right corner.
///
/// ## Example
///
/// ```swift
/// ContentView()
///     .notificationHost()
/// ```
///
/// The base content remains fully interactive — notifications do not dim
/// or block the background.
///
/// - SeeAlso: ``NotificationService``, ``View/notificationHost(width:)``
struct NotificationHostModifier<Content: View>: View {
    /// The base content to render.
    let content: Content

    /// The fixed width of each notification box in characters.
    let width: Int

    var body: Never {
        fatalError("NotificationHostModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension NotificationHostModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let baseBuffer = TUIkit.renderToBuffer(content, context: context)
        // Without an app there is no service, so there is nothing to show
        // over the content.
        guard let service = context.environment.notificationService else {
            return baseBuffer
        }
        // The service is a process-wide object that no memo keys on, and a post
        // writes nothing the render cache sees. So the read DECLARES itself
        // (`recordUnkeyedRead`), as a view sizing itself to the scroll viewport
        // does, and a memo above the host declines to keep a buffer drawn with
        // no toast in it: it served that buffer after `post`, and the toast
        // never appeared. Declared whether or not there are toasts, because
        // "none" is the answer a post invalidates. Where a host usually sits —
        // around the whole scene — there is no memo above it to decline.
        context.environment.volatileReadTracker?.recordUnkeyedRead()
        let activeEntries = service.activeEntries()

        guard !activeEntries.isEmpty else {
            return baseBuffer
        }

        // Start the animation timer if not already running.
        startAnimationTask(
            entries: activeEntries,
            service: service,
            lifecycle: context.environment.lifecycle!
        )

        // The frame's stamp, so every toast in one frame fades by one instant and a
        // re-walk of the frame draws the same picture. A one-off render has no stamp —
        // `nowNanos` is 0 outside the run loop — and reads the service's clock instead,
        // which is what the toast was posted on.
        let frame = context.environment.animationFrame
        let now = frame.canAnimate ? UInt64(bitPattern: frame.nowNanos) : service.nowNanos()
        let palette = context.environment.palette
        let horizontalPadding = 1
        let innerWidth = max(1, width - BorderRenderer.borderWidthOverhead)
        let textWidth = max(1, innerWidth - horizontalPadding * 2)
        let pad = String(repeating: " ", count: horizontalPadding)

        // Render each notification as a Box and stack them vertically.
        var stackedBuffer = FrameBuffer()
        for entry in activeEntries {
            let elapsed = entry.age(atNanos: now)
            let opacity = NotificationTiming.opacity(
                elapsed: elapsed,
                visibleDuration: entry.duration
            )

            let resolvedBorderColor = palette.border
            let fadedBorderColor = resolvedBorderColor.opacity(opacity, over: palette.background)
            let fgColor = Color.palette.foreground.resolve(with: palette)
                .opacity(opacity, over: palette.background)

            // Build content lines with horizontal padding, padded to full inner width
            // so the Box spans the intended width.
            let wrappedLines = NotificationTiming.wordWrap(entry.message, maxWidth: textWidth)
            var contentLines: [String] = []
            for line in wrappedLines {
                let styledLine = pad + ANSIRenderer.colorize(line, foreground: fgColor)
                contentLines.append(styledLine.padToVisibleWidth(innerWidth))
            }

            // Render a Box around the pre-styled lines. Box handles
            // Border style adapts to the current appearance automatically.
            let boxView = Box(lines: contentLines, color: fadedBorderColor)
            var boxContext = context
            boxContext.availableWidth = width
            let entryBuffer = TUIkit.renderToBuffer(boxView, context: boxContext)

            stackedBuffer.appendVertically(entryBuffer)
        }

        guard !baseBuffer.isEmpty, !stackedBuffer.isEmpty else {
            return baseBuffer
        }

        // Expand the base buffer to fullscreen so the notification stack
        // is positioned relative to the terminal, not the content size.
        // Crucially, carry over the base buffer's overlay layers and
        // hit-test regions — rebuilding `lines` from scratch would
        // otherwise drop them, and any interactive control underneath
        // the notification would silently stop responding to clicks
        // until the notification finished fading out.
        let screenWidth = context.availableWidth
        let screenHeight = context.availableHeight
        var fullscreenLines: [String] = []
        for row in 0..<screenHeight {
            if row < baseBuffer.lines.count {
                fullscreenLines.append(
                    baseBuffer.lines[row].padToVisibleWidth(screenWidth)
                )
            } else {
                fullscreenLines.append(String(repeating: " ", count: screenWidth))
            }
        }
        // The fullscreen padding doesn't move any content, so overlays
        // and hit-test regions carry across at the same coordinates.
        let fullscreenBuffer = baseBuffer.replacingLines(fullscreenLines)

        let offset = notificationOffset(
            stackSize: (stackedBuffer.width, stackedBuffer.height),
            screenSize: (screenWidth, screenHeight)
        )

        // As a LAYER at its declared level, not baked into the lines: a
        // pending presentation overlay in the base (a sheet or alert
        // presented anywhere inside the hosted content) composites at the
        // root AFTER these lines, and its dimming pass buried a baked-in
        // toast — stripped of its border colour, painted over by the centred
        // dialog. `.notification` is the topmost level by declaration; now it
        // actually composites there, fades intact (the stack's opacity
        // regions resolve when the layer lands).
        var result = fullscreenBuffer
        result.overlays.append(
            OverlayLayer(
                offsetX: offset.x, offsetY: offset.y,
                content: stackedBuffer, level: .notification))
        return result
    }
}

// MARK: - Layoutable

extension NotificationHostModifier: Layoutable {
    /// Notifications are transient overlays composited onto the page content
    /// (which spans the screen), so the layout footprint is the base `content`.
    /// Forwarding also keeps the animation-timer side-effect on the render pass.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Private Helpers

extension NotificationHostModifier {
    /// Calculates the screen offset for the notification stack (always top-right).
    ///
    /// - Parameters:
    ///   - stackSize: The width and height of the stacked notification buffer.
    ///   - screenSize: The available terminal width and height.
    /// - Returns: The (x, y) position to place the stack.
    fileprivate func notificationOffset(
        stackSize: (width: Int, height: Int),
        screenSize: (width: Int, height: Int)
    ) -> (x: Int, y: Int) {
        let xPosition = max(0, screenSize.width - stackSize.width - 1)
        return (xPosition, 1)
    }

    /// Starts a background task that triggers re-renders for fade animations
    /// and cleans up expired notifications.
    ///
    /// Uses a single shared token so only one animation task runs at a time.
    /// The task stops automatically when no notifications are active.
    fileprivate func startAnimationTask(
        entries: [NotificationEntry],
        service: NotificationService,
        lifecycle: LifecycleManager
    ) {
        let token = "notification-host-animation"

        // Recorded EVERY frame and started only on the first, which is not the
        // same thing as returning early once it has appeared. `recordAppear` is
        // the only writer of the manager's current-render token set, so a frame
        // that skipped it left the token missing at `endRenderPass`: the token
        // "disappeared", its appearance flag was cleared, and the next frame
        // re-entered here and called `startTask`, which cancels the task
        // already running. The cancelled sleep then threw, the loop broke, and
        // the epilogue asked for another render — so the toast pinned the app
        // at the frame-rate cap for its whole life, creating and cancelling a
        // task per frame, instead of the roughly thirty wakes its sleep
        // schedule computes. The same shape `TaskModifier` and `_ImageCore` use.
        let isFirstAppear = !lifecycle.hasAppeared(token: token)
        _ = lifecycle.recordAppear(token: token) {}
        guard isFirstAppear else { return }

        // The latest expiry across all entries, on the service's clock.
        let latestExpiry = entries.map(\.expiresAtNanos).max() ?? 0
        let nowNanos = service.nowNanos

        lifecycle.startTask(token: token, priority: .medium) { [lifecycle] in
            while !Task.isCancelled {
                let now = nowNanos()
                if now > latestExpiry {
                    break
                }
                // Sleep until an opacity actually moves, rather than 42 times a
                // second regardless. A notification is at a flat 1.0 for its
                // whole visible stretch — three seconds of the usual three and a
                // half — and every wake in there re-renders the entire screen to
                // draw exactly what is already on it.
                //
                // This cannot be an `AnimatedCellRun`, which is what everything
                // else on this path became: a run LOOPS, and a toast appears
                // once and vanishes. Its cells stop existing, which is a change
                // of layout rather than of appearance.
                let due = entries.map {
                    NotificationTiming.timeUntilOpacityChanges(
                        elapsed: $0.age(atNanos: now), visibleDuration: $0.duration)
                }.min() ?? 0
                // To an instant a 2-tick frame begins on the clock the frames are
                // stamped with, where a bar or a view animation on the same screen
                // changes too, rather than a fixed sleep from wherever this woke. The
                // clock is read again for the sleep, so the work above is not added on.
                let wake = UInt64(
                    clamping: NotificationTiming.nextWakeNanos(after: Int64(clamping: now), due: due))
                let current = nowNanos()
                try? await Task.sleep(nanoseconds: wake > current ? wake - current : 0)
                guard !Task.isCancelled else { break }
                AppState.shared.setNeedsRender()
            }

            // Only when the loop ran to its own end. A CANCELLED task is being
            // replaced, and its epilogue would clear the appearance flag the
            // replacement has just set — so the frame after that would start a
            // third task, cancelling the second, forever — and would ask for a
            // render on the way out.
            guard !Task.isCancelled else { return }
            // Final render to clear expired notifications.
            lifecycle.resetAppearance(token: token)
            AppState.shared.setNeedsRender()
        }
    }
}
