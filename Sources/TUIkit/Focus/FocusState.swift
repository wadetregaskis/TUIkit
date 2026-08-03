//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusState.swift
//
//  SwiftUI-shaped declarative focus: the `@FocusState` property wrapper plus
//  the `.focused(_:)` / `.focused(_:equals:)` / `.defaultFocus(_:_:)` modifiers.
//
//  The value a `@FocusState` reflects is DERIVED from the persistent
//  `FocusManager`, not stored in the view: a `@FocusState` reads "which of my
//  bound controls currently holds focus?" and writing it moves focus. The
//  per-value → focusID mappings therefore live on the manager (which outlives
//  any frame's view structs), keyed by a stable store id the wrapper is handed
//  at render time (see `RenderIdentityBindable`). A `.focused(_:equals:)`
//  modifier forces its child's focusID (via `assignedFocusID`, consumed by
//  `FocusRegistration`) so both directions agree on the same id.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Forced focusID environment

/// A focusID `.focused(_:equals:)` is offering, and which focusable has taken
/// it — ONE of them, not all of them.
///
/// The id used to go into the environment as a bare `String?`, which every
/// focusable below resolved for itself: `HStack { TextField; TextField }
/// .focused($field, equals: .credentials)` gave both fields the same id,
/// `FocusSection.register` silently dropped the duplicate, and the second field
/// became unreachable by Tab, arrows and pending-focus routing while both drew
/// the focused affordance and a blinking cursor. SwiftUI's modifier names ONE
/// focusable; this makes that true here — the first one to ask takes the id and
/// the rest fall back to their own.
///
/// Claiming is by identity and idempotent, so a control that resolves its
/// focusID more than once in a pass keeps the id it took the first time rather
/// than losing it to itself.
/// Unchecked because it lives in the environment and is only ever touched on
/// the render path, which is main-actor isolated — the same rationale as
/// ``VolatileReadTracker``.
final class AssignedFocusID: @unchecked Sendable {
    /// The id `.focused(_:equals:)` forces on its target.
    let id: String

    /// Whose it is. `nil` until the first focusable renders below the modifier.
    private var claimant: ViewIdentity?

    init(id: String) {
        self.id = id
    }

    /// The forced id if `identity` may use it — because nothing has taken it
    /// yet (in which case it now has), or because this identity already did.
    /// `nil` for every other focusable in the subtree.
    ///
    /// Render pass only. A measure pass must not claim: measuring is not
    /// presence (a candidate the layout later discards would otherwise take the
    /// id from the control that is actually drawn), and a measuring control
    /// resolves its persisted id anyway — which IS this id, for the claimant.
    func claim(_ identity: ViewIdentity) -> String? {
        guard let claimant else {
            claimant = identity
            return id
        }
        return claimant == identity ? id : nil
    }
}

private struct AssignedFocusIDKey: EnvironmentKey {
    static let defaultValue: AssignedFocusID? = nil
}

extension EnvironmentValues {
    /// The focusID offered to the first focusable in the subtree, set by
    /// `.focused(_:equals:)` and claimed through ``FocusRegistration`` so the
    /// `@FocusState`-bound control — and only it — adopts the id the binding
    /// expects.
    var assignedFocusID: AssignedFocusID? {
        get { self[AssignedFocusIDKey.self] }
        set { self[AssignedFocusIDKey.self] = newValue }
    }
}

// MARK: - Store

/// Reference-typed backing shared by a `@FocusState` and the
/// `.focused` / `.defaultFocus` modifiers bound to it (they capture it through
/// the projected ``FocusState/Binding``). Holds the stable `storeID` and the
/// `emptyValue` (the value meaning "nothing focused" — `false` for a `Bool`
/// binding, `nil` for an optional one); the value↔focusID mappings themselves
/// live on the ``FocusManager``.
public final class FocusStateStore<Value: Hashable> {
    /// Stable id derived from the owning view's render identity (set in
    /// ``FocusState/bindRenderIdentity(path:propertyIndex:)``). Empty until
    /// bound — a `@FocusState` never read or written before its view renders.
    var storeID: String = ""

