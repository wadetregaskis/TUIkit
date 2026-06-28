//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Layout system demo page.
///
/// Shows various layout options including:
/// - VStack (vertical stacking)
/// - HStack (horizontal stacking)
/// - Spacer (flexible space)
/// - Padding and frame modifiers
struct LayoutPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.layout.section.vstack")) {
                VStack(spacing: 0) {
                    Text("\(L("page.layout.item")) 1")
                    Text("\(L("page.layout.item")) 2")
                    Text("\(L("page.layout.item")) 3")
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.hstack")) {
                HStack(spacing: 2) {
                    Text(L("page.layout.left"))
                    Text(L("page.layout.center"))
                    Text(L("page.layout.right"))
                }
                .border()
            }

            DemoSection(L("page.layout.section.spacer")) {
                HStack {
                    Text(L("page.layout.start"))
                    Spacer()
                    Text(L("page.layout.end"))
                }
                .border()
            }

            DemoSection(L("page.layout.section.paddingFrame")) {
                HStack(spacing: 2) {
                    VStack {
                        Text(".padding()").dim()
                        Text(L("page.layout.padded"))
                            .frame(width: 25, alignment: .center)
                            .padding(EdgeInsets(all: 1))
                            .border()  // Uses appearance default
                    }
                    VStack {
                        Text(".frame()").dim()
                        Text(L("page.layout.framed"))
                            .frame(width: 15, alignment: .center)
                            .border()  // Uses appearance default
                    }
                }
            }

            DemoSection(L("page.layout.section.viewThatFits")) {
                // A single row when there is room; the same items stacked
                // vertically when the terminal is too narrow for the row.
                ViewThatFits {
                    HStack(spacing: 2) {
                        Text("[ \(L("page.layout.profile")) ]")
                        Text("[ \(L("page.layout.settings")) ]")
                        Text("[ \(L("page.layout.signOut")) ]")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("[ \(L("page.layout.profile")) ]")
                        Text("[ \(L("page.layout.settings")) ]")
                        Text("[ \(L("page.layout.signOut")) ]")
                    }
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.zstack")) {
                // Children stack back-to-front; alignment positions them within
                // the union of their sizes. Here a label is centred over a band.
                ZStack(alignment: .center) {
                    Text(String(repeating: "▒", count: 28)).foregroundStyle(.palette.accent)
                    Text(" \(L("page.layout.onTop")) ").bold().inverted()
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.divider")) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("page.layout.above"))
                    Divider()
                    Text(L("page.layout.between"))
                    Divider(character: "═")
                    Text(L("page.layout.below"))
                }
                .border(color: .brightBlack)
            }

            DemoSection(L("page.layout.section.lazy")) {
                // Same API shape as VStack/HStack, but rows/columns are
                // realised lazily — only the part scrolled into view is
                // rendered. Handy inside a ScrollView with many children.
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.layout.lazyExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("\(L("page.layout.lazyRow")) 1")
                        Text("\(L("page.layout.lazyRow")) 2")
                        Text("\(L("page.layout.lazyRow")) 3")
                    }
                    .border(color: .brightBlack)

                    LazyHStack(spacing: 2) {
                        Text("\(L("page.layout.col")) 1")
                        Text("\(L("page.layout.col")) 2")
                        Text("\(L("page.layout.col")) 3")
                    }
                    .border(color: .brightBlack)
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.layout.header"))
        }
    }
}
