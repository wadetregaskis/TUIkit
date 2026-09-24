//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusStateRegistrars.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// The one binding `.focused(_:)` / `.focused(_:equals:)` makes, shared by the
/// live render and by a value memo replaying it — see `EffectJournal`.
enum FocusBindingRegistrar {
    /// The journal kind of a `@FocusState` binding.
    static let kind = EffectJournal.Kind("focusBinding")

    /// Binds `value` of `store` to `focusID` on `context`'s manager.
    ///
    /// It looks the manager up in `context` rather than taking one, so a replay
    /// binds into the manager of the frame that serves it — and refuses the
    /// backdrop's, as the render does, so a replay is the call the render made.
    @MainActor
    static func register(store: String, value: AnyHashable, focusID: String, context: RenderContext) {
        guard let manager = context.environment.focusManager, !manager.isBackdrop else { return }
        manager.registerFocusBinding(store: store, value: value, focusID: focusID)
    }
}

/// The one declaration `.defaultFocus(_:_:priority:)` makes, shared by the live
/// render and by a value memo replaying it — see `EffectJournal`.
enum DefaultFocusRegistrar {
    /// The journal kind of a default-focus declaration.
    static let kind = EffectJournal.Kind("defaultFocus")

    /// Declares `value` as the default focus of `store` on `context`'s manager.
    ///
    /// It looks the manager up in `context` rather than taking one, so a replay
    /// declares into the manager of the frame that serves it — and refuses the
    /// same two throwaway managers the render refuses, so a replay is the call
    /// the render made rather than merely a similar one.
    @MainActor
    static func declare(
        value: AnyHashable, priority: DefaultFocusEvaluationPriority, store: String,
        context: RenderContext
    ) {
        guard let manager = context.environment.focusManager,
            !manager.isBackdrop, !manager.suppressesAutoFocus
        else { return }
        manager.setDefaultFocusValue(value, priority: priority, forStore: store)
    }
}
