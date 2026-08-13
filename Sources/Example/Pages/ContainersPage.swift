//  🖥️ TUIKit — Terminal UI Kit for Swift
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
                    Text(L("page.containers.aCardView")).foregroundStyle(.palette.foreground)
                    Text(L("page.containers.withPadding")).foregroundStyle(.palette.foregroundSecondary)
                }
            }

            VStack(alignment: .leading) {
                Text(".border()").bold().foregroundStyle(.palette.accent)
                Text(L("page.containers.simpleBordered"))
                    .foregroundStyle(.palette.foreground)
                    .border()
            }

            VStack(alignment: .leading) {
                Text("Panel").bold().foregroundStyle(.palette.accent)
                Panel(L("page.containers.info"), titleColor: .palette.accent) {
                    Text(L("page.containers.titleInBorder")).foregroundStyle(.palette.foreground)
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
            DemoSection(L("page.containers.section.panelHeaderFooter")) {
                Panel(L("page.containers.settings"), titleColor: .palette.accent) {
                    Text(L("page.containers.primaryText")).foregroundStyle(.palette.foreground)
                    Text(L("page.containers.secondaryText")).foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.containers.tertiaryText")).foregroundStyle(.palette.foregroundTertiary)
                } footer: {
                    Text(L("page.containers.footerConfirm")).foregroundStyle(.palette.foreground)
                }
            }

            DemoSection(L("page.containers.section.contentAlignment")) {
                // Each bordered box uses `.frame(maxWidth: .infinity)` so the
                // three share the row evenly. When the terminal is wide they
                // expand and you can see "short" pushed against the
                // leading/center/trailing edge — which is the whole point of
                // the demo. When the terminal is narrow they shrink together
                // and the longer label wraps to a second line, but neither
                // box ever disappears and "short" stays visible underneath.
                HStack(spacing: 1) {
                    VStack(alignment: .leading) {
                        Text(L("page.containers.leadingAlign")).foregroundStyle(.palette.foreground)
                        Text(L("page.containers.short")).foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .border()

                    VStack(alignment: .center) {
                        Text(L("page.containers.centerAlign")).foregroundStyle(.palette.foreground)
                        Text(L("page.containers.short")).foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .border()

                    VStack(alignment: .trailing) {
                        Text(L("page.containers.trailingAlign")).foregroundStyle(.palette.foreground)
                        Text(L("page.containers.short")).foregroundStyle(.palette.foregroundSecondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ContainerTypesRow().equatable()
            SettingsAndAlignmentRow().equatable()
            // ProgressView used to live here; it now has its own demo page
            // (press the back-tick shortcut on the menu) covering both
            // determinate and indeterminate variants of every style.

            DemoSection(L("page.containers.section.collapsible")) {
                VStack(alignment: .leading) {
                    // The OUTER group's expansion is owned by this page, so the
                    // group and the button under it are two views of one truth:
                    // clicking either moves both. That is what `isExpanded:` is
                    // for — without it a group keeps its own state and nothing
                    // outside can open it.
                    DisclosureGroup(L("page.containers.paddingExamples"), isExpanded: $showDetails) {
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
                            DisclosureGroup(L("page.containers.disclosure.nested")) {
                                Text(L("page.containers.primaryText"))
                                    .foregroundStyle(.palette.foreground)
                                Text(L("page.containers.secondaryText"))
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
            DemoSection(L("page.containers.section.outline")) {
                OutlineGroup(outlineDemoTree, children: \.children) { node in
                    Text(verbatim: node.id)
                }
            }

            DemoSection(L("page.containers.section.appearance")) {
                Text(L("page.containers.borderStyleHelp")).foregroundStyle(.palette.foregroundSecondary)
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("menu.item.containers"))
        }
    }
}
