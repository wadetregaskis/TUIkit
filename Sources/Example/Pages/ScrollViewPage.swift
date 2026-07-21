//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Demonstrates ``ScrollView`` — TUIkit's generic scrollable
/// container for arbitrary content. Unlike ``List``, ScrollView
/// has no rows, no selection, no item structure; it just gives
/// you a viewport over content taller than itself.
///
/// Three demos cover the interesting axes:
///
///   1. A long body of plain text — scroll with the wheel
///      anywhere on the page, or focus the view and use the
///      arrow / Page / Home / End keys.
///   2. Mixed widget content (a header, a TextField, several
///      Buttons, a Slider, a long Text trailer) — to show
///      that ScrollView happily wraps anything, and that inner
///      controls still respond to clicks and keyboard input
///      inside it.
///   3. The same content with `showsIndicators: false` to show
///      how to suppress the 'N more lines above / below' chrome
///      without disabling scrolling.
struct ScrollViewPage: View {
    @State var searchText: String = ""
    @State var counter: Int = 0
    @State var sliderValue: Double = 50

    // Scroll-anchoring demo: rows that can be inserted/removed ABOVE the
    // anchored one, so the hold is visible as the data shifts under it.
    @State var anchorRows: [Int] = Array(1...40)
    @State var rowAnchor: ScrollAnchor<Int>?
    @State var nextInsertedRow = 100

    /// The row the demo designates. Fixed so it can be labelled in the list.
    private static let anchoredRow = 20

