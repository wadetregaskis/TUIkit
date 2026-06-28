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
///      how to suppress the 'N more above / below' chrome
///      without disabling scrolling.
struct ScrollViewPage: View {
    @State var searchText: String = ""
    @State var counter: Int = 0
    @State var sliderValue: Double = 50

    // Live scrollbar settings for the configurable demo below.
    @State var barVisibility: ScrollbarVisibility = .visible
    @State var barArrows: ScrollbarArrows = .single
    @State var barProportional: Bool = true
    @State var barClickBehavior: ScrollbarClickBehavior = .page

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.scrollView.longTextSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.scrollView.longTextBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    ScrollView {
                        VStack(alignment: .leading) {
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
                            Text(L("page.scrollView.heading")).bold()
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
                L("page.scrollView.title"),
                subtitle: L("page.scrollView.subtitle")
            )
        }
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
