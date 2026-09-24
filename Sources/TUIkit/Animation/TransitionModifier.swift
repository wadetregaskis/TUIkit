//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// How this view arrives when it is inserted, and how it leaves when it is
    /// removed.
    ///
    /// ```swift
    /// if showDetail {
    ///     Detail().transition(.move(edge: .top).combined(with: .opacity))
    /// }
    /// ```
    ///
    /// A transition runs only when the change that caused it was animated —
    /// inside ``withAnimation(_:_:)``, or under a ``View/animation(_:value:)``
    /// watching the condition. An unanimated appearance is still instant, which
    /// is what makes it safe to leave a transition on a view that appears for
    /// other reasons (a page being opened, a list being rebuilt).
    ///
    /// ## How a view that no longer exists still leaves
    ///
    /// An **insertion** works wherever the view appears, because the view is
    /// there to be drawn.
    ///
    /// A **removal** has no view: the body no longer produces one, and a
    /// terminal rebuilds its whole frame from the tree. What plays it is
    /// whatever still stands where it stood — the `nil` the optional became —
    /// drawing the picture the view left behind on its last frame. While that
    /// runs, the slot keeps the size the view had, so the stack around it does
    /// not close up until the removal has finished.
    ///
    /// This holds both where the optional is itself the thing being rendered (a
    /// page's body, a modifier's content) and for the far commoner `if` inside a
    /// stack. A stack asks its children to flatten themselves, and a `nil`
    /// flattens to no children at all; it makes the one exception for a `nil`
    /// something is still leaving from, and only for as long as that is true.
    ///
    /// The exception is claimed by address — the enclosing identity plus the
    /// wrapped view's type — so a `nil` in a tree that is animating nothing
    /// contributes no child and changes no spacing, exactly as before. The one
    /// shape still left out is a `nil` whose content would have flattened into
    /// *several* children, which has no single address to claim: those still
    /// jump.
    ///
    /// The picture a removal plays is the transitioning view's alone, so the
    /// transition has to be the view the `if` holds: `X.transition(t)`, or
    /// `X.padding().transition(t)`, which plays padding and all. Written
    /// before a modifier — `X.transition(t).padding()` — the transition's
    /// picture lacks the padding, and drawing it would move the view; that
    /// removal snaps instead. So, for now, does one before a modifier that
    /// draws nothing of its own, `X.transition(t).foregroundStyle(.red)`: the
    /// slot cannot tell the two kinds apart. Write the transition last.
    ///
    /// - Parameter transition: How to come and go.
    /// - Returns: A view that transitions.
    public func transition(_ transition: AnyTransition) -> some View {
        _TransitionView(content: self, transition: transition)
    }
}

/// Applies a transition to its content while the content is arriving, and
/// leaves behind what is needed to play it out when the content goes.
/// See ``View/transition(_:)``.
struct _TransitionView<Content: View>: View {
    let content: Content
    let transition: AnyTransition

    var body: Never {
        fatalError("_TransitionView renders via Renderable")
    }
}

/// Which of a transitioning view's animation-store slots is which.
private enum StateIndex {
    static let phase = 0
}

extension _TransitionView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIkitView.renderToBuffer(content, context: context)
        guard !context.isMeasuring, let storage = context.stateStorage else { return buffer }

        let animation =
            transition.explicitAnimation
            ?? (context.environment.canAnimate
                ? context.environment.transaction.effectiveAnimation : nil)

        // The departure re-declaration and the parting picture are per-frame
        // work no memo may skip: a cached buffer would starve the store of the
        // re-declaration (pruning the entry, so the removal snaps) and would
        // freeze the picture the removal plays.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self),
            slot: StateIndex.phase)
        let phase = storage.animations.arrivalPhase(
            for: key, animation: animation,
            nowNanos: context.environment.frameNowNanos, isMeasuring: false)

        // Leave the parting picture behind on EVERY frame, so whatever holds
        // this slot can play it out if the next frame does not contain us.
        // Re-declared each frame because nothing else can report an absence —
        // see `DepartureStore` — and unconditionally, because how the view
        // will leave cannot be known while it is present: that is decided by
        // the transaction of the change that removes it, which the slot host
        // hands to the store at removal time.
        //
        // The arrival phase is folded in. A view removed mid-insertion is
        // only PART present, and a departure recorded from the raw content
        // buffer started the removal from full presence — the first departing
        // frame popped a 30%-arrived view to 100%. Scaling the removal's
        // phase by how far the arrival had got keeps the picture continuous
        // for the (symmetric) common case, and monotonic for every case.
        let removal = transition.removal
        let arrival = min(1, max(0, phase))
        storage.departures.present(
            DepartureStore.Departure(
                viewType: Self.self, width: buffer.width, height: buffer.lines.count,
                explicitAnimation: transition.explicitAnimation,
                render: { departurePhase in
                    removal.apply(to: buffer, phase: departurePhase * arrival, context: context)
                        .slotBuffer()
                }),
            at: context.identity)

        // `!= 1`, not `< 1`: a spring goes PAST its target and comes back, and
        // above 1 is a picture (the view a cell beyond where it lands) rather
        // than a rounding artefact — see ``AnyTransition/Effect/apply(to:phase:context:)``.
        // Exactly 1 is the settled value the store returns for a finished or
        // unanimated arrival, so the fast path still catches every idle frame.
        guard phase != 1 else { return buffer }
        return transition.insertion.apply(to: buffer, phase: phase, context: context).slotBuffer()
    }
}

extension _TransitionView: Layoutable {
    /// A transition never changes the size of its slot — see ``AnyTransition``
    /// on why the effects are applied to the buffer rather than to layout — so
    /// this measures exactly as its content.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _TransitionView: SingleContentWrapper {
    var wrappedContent: Content { content }
}
