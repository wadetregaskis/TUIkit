//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationPanelSlot.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

extension AnimationPage {
    /// The panel, and the two answers to "what happens to the space it was in?"
    ///
    /// Either way the removal itself plays out — the slot a `nil` leaves behind
    /// holds the panel's rows open until the transition has finished. The
    /// toggle is about what happens *after* that: reclaimed, and the page
    /// closes up; reserved, and the gap stays so nothing below ever moves.
    ///
    /// A function rather than a view of its own, so that what it returns
    /// stands in the page's stack exactly as if it were written there: a view
    /// with a `body` would be one child of the stack, drawn as a unit, where
    /// a frame on an `if` written in the stack reaches the `if`'s members.
    ///
    /// - Parameters:
    ///   - showsPanel: Whether the panel is there.
    ///   - reservesSpace: Whether its rows are kept while it is not.
    ///   - transition: How it comes and goes.
    static func panelSlot(
        showsPanel: Bool, reservesSpace: Bool, transition: AnyTransition
    ) -> some View {
        // The frame is on a stack that is always there, and the `if` is inside
        // it. On the `if` itself — `(showsPanel ? panel : nil).frame(…)`, which
        // this used to be — the frame reaches only what the `if` has, as a
        // frame on a `Group` reaches only its members, and with the panel gone
        // that is nothing: no rows were kept at all. SwiftUI does the same,
        // measured: a `nil` framed 50 tall adds no height to its stack, the
        // same `nil` in a `VStack` framed 50 tall adds 50.
        //
        // One frame either way, with a height of `nil` when the space is not
        // reserved — NOT `if reserved { slot.frame(…) } else { slot }`.
        // Swapping the wrapper is a change of view IDENTITY: every `@State`
        // below it is recreated at its initial value the moment the toggle
        // flips, which is a bug this page would have been an unusually good
        // place to demonstrate accidentally. Unreserved and empty, the stack
        // is no rows and takes no spacing, so the page closes up as before —
        // TUIkit's rule, not SwiftUI's, which would leave a spacing's gap
        // (`Documentation/SwiftUI-compatibility.md`, "A child with no extent
        // takes no stack spacing").
        //
        // Five rows, which is what the panel IS: a text row, a row of padding
        // each side of it, and the border's two. Reserving three left the
        // padding fighting the border for one row.
        VStack(spacing: 0) {
            if showsPanel {
                Text("page.animation.panel")
                    .padding(1)
                    .border(.palette.accent)
                    .transition(transition)
            }
        }
        .frame(height: reservesSpace ? 5 : nil, alignment: .top)
    }
}
