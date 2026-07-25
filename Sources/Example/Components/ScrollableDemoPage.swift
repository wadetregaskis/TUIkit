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
        // `.scrollbarVisibility` is an ENVIRONMENT value, so it reaches every
        // scrollable in the subtree — SwiftUI-parity behaviour, matching
        // `.scrollIndicators`. That is right for the modifier and wrong here:
        // the page wants a bar for ITSELF, but the demos inside it are showing
        // off their own chrome choices, and the page's `.automatic` was
        // overriding all of them. It is why the "Indicators off — fully naked"
        // section had a scrollbar, and why the section titled "naked ScrollView
        // with default indicators" showed a bar instead of the indicators its
        // own prose promises (a bar supersedes them).
        //
        // Restore the framework default (`.hidden`, i.e. opt-in) for the
        // content; the outer write is the one `_ScrollViewCore` reads for the
        // page's own bar. Demos that want a bar still ask for one explicitly
        // and still win, since their write is deeper.
        ScrollView { self.scrollbarVisibility(.hidden) }
            .scrollbarVisibility(.automatic)
    }
}
