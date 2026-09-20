//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HelpModifier.swift
//
//  `help(_:)` — SwiftUI's tooltip, on a surface with no pointer to depend on.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Help Text Environment

/// EnvironmentKey for the help text in force for a subtree.
private struct HelpTextKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The help text a focusable control inside this subtree should claim as its
    /// own, or `nil`.
    ///
    /// This is how the FOCUS half of `help(_:)` reaches the control:
    /// ``View/help(_:)`` writes it for its content, and
    /// `FocusRegistration.register(context:handler:focusID:)` — which every
    /// focusable control funnels through — publishes it when that control holds
    /// the focus. The alternative was to read `\.isFocused` in the modifier,
    /// which does not work: `isFocused` is published INSIDE a control's own
    /// render, so `Button("Save") {}.help("…")` — the natural spelling, with the
    /// modifier outside — would never see it.
    ///
    /// Innermost wins, because this is an ordinary environment cascade.
    var helpText: String? {
        get { self[HelpTextKey.self] }
        set { self[HelpTextKey.self] = newValue }
    }
}

// MARK: - Help Modifier

/// Attaches help text to a view: SwiftUI's `help(_:)`.
///
/// The modifier does two separable things, because a terminal has two ways to
/// point at a view and neither covers the other:
///
/// - **Hover.** It establishes a hit region and publishes the text to
///   ``TooltipState`` on `.entered` / `.exited`, exactly as `.onHover` does —
///   which is also why `help(_:)` makes a plain `Text` hit-testable where it was
///   not. The tooltip appears once the pointer has rested for
///   ``EnvironmentValues/tooltipDelay``, and the delay needs a clock the
///   demand-driven run loop does not otherwise have, so the modifier schedules a
///   one-shot wake at the deadline.
/// - **Focus.** It writes `EnvironmentValues.helpText` for its content, and the
///   focused control claims it from there. Revealed by the help key rather than
///   automatically — see `TooltipState.keyboardRevealed`.
public struct HelpModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The localized help text.
    let text: String

    public var body: Never {
        fatalError("HelpModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension HelpModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var childContext = context
        childContext.environment.helpText = text
        var buffer = TUIkit.renderToBuffer(content, context: childContext)

        // `isEnabled` is NOT checked, unlike `.onHover`'s SwiftUI-parity gate:
        // SwiftUI shows a disabled control's help, and explaining why a control
        // is unavailable is most of what help text is for. The keyboard half
        // still cannot reach one, because a disabled control does not register
        // with the focus system and so has nothing to reveal.
        guard !context.isMeasuring,
            context.environment.tooltipTrigger != .never,
            let tooltips = context.environment.tooltipState,
            let dispatcher = context.environment.mouseEventDispatcher
        else {
            return buffer
        }

        // Hover needs the terminal's any-event motion mode, requested per frame
        // exactly as `.onHover` requests it.
        dispatcher.requestFeature(.motion, in: context)

        let captured = text
        let trigger = context.environment.tooltipTrigger
        let capturedStyle = trigger.presentation(context.environment.tooltipStyle)
        let capturedDelay = context.environment.tooltipDelay
        // The handler wants its own id, to hand a popover something to anchor
        // to — and cannot have it at the point the closure is formed. A box is
        // the smallest thing that closes the loop; the id is written before any
        // event can arrive, because events are dispatched between frames.
        let idBox = HandlerIDBox()
        // An OBSERVER, as `.onHover` is. This region goes on after the
        // content's, so as an ordinary region it took the `.entered` /
        // `.exited` the control it explains needs for its own hover face —
        // `Button("Save") {}.help("…")` never lit up under the pointer. See
        // `MouseEventDispatcher.registerHoverObserver(in:_:)`.
        let handlerID = dispatcher.registerHoverObserver(in: context) { event in
            switch event.phase {
            case .entered:
                // The event's own arrival time, not this frame's clock: the
                // pointer entered between frames, and measuring the rest from a
                // stale frame stamp would let a tooltip appear early by up to a
                // frame.
                tooltips.hovering(
                    captured, handlerID: idBox.id, nowNanos: FrameClock.nowNanos,
                    style: capturedStyle, delaySeconds: capturedDelay)
                return true
            case .exited:
                tooltips.leaving(captured)
                return true
            default:
                // Claim nothing else, so clicks and the wheel still reach
                // whatever is underneath — `help(_:)` must not make a view
                // swallow gestures it did not have before.
                return false
            }
        }
        idBox.id = handlerID
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID))

        // The popover presentation, attached HERE rather than by the run loop,
        // because the anchor is this buffer and an overlay's offsets are in its
        // own buffer's coordinates — carried and shifted as the buffer travels
        // up, exactly as a `Menu`'s drop-down is. The run loop has only the root
        // buffer and could not say where the control ended up.
        //
        // Identified by its TEXT, which is how `TooltipState.leaving` already
        // identifies a candidate: handler ids are per-frame, and the resolved
        // candidate's id belongs to the frame that published it. Two views with
        // identical help text would both draw a panel; they would also be
        // indistinguishable to a reader, and the cost is a duplicate rather than
        // a wrong answer.
        if trigger.showsEverything {
            // Every panel, unprompted and for as long as the subtree is on screen.
            // No candidate is consulted: this mode is not "which tooltip is
            // showing" but "all of them", so there is nothing to resolve and
            // nothing to wait for.
            TooltipPopover.attach(text: text, to: &buffer, context: context)
        } else if let showing = tooltips.resolved(nowNanos: context.environment.frameNowNanos),
            showing.style == .popover, showing.text == text
        {
            TooltipPopover.attach(text: text, to: &buffer, context: context)
        }

        // The delay expires between frames, and nothing else will redraw for it
        // — a still-held focus least of all. Declared every frame while either
        // slot is pending, and it stops as soon as the tooltip is showing or the
        // candidate goes away: one wake per hover or focus, not a poll.
        if let deadline = tooltips.pendingDeadlineNanos(
            nowNanos: context.environment.frameNowNanos)
        {
            let seconds = Double(deadline - context.environment.frameNowNanos) / 1_000_000_000
            context.requestWake(token: "tooltip-\(context.identity.path)", afterSeconds: seconds)
        }
        return buffer
    }
}

