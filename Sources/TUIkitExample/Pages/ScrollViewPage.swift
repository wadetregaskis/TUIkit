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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Long text — wheel scrolls without focus") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Roll the wheel anywhere over the box below to "
                            + "scroll. Click into it and use ↑/↓, PageUp/"
                            + "PageDown, Home/End for keyboard scrolling. "
                            + "Indicators along the top and bottom edges "
                            + "show how many rows are off-screen."
                    )
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

            DemoSection("Mixed-widget content — inner controls still work") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "ScrollView doesn't impose any row structure — "
                            + "it just windows whatever you put in it. "
                            + "Click and type into the field, tap the "
                            + "buttons, drag the slider — all of it "
                            + "works the same as outside a ScrollView."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("A heading inside the scroll view").bold()
                            HStack(spacing: 1) {
                                Text("Filter:")
                                TextField("Filter", text: $searchText,
                                          prompt: Text("type to filter…"))
                            }
                            ValueDisplayRow("Search:", searchText)

                            Text("Buttons in a scroll view:").bold()
                            HStack(spacing: 1) {
                                Button("-1") { counter -= 1 }
                                Button("+1") { counter += 1 }
                                Button("Reset", role: .destructive) { counter = 0 }
                            }
                            ValueDisplayRow("Counter:", "\(counter)")

                            Text("A slider:").bold()
                            Slider(value: $sliderValue, in: 0...100, step: 1)
                            ValueDisplayRow(
                                "Slider value:", String(format: "%.0f", sliderValue))

                            Text("And a long block of trailing text:").bold()
                            ForEach(loremLines.prefix(20), id: \.self) { Text($0) }
                        }
                    }
                    .frame(height: 10)
                    .border(color: .palette.border)
                }
            }

            DemoSection("Indicators off — same scrolling, no chrome") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "The same long-text box but with "
                            + ".showsIndicators(false). Wheel and "
                            + "keyboard scrolling still work; the "
                            + "edge chrome is just suppressed."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading) {
                            ForEach(loremLines, id: \.self) { line in
                                Text(line)
                            }
                        }
                    }
                    .frame(height: 5)
                    .border(color: .palette.border)
                }
            }

            Spacer()

            KeyboardHelpSection(
                "ScrollView shortcuts",
                shortcuts: [
                    "Mouse wheel: scroll the viewport anywhere (no focus needed)",
                    "[↑/↓]: scroll one line (when focused)",
                    "[PageUp/PageDown]: scroll one viewport",
                    "[Home/End]: jump to top / bottom",
                ]
            )
        }
        .padding(.horizontal, 1)
        .appHeader {
            DemoAppHeader(
                "ScrollView",
                subtitle: "Generic scrollable container for arbitrary content"
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
