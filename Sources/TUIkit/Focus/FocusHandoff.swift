//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusHandoff.swift
//
//  `.focusHandoff(_:_:)`: where a control's focus goes when it holds the focus
//  and can no longer hold it. TUIkit-only; SwiftUI has nothing that says where
//  focus goes when its control is disabled, hidden or removed.
//
//  The modifier offers a declaration to the first focusable below it, the way
//  `.focused(_:equals:)` offers a focus id (`AssignedFocusID`), and
//  `FocusRegistration.register` hands the claimed declaration to the focus
//  manager. What the manager does with it is `FocusManagerRecovery.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Modifier

extension View {
    /// Names where this control's focus goes when it holds the focus and stops
    /// being able to: it was disabled, hidden, or removed from the tree.
    ///
    /// Without it the focus goes to the control's neighbour in the focus ring (the
    /// next focusable control, else the previous one). That is right for most
    /// controls and wrong for a pair that mirror each other. A row of `◀ ▶`
    /// buttons that move a selection wants ▶, disabled at the end, to hand the
    /// focus to ◀ on its left, and ◀, disabled at the start, to hand it to ▶ on
    /// its right. No rule based on position alone gives both:
    ///
    /// ```swift
    /// enum Move: Hashable { case left, right }
    /// @FocusState private var move: Move?
    ///
    /// HStack {
    ///     Button("◀") { selection -= 1 }
    ///         .disabled(selection == 0)
    ///         .focused($move, equals: .left)
    ///         .focusHandoff($move, .right)
    ///     Button("▶") { selection += 1 }
    ///         .disabled(selection == last)
    ///         .focused($move, equals: .right)
    ///         .focusHandoff($move, .left)
    /// }
    /// ```
    ///
    /// It applies only when the control loses the ability to hold the focus,
    /// however that happens: its own action disabling it, or a change elsewhere
    /// (another control, a binding) that disabled, hid or removed it. Moves the
    /// user or the app chose (Tab, the arrow keys, a click, a `@FocusState`
    /// write) are never redirected.
    ///
    /// When the target can't take the focus either (it is disabled, or not in
    /// the tree), the focus follows the TARGET's own handoff, and so on, stopping
    /// at the first control that can take it. A chain that comes back to a
    /// control it already passed through (◀ and ▶ above, both disabled) stops
    /// there, and the focus goes to the original control's neighbour. A
    /// ``View/defaultFocus(_:_:priority:)`` that still wants the focus wins over
    /// any handoff. A target in another focus section moves the focus there,
    /// except out of a modal. See <doc:FocusSystem>.
    ///
    /// Like `focused(_:equals:)`, it names ONE control: the first focusable view
    /// below it. It names its target by `@FocusState` value because a control's
    /// focus id comes from its place in the tree, which an app cannot spell.
    ///
    /// - Parameters:
    ///   - binding: The `@FocusState` the target is bound to with
    ///     `focused(_:equals:)`.
    ///   - value: The value the target is bound to.
    /// - Returns: A view that hands its focus to the control bound to `value` when
    ///   it can no longer hold it.
    public func focusHandoff<Value: Hashable>(
        _ binding: FocusState<Value>.Binding, _ value: Value
    ) -> some View {
        _FocusHandoffModifier(content: self, store: binding.store, value: value)
    }
}

// MARK: - Offer

/// A `.focusHandoff(_:_:)` declaration on offer to the first focusable below the
/// modifier, and which focusable took it: claimed by identity, exactly as
/// ``AssignedFocusID`` is, so a handoff written on a container names one control.
///
/// Holds the store rather than its id, because a `@FocusState`'s id is empty until
/// its view binds its render identity. Read at the claim, which happens while the
/// control registers, after the owning view's body has run.
///
/// Unchecked because it lives in the environment and is only touched on the render
/// path, which is main-actor isolated — the same rationale as ``AssignedFocusID``.
final class FocusHandoffOffer: @unchecked Sendable {
    /// The store's id, read when claimed.
    private let storeID: () -> String

    /// The value the target is bound to.
    private let value: AnyHashable

    /// Whose it is. `nil` until the first focusable registers below the modifier.
    private var claimant: ViewIdentity?

    init<Value: Hashable>(store: FocusStateStore<Value>, value: Value) {
        storeID = { store.storeID }
        self.value = AnyHashable(value)
    }

    /// The declaration if `identity` may make it — because nothing has claimed it
    /// yet (in which case it now has), or because this identity already did. `nil`
    /// for every other focusable in the subtree.
    ///
    /// Render pass only, like ``AssignedFocusID/claim(_:)``: its one caller,
    /// `FocusRegistration.register`, returns on a measure pass first.
    func claim(_ identity: ViewIdentity) -> (store: String, value: AnyHashable)? {
        if let claimant, claimant != identity { return nil }
        claimant = identity
        return (storeID(), value)
    }
}

private struct FocusHandoffOfferKey: EnvironmentKey {
    static let defaultValue: FocusHandoffOffer? = nil
}

extension EnvironmentValues {
    /// The handoff offered to the first focusable in the subtree, set by
    /// `.focusHandoff(_:_:)` and claimed through ``FocusRegistration``.
    var focusHandoffOffer: FocusHandoffOffer? {
        get { self[FocusHandoffOfferKey.self] }
        set { self[FocusHandoffOfferKey.self] = newValue }
    }
}

/// Puts a fresh ``FocusHandoffOffer`` in the environment on every render.
///
/// Unlike `_FocusedModifier`, it never wires the store's focus manager, so a
/// dimmed backdrop's throwaway manager needs no special case: the offer is
/// claimed there, recorded on the throwaway, and discarded with it.
struct _FocusHandoffModifier<Content: View, Value: Hashable>: View {
    let content: Content
    let store: FocusStateStore<Value>
    let value: Value

    var body: some View { content }
}

extension _FocusHandoffModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A fresh offer per render: the claim is this render's, so the same
        // control takes it again next frame rather than the offer staying spent.
        let offer = FocusHandoffOffer(store: store, value: value)
        let env = context.environment.setting(\.focusHandoffOffer, to: offer)
        return TUIkitView.renderToBuffer(content, context: context.withEnvironment(env))
    }
}

extension _FocusHandoffModifier: Layoutable {
    /// Measures as its content, with no offer: a measure pass registers nothing,
    /// so nothing would claim it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _FocusHandoffModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension _FocusHandoffModifier: DrawsContentUnchanged {}