    /// The value meaning "nothing focused".
    let emptyValue: Value

    /// The focus manager, wired by the `.focused` / `.defaultFocus` modifiers as
    /// they render, so event closures (which run with no environment) can still
    /// reach it.
    weak var focusManager: FocusManager?

    init(emptyValue: Value) {
        self.emptyValue = emptyValue
    }

    /// The manager to use: the render-wired one, or the active render
    /// environment's (so a read at body-top works before any modifier wired it).
    private var resolvedManager: FocusManager? {
        focusManager ?? StateRegistration.activeEnvironment?.focusManager
    }

    /// The value whose bound control currently holds focus, or ``emptyValue``.
    var currentValue: Value {
        guard let erased = resolvedManager?.focusedValue(forStore: storeID),
            let value = erased as? Value
        else { return emptyValue }
        return value
    }

    /// Moves focus to the control bound to `newValue`, or relinquishes it when
    /// `newValue` is ``emptyValue``.
    func setValue(_ newValue: Value) {
        let erased: AnyHashable? = newValue == emptyValue ? nil : AnyHashable(newValue)
        resolvedManager?.setFocusValue(erased, forStore: storeID)
    }
}

// MARK: - @FocusState

/// A property wrapper that binds a view's state to whether a specific control
/// has keyboard focus.
///
/// Mirrors SwiftUI's `@FocusState`. Declare it as a `Bool` to track one
/// control, or as an optional `Hashable` to track which of several controls is
/// focused; bind controls with `.focused(_:)` / `.focused(_:equals:)`, and set
/// the initial focus with `.defaultFocus(_:_:)`.
///
/// ```swift
/// enum Field { case name, email }
///
/// struct SignUp: View {
///     @FocusState private var focus: Field?
///     var body: some View {
///         VStack {
///             TextField("Name", text: $name).focused($focus, equals: .name)
///             TextField("Email", text: $email).focused($focus, equals: .email)
///         }
///         .defaultFocus($focus, .name)
///     }
/// }
/// ```
@propertyWrapper
public struct FocusState<Value: Hashable>: RenderIdentityBindable {
    /// The shared backing.
    let store: FocusStateStore<Value>

    /// The focused value — which bound control holds focus (or the empty
    /// value). Setting it moves focus.
    public var wrappedValue: Value {
        get { store.currentValue }
        nonmutating set { store.setValue(newValue) }
    }

    /// The binding passed to `.focused(_:)` / `.focused(_:equals:)` /
    /// `.defaultFocus(_:_:)`.
    public var projectedValue: Binding {
        // Cache the manager at body time (`$field` is projected while the active
        // environment is published) so an event closure capturing this binding
        // can still move focus even if the bound control did not render this
        // frame (windowed out) and so never wired the store itself.
        if store.focusManager == nil {
            store.focusManager = StateRegistration.activeEnvironment?.focusManager
        }
        return Binding(store: store)
    }

    /// Creates a `Bool` focus state (default `false` — not focused).
    public init() where Value == Bool {
        store = FocusStateStore(emptyValue: false)
    }

    /// Creates an optional focus state (default `nil` — nothing focused).
    public init<T>() where Value == T?, T: Hashable {
        store = FocusStateStore(emptyValue: nil)
    }

    public func bindRenderIdentity(path: String, propertyIndex: Int) {
        store.storeID = "focusstate::\(path)::\(propertyIndex)"
    }

    /// The projected value of a ``FocusState`` — a handle the focus modifiers
    /// bind a control to.
    public struct Binding {
        let store: FocusStateStore<Value>

        /// The focused value (same as the wrapper's `wrappedValue`).
        public var wrappedValue: Value {
            get { store.currentValue }
            nonmutating set { store.setValue(newValue) }
        }
    }
}

// MARK: - Modifiers

