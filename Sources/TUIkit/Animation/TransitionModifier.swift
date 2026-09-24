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
    /// contributes no child and changes no spacing, exactly as before. The
    /// present view is given that same address, so the claim finds it wherever
    /// the `if` stands: beside siblings, as a stack's only content, or under a
    /// modifier that reaches each member of what it wraps (`.frame`,
    /// `.opacity`, `.disabled`, `.padding`, `.background`). In a stack the
    /// same holds through structure that holds one view with nothing drawn
    /// around it — `if a { if b { X } }`, `if a { Group { X } }`, `if a { if c
    /// { X } else { Y } }` — whose `nil` asks that structure where it put the
    /// view.
    ///
    /// ## What still jumps
    ///
    /// The claim finds a departure only where the view carrying the transition
    /// rendered at exactly that address, so these removals still happen at
    /// once, as every removal inside a stack once did:
    ///
    /// - An `if` holding several views — two or more, a `ForEach`, a `Group`
    ///   of several — which have no one slot to keep; or one view behind a
    ///   modifier on the structure around it, `if a { Group { X }.padding() }`
    ///   or `.foregroundStyle(.red)` on that `Group`, whose member the `nil`
    ///   cannot find (and, padded, could not draw).
    /// - Where the optional is rendered directly — a view's whole `body`, or a
    ///   modifier's content such as `.overlay { if a { … } }` — a `Group` or an
    ///   `if`/`else` inside the `if`: `if a { Group { X } }`, `if a { if c { X }
    ///   else { Y } }`. Each draws its view a step below the optional's own
    ///   identity, where the `nil` does not look. In a stack both play, and a
    ///   nested `if` plays either way.
    /// - A transition with an identity step between it and the `if`: one on
    ///   the root of a `body` — a view of your own, or a modifier built as a
    ///   view with a body, such as `.tag` or `.zIndex` — rather than on the
    ///   view the `if` holds; one inside a presentation modifier (`.sheet`,
    ///   `.alert`, `.popover`, `.contextMenu`); or one with an `.id` outside
    ///   it — `X.transition(t).id(k)`, or `.id` written on the `if` itself.
    ///   `X.id(k).transition(t)` plays.
    /// - A transition with a modifier outside it in the `if`:
    ///   `X.transition(t).padding()`. The picture the removal would play is the
    ///   transition's alone, so drawing it would drop the padding and move the
    ///   view; it snaps instead. So does one inside a wrapper that draws
    ///   nothing of its own — `X.transition(t).foregroundStyle(.red)`,
    ///   `.onAppear { … }`, `AnyView(X.transition(t))` — whose picture would
    ///   have been right: the slot cannot yet tell the two kinds apart.
    ///   `X.padding().transition(t)` plays, padding and all — write the
    ///   transition last.
    /// - The branch an `if`/`else` leaves. The other branch takes the slot at
    ///   once, and nothing is left standing to play the removal.
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
