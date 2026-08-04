//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SubmitEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Submit action entry

/// One ``View/onSubmit(of:_:)`` registration cascading through the
/// environment: the triggers it responds to plus the action to run. It wraps a
/// plain (non-`Sendable`) closure; `@unchecked Sendable` is sound because the
/// action is only ever created and invoked on the render loop's single thread —
/// the same latitude every action closure in the framework relies on (Button,
/// `TextField.onSubmit`, …). This lets `submitActions` be a concurrency-safe
/// empty-array default.
struct SubmitActionEntry: @unchecked Sendable {
    let triggers: SubmitTriggers
    let action: () -> Void
}

// MARK: - Environment keys

/// The stack of `.onSubmit(of:_:)` actions in scope, outer-first (append order).
/// A text field runs the ones whose triggers match its role, inner-first.
private struct SubmitActionsKey: EnvironmentKey {
    static let defaultValue: [SubmitActionEntry] = []
}

/// Which submit trigger a field in this subtree represents — ``SubmitTriggers/text``
/// for a normal ``TextField`` / ``SecureField``, ``SubmitTriggers/search`` for the
/// `.searchable` query field. Selects which cascading actions the field consumes.
/// The KEY is private (internal plumbing), but the property is package-visible so
/// `SearchableModifier` can scope its query field to `.search`.
private struct SubmitTriggerRoleKey: EnvironmentKey {
    static let defaultValue: SubmitTriggers = .text
}

/// The most recent `.submitLabel(_:)` in scope. Stored for parity; a terminal has
/// no on-screen Return key to draw it on.
private struct SubmitLabelKey: EnvironmentKey {
    static let defaultValue: SubmitLabel? = nil
}

extension EnvironmentValues {
    /// The cascading `.onSubmit(of:_:)` actions in scope (outer-first). Read by
    /// text fields to assemble their effective submit action.
    var submitActions: [SubmitActionEntry] {
        get { self[SubmitActionsKey.self] }
        set { self[SubmitActionsKey.self] = newValue }
    }

    /// The submit trigger a field in this subtree represents (default ``SubmitTriggers/text``).
    var submitTriggerRole: SubmitTriggers {
        get { self[SubmitTriggerRoleKey.self] }
        set { self[SubmitTriggerRoleKey.self] = newValue }
    }

    /// The `.submitLabel(_:)` in scope, if any. Stored for source-compatibility;
    /// no on-screen Return key exists to render it.
    public var submitLabel: SubmitLabel? {
        get { self[SubmitLabelKey.self] }
        set { self[SubmitLabelKey.self] = newValue }
    }
}

// MARK: - Combined submit action

/// Assembles a text field's effective submit action from its own per-field
/// closure and the cascading `.onSubmit(of:_:)` actions that match `role`.
///
/// Order matches SwiftUI's accumulation: the most-specific action runs first —
/// the per-field ``TextField/onSubmit(_:)`` closure, then the cascading env
/// actions inner-first (i.e. reversed relative to the outer-first append order).
///
/// Returns `nil` when there is nothing to run, which is load-bearing: a
/// ``TextField`` with no submit action lets Return fall through to a dialog's
/// default button (see ``TextFieldHandler``), so a non-nil no-op would silently
/// break default buttons.
func combinedSubmitAction(
    perField: (() -> Void)?,
    cascading actions: [SubmitActionEntry],
    role: SubmitTriggers
) -> (() -> Void)? {
    let matching = actions.filter { !$0.triggers.isDisjoint(with: role) }
    guard perField != nil || !matching.isEmpty else { return nil }
    return {
        perField?()
        // Inner-first: the environment appends outer-first, so a descendant's
        // `.onSubmit` is later in the array and must fire before an ancestor's.
        for entry in matching.reversed() { entry.action() }
    }
}
