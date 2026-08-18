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
/// (`.tabViewHeaderAlignment(_:)`), wrap mode (`.tabViewHeaderWrap(_:)`) and
/// content sizing (`.tabViewContentSizing(_:)`, size to the tallest tab vs the
/// visible one) to live controls so the strip's placement, folding and vertical
/// sizing can be tried interactively.
struct TabViewPage: View {
    @State private var compactSelection = 0
    @State private var borderedSelection = 0
    @State private var notify = true
    /// The two fields the tabs carry — a text control inside a tab is where the
    /// field's own surface has to be told what it sits on, or it comes out the
    /// tab's colour (see ``Palette/fieldBackground(on:)``).
    @State private var displayName = "Ada"
    @State private var statusMessage = ""
    @State private var volume = 0.6
    // The bordered demo's own switch. It reads as a sibling of `notify` above
    // but belongs to a different `TabView`, and the two demos are independent —
    // one binding behind both made flipping "Notifications" in the compact demo
    // silently flip "Online" in the bordered one.
    @State private var online = true

    // Live settings for the "Adjustable" demo below.
    @State private var adjustableSelection = 0
    @State private var headerAlignment: HeaderAlignment = .center
    @State private var foldStrip = true
    // Off (default) sizes the box to the tallest tab so it never jumps as you
    // switch; on sizes it to whichever tab is visible. Drives
    // `.tabViewContentSizing(_:)` on the adjustable demo below.
    @State private var sizeToVisibleTab = false

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

            DemoSection("page.tabView.compactStyle") {
                TabView(selection: $compactSelection) {
                    Tab("page.tabView.profile", value: 0) {
                        VStack(alignment: .leading) {
                            Text("Ada Lovelace").bold()
                            Text("page.tabView.firstProgrammer")
                                .foregroundStyle(.palette.foregroundSecondary)
                            HStack {
                                Text("page.tabView.displayName")
                                TextField("page.tabView.displayNamePrompt", text: $displayName)
                                    .frame(width: 18)
                            }
                        }
                    }
                    Tab("page.tabView.settings", value: 1) {
                        Toggle("page.tabView.notifications", isOn: $notify)
                    }
                    Tab("page.tabView.about", value: 2) {
                        Text("TUIkit · v1.0")
                    }
                }
                .tabViewStyle(.compact)
                .tabViewHeaderAlignment(.leading)
            }

            DemoSection("page.tabView.borderedStyle") {
                TabView(selection: $borderedSelection) {
                    Tab("page.tabView.overview", value: 0) {
                        Text("page.tabView.borderedDescription")
                    }
                    Tab("page.tabView.audio", value: 1) {
                        VStack(alignment: .leading) {
                            Text("page.tabView.volume")
                            Slider(value: $volume, in: 0...1)
                                .frame(width: 24)
                        }
                    }
                    Tab("page.tabView.status", value: 2) {
                        VStack(alignment: .leading) {
                            Toggle("page.tabView.online", isOn: $online)
                            HStack {
                                Text("page.tabView.statusMessage")
                                TextField(
                                    "page.tabView.statusMessagePrompt", text: $statusMessage
                                )
                                .frame(width: 22)
                            }
                        }
                    }
                    Tab("page.tabView.help", value: 3) {
                        Text("page.tabView.helpSwitchTabs")
                    }
                }
                .tabViewStyle(.bordered)
            }

            DemoSection("page.tabView.adjustable") {
                VStack(alignment: .leading, spacing: 1) {
                    Picker("page.tabView.tabStripAlignment", selection: $headerAlignment) {
                        ForEach(HeaderAlignment.allCases, id: \.self) { choice in
                            Text(L(choice.localizationKey)).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    // Fold the strip to the content width (so it wraps onto
                    // several rows) instead of keeping it on one wide row — the
                    // same choice the colour picker makes. With it on, the
                    // alignment above visibly shifts each folded row.
                    Toggle("page.tabView.foldStrip", isOn: $foldStrip)
                    // Each tab below is taller than the one before, so this
                    // toggle has a visible effect: off (the default,
                    // `.largestTab`) holds the box at the tallest tab's height so
                    // it never jumps as you switch tabs; on (`.activeTab`) shrinks
                    // the box to whichever tab is showing.
                    Toggle("page.tabView.sizeToVisibleTab", isOn: $sizeToVisibleTab)

                    TabView(selection: $adjustableSelection) {
                        ForEach(Array(["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"].enumerated()), id: \.offset) { index, name in
                            Tab(name, value: index) {
                                // Taller the further right you go (1…6 lines), to
                                // make the content-sizing toggle's effect visible.
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("\(L("page.tabView.sectionDetailsPrefix")) \(name) \(L("page.tabView.sectionDetailsSuffix"))")
                                    ForEach(0..<index, id: \.self) { line in
                                        Text("• \(name) \(line + 1)")
                                            .foregroundStyle(.palette.foregroundSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .tabViewStyle(.bordered)
                    .tabViewHeaderAlignment(headerAlignment.alignment)
                    .tabViewHeaderWrap(foldStrip ? .toContentWidth : .minimal)
                    .tabViewContentSizing(sizeToVisibleTab ? .activeTab : .largestTab)
                }
            }

            KeyboardHelpSection(
                "page.tabView.navigation",
                shortcuts: [
                    "page.tabView.helpFocusStrip",
                    "page.tabView.helpSwitchKeys",
                    "page.tabView.helpClickHeader",
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.tabViews")
        }
    }
}