/// A mutable cell for a handler id a closure needs before it exists.
private final class HandlerIDBox {
    var id: HitTestRegion.HandlerID?
}

// MARK: - Layoutable

extension HelpModifier: Layoutable {
    /// Forwards measurement to the content — help text changes no layout. The
    /// child is measured with `helpText` set, so a control that reads it while
    /// measuring sees the same value it will render with.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var childContext = context
        childContext.environment.helpText = text
        return measureChild(content, proposal: proposal, context: childContext)
    }
}

// MARK: - View Extension

extension View {
    /// Adds help text to this view, shown as a tooltip.
    ///
    /// The text appears when the pointer rests on the view for
    /// `View.tooltipDelay(_:)`, or when the view holds the keyboard focus and
    /// the reader presses the help key (`?` by default). It is presented either
    /// as a row in the status bar or as a popover attached to the control — the
    /// app's choice, through `View.tooltipStyle(_:)`.
    ///
    /// `View.tooltips(_:)` chooses when: ``TooltipTrigger/onFocus`` drops the
    /// help key requirement, so moving the focus through a page explains it.
    ///
    /// ```swift
    /// Button("Rebuild") { rebuild() }
    ///     .help("Rebuild the index from scratch")
    /// ```
    ///
    /// > Note: `help(_:)` gives the view a hit region so the pointer can be
    /// > known to be over it. On a view that had none — a plain `Text` — that is
    /// > a small behavioural change to whatever sits underneath.
    ///
    /// - Parameter textKey: The key for the help text.
    public func help(_ textKey: LocalizedStringKey) -> some View {
        HelpModifier(content: self, text: textKey.localized)
    }

    /// Adds help text to this view, displayed as written.
    ///
    /// Generic over `StringProtocol`, which is both SwiftUI's own spelling and
    /// what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter text: The help text.
    public func help<S: StringProtocol>(_ text: S) -> some View {
        HelpModifier(content: self, text: String(text))
    }

    /// Adds help text to this view, from a `Text`.
    ///
    /// SwiftUI's third overload. Only the string is used: a tooltip is drawn in
    /// the chrome's own styling in both presentations, so a `Text`'s colour or
    /// weight has nowhere to land.
    ///
    /// - Parameter text: The help text.
    public func help(_ text: Text) -> some View {
        HelpModifier(content: self, text: text.content)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension HelpModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }
}
