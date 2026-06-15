//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LazyPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Defers construction of `Content` until render time, giving each page its own
/// `@State` scope.
///
/// `@State` self-hydrates when a view is *constructed*, keyed by the active
/// hydration scope (the enclosing `body`) plus a declaration-order counter. A
/// `switch` that returns a different page per case constructs the active page
/// inside `ContentView`'s body, always at the same counter origin — so every
/// page's *first* `@State` would claim the same storage slot, its *second* the
/// next, and so on. Pages then alias each other's state (famously: text typed
/// into the SecureField page surfacing as the RadioButton page's selection),
/// because `ConditionalView` distinguishes branches only by the render-time
/// identity its content's already-hydrated `@State` never saw.
///
/// Wrapping each branch in `LazyPage` moves the page's construction into *this*
/// wrapper's `body`, which renders at the conditional branch's own identity —
/// so the page's `@State` hydrates in its own (branch-distinguished) scope and
/// no longer collides. As a bonus, the closure is invoked only for the page
/// actually on screen, so off-screen pages aren't built.
struct LazyPage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}