    // Live scrollbar settings for the configurable demo below.
    @State var barVisibility: ScrollbarVisibility = .visible
    @State var barArrows: ScrollbarArrows = .single
    @State var barProportional: Bool = true
    @State var barClickBehavior: ScrollbarClickBehavior = .page
    @State var revealFollowMargin = FollowMarginChoice.none.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.scrollView.longTextSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.scrollView.longTextBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    ScrollView {
                        VStack(alignment: .leading) {
                            // An animated row right at the top of the FIRST
                            // scroll view, so the "animation keeps running
                            // inside scrolled content" behaviour is visible the
                            // moment the page opens (there's a second Spinner
                            // in the mixed-content section below).
                            HStack(spacing: 1) {
                                Spinner(style: .line)
                                Text(L("page.scrollView.liveRow")).dim()
                            }
                            ForEach(loremLines, id: \.self) { line in
                                Text(line)
                            }
                        }
                    }
                    .frame(height: 8)
                    .border(color: .palette.border)
                }
            }

            DemoSection(L("page.scrollView.mixedSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.scrollView.mixedBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            // An animated cell inside a ScrollView: the Spinner
                            // must keep ticking even though its row is memoized
                            // (verifies the animation-in-cell gate; see also
                            // SpinnerRowAnimationTests).
                            HStack(spacing: 1) {
                                Text(L("page.scrollView.heading")).bold()
                                Spinner(style: .dots)
                            }
                            HStack(spacing: 1) {
                                Text(L("page.scrollView.filter"))
                                TextField(L("page.scrollView.filterField"), text: $searchText,
                                          prompt: Text(L("page.scrollView.filterPrompt")))
                            }
                            ValueDisplayRow(L("page.scrollView.search"), searchText)

                            Text(L("page.scrollView.buttonsLabel")).bold()
                            HStack(spacing: 1) {
                                Button("-1") { counter -= 1 }
                                Button("+1") { counter += 1 }
                                Button(L("page.scrollView.reset"), role: .destructive) { counter = 0 }
                            }
                            ValueDisplayRow(L("page.scrollView.counter"), "\(counter)")

                            Text(L("page.scrollView.sliderLabel")).bold()
                            Slider(value: $sliderValue, in: 0...100, step: 1)
                            ValueDisplayRow(
                                L("page.scrollView.sliderValue"), String(format: "%.0f", sliderValue))

                            Text(L("page.scrollView.trailingLabel")).bold()
                            ForEach(Array(loremLines.prefix(20)), id: \.self) { Text($0) }
                        }
                    }
                    .frame(height: 10)
                    .border(color: .palette.border)
                }
            }

            DemoSection(L("page.scrollView.scrollbarSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.scrollView.scrollbarBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    // Few enough lines (18) in a tall enough viewport (10) that the
                    // proportional thumb is several cells — clearly larger than the
                    // fixed one-cell thumb when the toggle below is turned off. With
                    // the full 60-line body the proportional thumb would round down
                    // to the one-cell minimum and look identical.
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(Array(loremLines.prefix(18)), id: \.self) { line in
                                Text(line)
                            }
                        }
                    }
                    .frame(height: 10)
                    .border(color: .palette.border)
                    .scrollbarVisibility(barVisibility)
                    .scrollbarArrows(barArrows)
                    .scrollbarProportionalThumb(barProportional)
                    .scrollbarClickBehavior(barClickBehavior)
                    .scrollFollowMargin(
                        FollowMarginChoice(rawValue: revealFollowMargin)?.margin ?? .none)

                    Text(L("page.scrollView.scrollbarInteractive"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    Picker(L("page.scrollView.visibility"), selection: $barVisibility) {
                        Text(L("page.scrollView.visibility.automatic")).tag(ScrollbarVisibility.automatic)
                        Text(L("page.scrollView.visibility.visible")).tag(ScrollbarVisibility.visible)
                        Text(L("page.scrollView.visibility.hidden")).tag(ScrollbarVisibility.hidden)
                    }
                    Picker(L("page.scrollView.endArrows"), selection: $barArrows) {
                        Text(L("page.scrollView.arrows.none")).tag(ScrollbarArrows.none)
                        Text(L("page.scrollView.arrows.single")).tag(ScrollbarArrows.single)
                        Text(L("page.scrollView.arrows.double")).tag(ScrollbarArrows.double)
                    }
                    Picker(L("page.scrollView.trackClick"), selection: $barClickBehavior) {
                        Text(L("page.scrollView.click.page")).tag(ScrollbarClickBehavior.page)
                        Text(L("page.scrollView.click.jump")).tag(ScrollbarClickBehavior.jump)
                    }
                    Toggle(L("page.scrollView.proportionalThumb"), isOn: $barProportional)
                    // How early the reveal-on-focus scrolls: at the edge
                    // (default), 2 lines early, or keeping the control centred.
                    FollowMarginPicker(selection: $revealFollowMargin)
                }
            }

            DemoSection(L("page.scrollView.anchorSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.scrollView.anchorBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    ScrollView {
                        // LazyVStack, not VStack: anchoring is a property of
                        // the WINDOWED render paths, so an eager stack (which
                        // draws the whole canvas and lets the ScrollView clip
                        // it) has no anchor to hold.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(anchorRows, id: \.self) { row in
                                anchorRowView(row)
                            }
                        }
                    }
                    .frame(height: 8)
                    .border(color: .palette.border)
                    // The whole point: with a row designated, inserting or
                    // removing rows above it moves the SCROLL POSITION, not
                    // the row. Release it and the same edits shove it around.
                    .anchorPosition($rowAnchor)

                    HStack(spacing: 1) {
                        Button(L("page.scrollView.anchorInsert")) { insertRowsAbove() }
                        Button(L("page.scrollView.anchorRemove")) { removeRowsAbove() }
                        Button(L("page.scrollView.anchorReset")) { resetAnchorRows() }
                    }
                    HStack(spacing: 1) {
                        Button(L("page.scrollView.anchorHold")) {
                            rowAnchor = .row(Self.anchoredRow)
                        }
                        Button(L("page.scrollView.anchorRelease")) { rowAnchor = .window }
                    }
                    ValueDisplayRow(L("page.scrollView.anchorState"), anchorDescription)
                }
            }

            DemoSection(L("page.scrollView.indicatorsOffSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.scrollView.indicatorsOffBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading) {
                            ForEach(loremLines, id: \.self) { line in
                                Text(line)
                            }
                        }
                    }
                    .frame(height: 5)
                }
            }

            Spacer()

            KeyboardHelpSection(
                L("page.scrollView.shortcutsTitle"),
                shortcuts: [
                    L("page.scrollView.help.wheel"),
                    L("page.scrollView.help.line"),
                    L("page.scrollView.help.page"),
                    L("page.scrollView.help.jump"),
                ]
            )
        }
        .padding(.horizontal, 1)
        // The page itself is taller than most terminals (several framed demo
        // ScrollViews stacked), so wrap it too. The inner demos are fixed-height,
        // so this nests cleanly, and Tab-ing to a control below the fold now
        // scrolls the page to reveal it.
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(
                L("menu.item.scrollView"),
                subtitle: L("page.scrollView.subtitle")
            )
        }
    }

    // MARK: - Scroll anchoring

    /// One row of the anchoring demo, with the designated row called out so
    /// it can be followed by eye as rows are inserted and removed above it.
    @ViewBuilder
    private func anchorRowView(_ row: Int) -> some View {
        if row == Self.anchoredRow {
            Text("▶ \(L("page.scrollView.anchorRowLabel")) \(row)")
            .bold()
            .foregroundStyle(.palette.accent)
        } else {
            Text("  \(L("page.scrollView.anchorRowPlain")) \(row)")
        }
    }

    /// The bound anchor, spelled out — including the distinction the optional
    /// exists for: `nil` (never departed from the declared anchor) reads
    /// differently from `.window` (explicitly released).
    private var anchorDescription: String {
        switch rowAnchor {
        case .none: L("page.scrollView.anchorState.none")
        case .window: L("page.scrollView.anchorState.window")
        case .top: L("page.scrollView.anchorState.top")
        case .bottom: L("page.scrollView.anchorState.bottom")
        case .row(let id): "\(L("page.scrollView.anchorState.row")) \(id)"
        }
    }

    private func insertRowsAbove() {
        guard let index = anchorRows.firstIndex(of: Self.anchoredRow) else { return }
        let inserted = (0..<5).map { nextInsertedRow + $0 }
        nextInsertedRow += 5
        anchorRows.insert(contentsOf: inserted, at: max(0, index - 3))
    }

    private func removeRowsAbove() {
        guard let index = anchorRows.firstIndex(of: Self.anchoredRow), index > 0 else { return }
        anchorRows.removeSubrange(max(0, index - 5)..<index)
    }

    private func resetAnchorRows() {
        anchorRows = Array(1...40)
        nextInsertedRow = 100
    }

    /// A long enough body of text to overflow the demo viewports.
    /// Made of distinct lines so the user can see which row is
    /// where as they scroll.
    private var loremLines: [String] {
        (1...60).map { line in
            "Line \(line) — \(loremFragments[line % loremFragments.count])"
        }
    }

    private let loremFragments: [String] = [
        "lorem ipsum dolor sit amet",
        "consectetur adipiscing elit",
        "sed do eiusmod tempor incididunt",
        "ut labore et dolore magna aliqua",
        "ut enim ad minim veniam",
        "quis nostrud exercitation",
        "ullamco laboris nisi ut aliquip",
        "ex ea commodo consequat",
        "duis aute irure dolor",
        "in reprehenderit in voluptate",
        "velit esse cillum dolore",
        "eu fugiat nulla pariatur",
    ]
}
