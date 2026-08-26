//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainersPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Static row showing Card, Box, and Panel side by side.
///
/// Purely palette-driven, no state — wrapped in `.equatable()` for
/// subtree memoization during Spinner/Pulse animation frames.
struct ContainerTypesRow: View, Equatable {
    var body: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading) {
                Text("Card").bold().foregroundStyle(.palette.accent)
                Card(borderColor: .palette.border) {
                    Text("page.containers.aCardView").foregroundStyle(.palette.foreground)
                    Text("page.containers.withPadding").foregroundStyle(.palette.foregroundSecondary)
                }
            }

            VStack(alignment: .leading) {
                Text(".border()").bold().foregroundStyle(.palette.accent)
                Text("page.containers.simpleBordered")
                    .foregroundStyle(.palette.foreground)
                    .border()
            }

            VStack(alignment: .leading) {
                Text("Panel").bold().foregroundStyle(.palette.accent)
                Panel("page.containers.info", titleColor: .palette.accent) {
                    Text("page.containers.titleInBorder").foregroundStyle(.palette.foreground)
                }
            }
        }
    }
}

/// Static row showing a settings panel with footer and alignment examples.
///
/// Purely palette-driven, no state — wrapped in `.equatable()` for
/// subtree memoization during Spinner/Pulse animation frames.
struct SettingsAndAlignmentRow: View, Equatable {
    var body: some View {
        HStack(spacing: 2) {
            DemoSection("page.containers.section.panelHeaderFooter") {
                Panel("page.containers.settings", titleColor: .palette.accent) {
                    Text("page.containers.primaryText").foregroundStyle(.palette.foreground)
                    Text("page.containers.secondaryText").foregroundStyle(.palette.foregroundSecondary)
                    Text("page.containers.tertiaryText").foregroundStyle(.palette.foregroundTertiary)
                } footer: {
                    Text("page.containers.footerConfirm").foregroundStyle(.palette.foreground)
                }
            }

            DemoSection("page.containers.section.contentAlignment") {
                // Each bordered box uses `.frame(maxWidth: .infinity)` so the
                // three share the row evenly. When the terminal is wide they
                // expand and you can see "short" pushed against the
                // leading/center/trailing edge — which is the whole point of
                // the demo. When the terminal is narrow they shrink together
                // and the longer label wraps to a second line, but neither
                // box ever disappears and "short" stays visible underneath.
                HStack(spacing: 1) {
                    VStack(alignment: .leading) {
                        Text("page.containers.leadingAlign").foregroundStyle(.palette.foreground)
                        Text("page.containers.short").foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .border()

                    VStack(alignment: .center) {
                        Text("page.containers.centerAlign").foregroundStyle(.palette.foreground)
                        Text("page.containers.short").foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .border()

                    VStack(alignment: .trailing) {
                        Text("page.containers.trailingAlign").foregroundStyle(.palette.foreground)
                        Text("page.containers.short").foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .border()
                }
            }
        }
    }
}

/// Container views demo page.
///
/// Shows various container views including:
/// - Card (bordered container with padding)
/// - Box (simple bordered container)
/// - Panel (container with title in border)
/// - ProgressView (horizontal progress bar)
/// - DisclosureGroup, in both forms: an outer one whose expansion this page
///   owns (so the button beside it moves the same state), and a nested one
///   that owns its own
struct ContainersPage: View {
    @State var showDetails: Bool = false

    /// The app-wide appearance, which is what decides every border's style.
    /// Cycled here by `b` / `B` — this being the page whose whole subject is
    /// bordered containers, and the only one where seeing the six styles in
    /// turn is the point rather than a side effect.
    @Environment(\.appearanceManager) private var appearanceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ContainerTypesRow().equatable()
            SettingsAndAlignmentRow().equatable()
            // ProgressView used to live here; it now has its own demo page
            // (press the back-tick shortcut on the menu) covering both
            // determinate and indeterminate variants of every style.

            DemoSection("page.containers.section.collapsible") {
                VStack(alignment: .leading) {
                    // The OUTER group's expansion is owned by this page, so the
                    // group and the button under it are two views of one truth:
                    // clicking either moves both. That is what `isExpanded:` is
                    // for — without it a group keeps its own state and nothing
                    // outside can open it.
                    DisclosureGroup("page.containers.paddingExamples", isExpanded: $showDetails) {
                        VStack(alignment: .leading) {
                            HStack(spacing: 1) {
                                Text("h:1 v:0").foregroundStyle(.palette.foreground)
                                    .padding(.horizontal, 1)
                                    .border()

                                Text("h:1 v:1").foregroundStyle(.palette.foreground)
                                    .padding(EdgeInsets(horizontal: 1, vertical: 1))
                                    .border()

                                Text("h:1 v:2").foregroundStyle(.palette.foreground)
                                    .padding(EdgeInsets(horizontal: 1, vertical: 2))
                                    .border()
                            }

                            // The INNER group owns its own expansion, and its
                            // content is indented one step further — which is
                            // how nesting draws a tree.
                            DisclosureGroup("page.containers.disclosure.nested") {
                                Text("page.containers.primaryText")
                                    .foregroundStyle(.palette.foreground)
                                Text("page.containers.secondaryText")
                                    .foregroundStyle(.palette.foregroundSecondary)
                            }
                        }
                    }

                    HStack(spacing: 2) {
                        Button(showDetails ? L("page.containers.hideDetails") : L("page.containers.showDetails")) {
                            showDetails.toggle()
                        }
                        Text(showDetails ? L("page.containers.expanded") : L("page.containers.collapsed"))
                            .dim()
                    }
                }
            }

            // The recursive form of the same idea: one `OutlineGroup` draws the
            // whole tree, disclosing a level at a time. "Tests" has an EMPTY
            // children array rather than nil, so it still gets a triangle —
            // "this folder has nothing in it" being worth saying.
            DemoSection("page.containers.section.outline") {
                OutlineGroup(outlineDemoTree, children: \.children) { node in
                    Text(verbatim: node.id)
                }
            }

            DemoSection("page.containers.section.appearance") {
                Text("page.containers.borderStyleHelp").foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 1) {
                    Text("page.containers.currentBorderStyle")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(verbatim: appearanceManager?.currentName ?? "—")
                        .bold()
                        .foregroundStyle(.palette.accent)
                }
            }

            // The page had no keyboard help at all, and it is the page whose
            // controls answer the least obvious keys: Left and Right disclose
            // here as they do in a tree, which nothing on screen said.
            KeyboardHelpSection(shortcuts: [
                "page.containers.help.tab",
                "page.containers.help.toggle",
                "page.containers.help.arrows",
            ])

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.containers")
        }
        .statusBarItems(statusBarItems)
    }

    /// This page's footer.
    ///
    /// `b` cycles the appearance forward and `B` back, the pair spelled the way
    /// the image pages spell theirs: one visible item carrying the dual-key
    /// indicator and the current value, and a hidden partner for the uppercase
    /// key. Escape and the arrows are informational — the page switch and the
    /// scroll are handled above this page.
    private var statusBarItems: [any StatusBarItemProtocol] {
        [
            StatusBarItem(shortcut: Shortcut.escape, label: "status.back"),
            StatusBarItem(
                shortcut: "b|B",
                label: "border:" + (appearanceManager?.currentAppearance?.id ?? "?"),
                key: .character("b")
            ) {
                appearanceManager?.cycleNext()
            },
            StatusBarItem(
                shortcut: "B",
                label: "",
                key: .character("B"),
                displayInStatusBar: false
            ) {
                appearanceManager?.cyclePrevious()
            },
            StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "status.scroll"),
        ]
    }
}
