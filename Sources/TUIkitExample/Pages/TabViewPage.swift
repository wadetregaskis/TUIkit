//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// TabView demo page.
///
/// Shows the `TabView` control in both of its styles:
/// - `.compact` — a lightweight strip of chip-style tab headers with no chrome
///   around the content (the style the colour picker uses). Here it's set to
///   leading alignment via `.tabViewHeaderAlignment(_:)`.
/// - `.bordered` — folder tabs sitting on a line-drawing content box (like
///   `List` / `Table` / the app header). Inactive tabs are separated from the
///   content by the box's top border; the active tab's row floats to the bottom
///   and the border curves around it (`╯ … ╰`) so the tab and body read as one.
///   The strip is centred by default and the content is padded for breathing
///   room (both adjustable via `.tabViewHeaderAlignment(_:)` /
///   `.tabViewContentPadding(_:)`).
///
/// In both styles the active tab and the content share a subtle surface (a quiet
/// lift above the base background, like the status bar / app header), and the
/// active tab breathes on the pulse clock while the strip is focused.
///
/// A third **adjustable** demo wires the header alignment
/// (`.tabViewHeaderAlignment(_:)`) and wrap mode (`.tabViewHeaderWrap(_:)`) to
/// live controls so the strip's placement and folding can be tried interactively.
struct TabViewPage: View {
    @State private var compactSelection = 0
    @State private var borderedSelection = 0
    @State private var notify = true
    @State private var volume = 0.6

    // Live settings for the "Adjustable" demo below.
    @State private var adjustableSelection = 0
    @State private var headerAlignment: HeaderAlignment = .center
    @State private var foldStrip = true

    /// A `Picker`-friendly (`Hashable`) stand-in for ``HorizontalAlignment``,
    /// which is `Sendable` but not `Hashable`, so it can't be a selection tag.
    private enum HeaderAlignment: String, CaseIterable, Hashable {
        case leading = "Leading", center = "Centre", trailing = "Trailing"
        var alignment: HorizontalAlignment {
            switch self {
            case .leading: .leading
            case .center: .center
            case .trailing: .trailing
            }
        }

        /// The localization key for the displayed name (the `rawValue` stays the
        /// stable, English `Picker` tag; only the shown text is localized).
        var localizationKey: String {
            switch self {
            case .leading: "page.tabView.alignLeading"
            case .center: "page.tabView.alignCentre"
            case .trailing: "page.tabView.alignTrailing"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.tabView.compactStyle")) {
                TabView(selection: $compactSelection) {
                    Tab(L("page.tabView.profile"), value: 0) {
                        VStack(alignment: .leading) {
                            Text("Ada Lovelace").bold()
                            Text(L("page.tabView.firstProgrammer"))
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                    }
                    Tab(L("page.tabView.settings"), value: 1) {
                        Toggle(L("page.tabView.notifications"), isOn: $notify)
                    }
                    Tab(L("page.tabView.about"), value: 2) {
                        Text("TUIkit · v1.0")
                    }
                }
                .tabViewStyle(.compact)
                .tabViewHeaderAlignment(.leading)
            }

            DemoSection(L("page.tabView.borderedStyle")) {
                TabView(selection: $borderedSelection) {
                    Tab(L("page.tabView.overview"), value: 0) {
                        Text(L("page.tabView.borderedDescription"))
                    }
                    Tab(L("page.tabView.audio"), value: 1) {
                        VStack(alignment: .leading) {
                            Text(L("page.tabView.volume"))
                            Slider(value: $volume, in: 0...1)
                                .frame(width: 24)
                        }
                    }
                    Tab(L("page.tabView.status"), value: 2) {
                        Toggle(L("page.tabView.online"), isOn: $notify)
                    }
                    Tab(L("page.tabView.help"), value: 3) {
                        Text(L("page.tabView.helpSwitchTabs"))
                    }
                }
                .tabViewStyle(.bordered)
            }

            DemoSection(L("page.tabView.adjustable")) {
                VStack(alignment: .leading, spacing: 1) {
                    Picker(L("page.tabView.tabStripAlignment"), selection: $headerAlignment) {
                        ForEach(HeaderAlignment.allCases, id: \.self) { choice in
                            Text(L(choice.localizationKey)).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    // Fold the strip to the content width (so it wraps onto
                    // several rows) instead of keeping it on one wide row — the
                    // same choice the colour picker makes. With it on, the
                    // alignment above visibly shifts each folded row.
                    Toggle(L("page.tabView.foldStrip"), isOn: $foldStrip)

                    TabView(selection: $adjustableSelection) {
                        ForEach(Array(["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"].enumerated()), id: \.offset) { index, name in
                            Tab(name, value: index) {
                                Text("\(L("page.tabView.sectionDetailsPrefix")) \(name) \(L("page.tabView.sectionDetailsSuffix"))")
                            }
                        }
                    }
                    .tabViewStyle(.bordered)
                    .tabViewHeaderAlignment(headerAlignment.alignment)
                    .tabViewHeaderWrap(foldStrip ? .toContentWidth : .minimal)
                }
            }

            KeyboardHelpSection(
                L("page.tabView.navigation"),
                shortcuts: [
                    L("page.tabView.helpFocusStrip"),
                    L("page.tabView.helpSwitchKeys"),
                    L("page.tabView.helpClickHeader"),
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.tabView.title"))
        }
    }
}
