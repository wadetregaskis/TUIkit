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

    // The nested demo: an outer strip whose tabs carry strips of their own.
    @State private var nestedOuter = 0
    @State private var nestedGeneral = 0
    @State private var nestedNetwork = 0
    @State private var nestedVolume = 0.4
    @State private var nestedNotify = false
    @State private var nestedOnline = true

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

            DemoSection("page.tabView.nested") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.tabView.nestedHint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    nestedTabs
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

    /// Tab views inside tab views.
    ///
    /// A tab's content is an ordinary view, so there is nothing special about
    /// putting another `TabView` in it — which is the point worth showing, along
    /// with the two things that follow from it. The strips are independent
    /// controls: each takes its own turn in the Tab order and ←/→ move whichever
    /// one holds the focus. And the styles nest either way round: an inner
    /// `.compact` strip sits inside the outer box's padding as a row of chips,
    /// while an inner `.bordered` one draws its own box inside the outer one.
    ///
    /// Both are worth having on screen at once, because which reads better is a
    /// judgement about the content, not a rule — chips for a couple of small
    /// panes, a box when the inner content wants its own frame.
    private var nestedTabs: some View {
        TabView(selection: $nestedOuter) {
            Tab("page.tabView.nested.general", value: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    TabView(selection: $nestedGeneral) {
                        Tab("page.tabView.nested.appearance", value: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("page.tabView.volume")
                                Slider(value: $nestedVolume, in: 0...1)
                                    .frame(width: 24)
                            }
                        }
                        Tab("page.tabView.nested.behaviour", value: 1) {
                            Toggle("page.tabView.notifications", isOn: $nestedNotify)
                        }
                    }
                    .tabViewStyle(.compact)
                    .tabViewHeaderAlignment(.leading)
                }
            }
            Tab("page.tabView.nested.network", value: 1) {
                TabView(selection: $nestedNetwork) {
                    Tab("page.tabView.nested.proxies", value: 0) {
                        Toggle("page.tabView.online", isOn: $nestedOnline)
                    }
                    Tab("page.tabView.nested.dns", value: 1) {
                        // Demo data, not prose: nothing here to translate.
                        Text(verbatim: "1.1.1.1\n8.8.8.8")
                    }
                }
                .tabViewStyle(.bordered)
            }
            Tab("page.tabView.nested.plain", value: 2) {
                Text("page.tabView.nested.plainBody")
            }
        }
        .tabViewStyle(.bordered)
    }
}
