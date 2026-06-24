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
        ScrollView { self }
            .scrollbarVisibility(.automatic)
    }
}
