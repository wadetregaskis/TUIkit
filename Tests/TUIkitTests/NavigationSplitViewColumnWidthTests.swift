//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewColumnWidthTests.swift
//
//  Coverage for `.navigationSplitViewColumnWidth(…)`, split out of
//  NavigationSplitViewTests.swift to keep that file under the length limit.
//  Both spellings shipped inert: the modifier published a preference key that
//  nothing read, so a column asking for 30 cells got the style's proportional
//  share instead.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("NavigationSplitView Column Width Tests")
struct NavigationSplitViewColumnWidthTests {
    @Test("All column-width modifier spellings compile and wrap the view")
    func columnWidthModifierSpellings() {
        // Compile-only: every overload of navigationSplitViewColumnWidth.
        _ = Text("Sidebar").navigationSplitViewColumnWidth(25)  // fixed
        _ = Text("Sidebar").navigationSplitViewColumnWidth(min: 20, ideal: 30, max: 50)  // flexible
        _ = Text("Sidebar").navigationSplitViewColumnWidth(min: 15)  // min only
        _ = Text("Sidebar").navigationSplitViewColumnWidth(max: 40)  // max only
    }

    /// The width of the leading column of a two-column split holding `sidebar`,
    /// read as the screen column its divider grip (`◦`) sits in on the centre
    /// row.
    ///
    /// Reading the geometry off the divider rather than counting the column's
    /// own glyphs keeps these tests independent of how each sidebar's content
    /// wraps — the point here is the width the split CHOSE, not what got drawn
    /// into it. (Splits are resizable by default, so the grip is always there.)
    private func sidebarWidth(
        _ sidebar: some View,
        style: some NavigationSplitViewStyle = AutomaticNavigationSplitViewStyle(),
        width: Int = 80
    ) -> Int? {
        let view = NavigationSplitView {
            sidebar
        } detail: {
            Text("DETAIL")
        }
        .navigationSplitViewStyle(style)

        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: width, availableHeight: 12, environment: environment,
            tuiContext: TUIContext())
        let buffer = renderToBuffer(view, context: context)
        guard buffer.height > 0 else { return nil }
        let middle = buffer.lines[buffer.height / 2].stripped
        return middle.firstIndex(of: "◦").map { middle.distance(from: middle.startIndex, to: $0) }
    }

    @Test("A fixed column width is the width the column gets")
    func fixedWidthIsHonoured() {
        let asked = sidebarWidth(Text("SIDEBAR").navigationSplitViewColumnWidth(30))
        let styleDefault = sidebarWidth(Text("SIDEBAR"))
        #expect(asked == 30, "asked for 30, got \(asked as Int?)")
        // Guards the assertion above against passing by coincidence: the whole
        // bug was the column silently taking its style share (26 at width 80).
        #expect(styleDefault != 30, "the style's own share must differ from the request")
    }

    @Test("min:ideal:max: opens the column at its ideal width")
    func idealWidthIsTheOpeningWidth() {
        let width = sidebarWidth(
            Text("SIDEBAR").navigationSplitViewColumnWidth(min: 20, ideal: 25, max: 40))
        #expect(width == 25, "opened at ideal, got \(width as Int?)")
    }

    @Test("min and max clamp a column that asked for neither an ideal nor a fixed width")
    func boundsClampTheStyleShare() {
        // The style's share at width 80 is 26 cells; each bound pulls it back to
        // itself.
        let narrowed = sidebarWidth(Text("SIDEBAR").navigationSplitViewColumnWidth(max: 15))
        let widened = sidebarWidth(Text("SIDEBAR").navigationSplitViewColumnWidth(min: 40))
        #expect(narrowed == 15, "a max below the style share clamps down, got \(narrowed as Int?)")
        #expect(widened == 40, "a min above it clamps up, got \(widened as Int?)")
    }

    @Test("A size-to-fit column takes the width it asked for, not its content's")
    func sizeToFitHonoursTheRequest() {
        let hugged = sidebarWidth(Text("SB"), style: SizeToFitFromLeftNavigationSplitViewStyle())
        let asked = sidebarWidth(
            Text("SB").navigationSplitViewColumnWidth(28),
            style: SizeToFitFromLeftNavigationSplitViewStyle())
        #expect(hugged == 10, "a two-cell sidebar hugs to the minimum, got \(hugged as Int?)")
        #expect(asked == 28, "…until it asks for a width, got \(asked as Int?)")
    }

    @Test("A width asked for under an intervening modifier still lands")
    func requestTravelsUpThroughAModifier() {
        // The whole reason this is a preference and not an inspection of the
        // column's own type: the modifier can sit anywhere inside the column.
        let width = sidebarWidth(Text("SIDEBAR").navigationSplitViewColumnWidth(30).padding())
        #expect(width == 30, "the request travelled up through .padding(), got \(width as Int?)")
    }

    @Test("The trailing column's request is ignored")
    func trailingColumnAbsorbsTheRemainder() {
        // The detail column is the flexible remainder by construction, so a
        // width asked for there cannot be honoured — and must not disturb the
        // column that CAN ask.
        let view = NavigationSplitView {
            Text("SIDEBAR")
        } detail: {
            Text("DETAIL").navigationSplitViewColumnWidth(60)
        }
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 80, availableHeight: 12, environment: environment,
            tuiContext: TUIContext())
        let middle = renderToBuffer(view, context: context).lines[6].stripped
        let grip = middle.firstIndex(of: "◦").map { middle.distance(from: middle.startIndex, to: $0) }
        #expect(grip == 26, "the sidebar keeps the style's share, got \(grip as Int?)")
    }
}