extension View {
    /// Binds this view's focus to a `Bool` `@FocusState`: it reads `true` while
    /// this view is focused, and setting it to `true`/`false` focuses/unfocuses
    /// the view.
    public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        _FocusedModifier(content: self, store: condition.store, value: true)
    }

    /// Binds this view's focus to a `@FocusState` for a specific `value`: the
    /// state takes `value` while this view is focused, and setting the state to
    /// `value` focuses this view.
    public func focused<Value: Hashable>(
        _ binding: FocusState<Value>.Binding, equals value: Value
    ) -> some View {
        _FocusedModifier(content: self, store: binding.store, value: value)
    }

    /// Sets the value a `@FocusState` should take when its focus scope first
    /// appears — the control bound to `value` receives the initial focus,
    /// overriding the automatic "first focusable" choice.
    ///
    /// With the default `.automatic` priority this is applied once and then the
    /// user controls focus; `.userInitiated` re-applies it every render, even
    /// after the user has moved focus.
    public func defaultFocus<Value: Hashable>(
        _ binding: FocusState<Value>.Binding, _ value: Value,
        priority: DefaultFocusEvaluationPriority = .automatic
    ) -> some View {
        _DefaultFocusModifier(
            content: self, store: binding.store, value: value, priority: priority)
    }
}

/// How aggressively `.defaultFocus(_:_:priority:)` claims focus. Mirrors
/// SwiftUI's `DefaultFocusEvaluationPriority`.
public enum DefaultFocusEvaluationPriority: Sendable {
    /// Set the initial focus once, then leave the user in control (default).
    case automatic
    /// Re-assert the focus on every render, overriding the user's moves.
    case userInitiated
}

/// Forces the wrapped control's focusID (via ``EnvironmentValues/assignedFocusID``)
/// and registers the value↔focusID binding on the ``FocusManager`` each render.
struct _FocusedModifier<Content: View, Value: Hashable>: View {
    let content: Content
    let store: FocusStateStore<Value>
    let value: Value

    var body: some View { content }

    /// The forced id — stable across frames (structural identity of this
    /// modifier), distinct per `.focused` usage.
    fileprivate func forcedID(_ context: RenderContext) -> String {
        "focused-\(context.identity.path)"
    }
}

extension _FocusedModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let id = forcedID(context)
        // NOT under a dimmed backdrop. That render uses a throwaway
        // FocusManager, and `store.focusManager` is weak — so wiring it there
        // pointed the page's `@FocusState` at an object that dies with the
        // frame. Every subsequent write (a modal button's action setting
        // `focus = .email` to direct focus after dismissal) then resolved a nil
        // manager and silently did nothing: the store is what event closures
        // read, since the environment is out of reach outside a render.
        if !context.isMeasuring, let manager = context.environment.focusManager,
            !manager.isBackdrop
        {
            store.focusManager = manager
            manager.registerFocusBinding(
                store: store.storeID, value: AnyHashable(value), focusID: id)
        }
        // A fresh offer per render: the claim is this render's, so the same
        // control takes the id again next frame rather than the offer staying
        // spent.
        let env = context.environment.setting(\.assignedFocusID, to: AssignedFocusID(id: id))
        return TUIkitView.renderToBuffer(content, context: context.withEnvironment(env))
    }
}

extension _FocusedModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let env = context.environment.setting(
            \.assignedFocusID, to: AssignedFocusID(id: forcedID(context)))
        return measureChild(content, proposal: proposal, context: context.withEnvironment(env))
    }
}

/// Declares a store's initial-focus value on the ``FocusManager``; the actual
/// move happens at `endRenderPass`, once the target's `.focused` binding has
/// registered this frame (so there is no first-frame focus flash).
struct _DefaultFocusModifier<Content: View, Value: Hashable>: View {
    let content: Content
    let store: FocusStateStore<Value>
    let value: Value
    let priority: DefaultFocusEvaluationPriority

    var body: some View { content }
}

extension _DefaultFocusModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Backdrop-excluded for the same reason as `_FocusedModifier`: the
        // throwaway manager must not become the store's, and a default-focus
        // declaration made against it is discarded with it anyway.
        if !context.isMeasuring, let manager = context.environment.focusManager,
            !manager.isBackdrop
        {
            store.focusManager = manager
            manager.setDefaultFocusValue(
                AnyHashable(value), priority: priority, forStore: store.storeID)
        }
        return TUIkitView.renderToBuffer(content, context: context)
    }
}

extension _DefaultFocusModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
