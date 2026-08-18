//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollableDemoPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

extension View {
    /// Wraps a demo page's content in a vertical `ScrollView` with an auto-hiding
    /// scrollbar, so the whole page is reachable even when the terminal is shorter
    /// than the content.
    ///
    /// Apply it just before `.appHeader` so the header (and the status bar the host
    /// adds) stay fixed while only the content scrolls:
    ///
    /// ```swift
    /// var body: some View {
    ///     VStack { … }
    ///         .scrollableDemoPage()
    ///         .appHeader { DemoAppHeader("…") }
    /// }
    /// ```
    ///
    /// A trailing `Spacer()` in the content (the usual top-align idiom) is fine —
    /// `ScrollView` ignores a flexible filler's blank lines when sizing. Pages whose
    /// content is itself greedy in height (a split view, a tab view) are left
    /// unwrapped, as they fill the viewport by design.
    func scrollableDemoPage() -> some View {
        // `.scrollIndicators` is an ENVIRONMENT value, so it reaches every
        // scrollable in the subtree — SwiftUI-parity behaviour. Writing it
        // here says the same thing for the page and for the demos inside it,
        // which is fine now that it says only WHETHER (#555): the demos each
        // decide WHICH indicator with `.scrollIndicatorStyle`, and one that
        // wants no chrome at all still says so itself and wins, its write
        // being the deeper one.
        //
        // This page used to reset the content to `.hidden` to keep its own bar
        // off the demos. That would now strip their indicators entirely rather
        // than swapping a bar for the "N more" lines, so it is gone.
        ScrollView { self }
            .scrollIndicators(.automatic)
    }
}
