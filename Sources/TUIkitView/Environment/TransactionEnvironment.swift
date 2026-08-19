//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransactionEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

private struct TransactionKey: EnvironmentKey {
    static var defaultValue: Transaction { Transaction() }
}

extension EnvironmentValues {
    /// The transaction the change being rendered was made under.
    ///
    /// Published for the whole frame by the run loop, from whatever
    /// ``withAnimation(_:_:)`` scope the change was made in, and narrowed for a
    /// subtree by `View.transaction(_:)` / `View.animation(_:value:)`.
    ///
    /// Read it to find out whether the update being rendered is meant to be
    /// animated, and how. A view whose appearance is a function of an
    /// ``Animatable`` value does not need to: the framework interpolates that
    /// for it.
    public var transaction: Transaction {
        get { self[TransactionKey.self] }
        set { self[TransactionKey.self] = newValue }
    }
}
