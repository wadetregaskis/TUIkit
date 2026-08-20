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
    /// ## Insertions everywhere, removals where a slot survives
    ///
    /// An **insertion** works wherever the view appears, because the view is
    /// there to be drawn.
    ///
    /// A **removal** needs somewhere to play out, and the view being removed is
    /// by definition no longer in the tree — so what plays it is whatever still
    /// stands where it stood. That works when the optional is itself the thing
    /// being rendered (a page's body, a modifier's content). It does **not**
    /// work for an `if` inside a stack: a stack asks its children to flatten
    /// themselves and a `nil` optional flattens to *no children at all*, so the
    /// instant the condition goes false there is nothing left holding the
    /// place. Such a view still animates in, and jumps out.
    ///
    /// Changing that means an optional keeping a slot of its own instead of
    /// flattening, which would move identities and stack spacing under every
    /// `if` in every existing app — a much larger change than this, and one to
    /// make on its own terms rather than as a side effect of transitions.
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

        // Leave the parting picture behind on every frame, so whatever holds
        // this slot can play it out if the next frame does not contain us.
        // Re-declared each frame because nothing else can report an absence —
        // see `DepartureStore`.
        if let leaving = animation ?? transition.explicitAnimation {
            let removal = transition.removal
            storage.departures.present(
                DepartureStore.Departure(
                    width: buffer.width, height: buffer.lines.count, animation: leaving,
                    render: { phase in
                        removal.apply(to: buffer, phase: phase, context: context)
                    }),
                at: context.identity)
        }

        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self),
            slot: StateIndex.phase)
        let phase = storage.animations.arrivalPhase(
            for: key, animation: animation,
            nowNanos: context.environment.frameNowNanos, isMeasuring: false)
        guard phase < 1 else { return buffer }

        // Arriving: the subtree's picture is a function of time, so a value
        // memo must not cache it.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        return transition.insertion.apply(to: buffer, phase: phase, context: context)
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
