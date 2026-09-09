//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusStateRecords.swift
//
//  What the focus manager remembers about the `@FocusState` half: which control
//  a bound value names, and which value a `.defaultFocus(_:_:)` asked for. The
//  maps themselves stay private in `Focus.swift`, beside the code that keeps
//  them — as `FocusManagerSubtreeJump.swift` does for its own nested type.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {

    /// One `.focused(_:equals:)` control: the focus id it registered with, and
    /// the render generation it was last registered in (for per-frame pruning).
    struct FocusBinding {
        let focusID: String
        var generation: UInt64
    }

    /// One `.defaultFocus(_:_:)` declaration.
    struct DefaultFocusDeclaration {
        let value: AnyHashable
        let priority: DefaultFocusEvaluationPriority
        /// When this declaration was FIRST made, so two live defaults have a
        /// defined order. Kept across frames for a store that re-declares, so
        /// the order is the tree's and not the frame's.
        let sequence: UInt64
        var generation: UInt64

        /// Which of two declarations is resolved first: `.userInitiated` before
        /// `.automatic` — that is what the priority means — and then the order
        /// they were declared in, so of two ordinary defaults the one earlier in
        /// the tree wins. Any total order would make the outcome reproducible;
        /// this one also makes it explainable.
        static func precedes(
            _ lhs: (key: String, value: Self), _ rhs: (key: String, value: Self)
        ) -> Bool {
            if (lhs.value.priority == .userInitiated) != (rhs.value.priority == .userInitiated) {
                return lhs.value.priority == .userInitiated
            }
            return lhs.value.sequence < rhs.value.sequence
        }
    }
}
