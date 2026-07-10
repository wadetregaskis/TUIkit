//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

// MARK: - Demo Item

/// A simple item for list demos.
private struct FileItem: Identifiable {
    let id: String
    let name: String
    let size: String
    let icon: String

    static let sampleFiles: [Self] = [
        Self(id: "1", name: "README.md", size: "4.2 KB", icon: "📄"),
        Self(id: "2", name: "Package.swift", size: "1.8 KB", icon: "📦"),
        Self(id: "3", name: "Sources", size: "128 KB", icon: "📁"),
        Self(id: "4", name: "Tests", size: "64 KB", icon: "📁"),
        Self(id: "5", name: ".gitignore", size: "0.5 KB", icon: "📄"),
        Self(id: "6", name: "LICENSE", size: "1.1 KB", icon: "📄"),
        Self(id: "7", name: "docs", size: "256 KB", icon: "📁"),
        Self(id: "8", name: "plans", size: "32 KB", icon: "📁"),
        Self(id: "9", name: ".swiftlint.yml", size: "1.2 KB", icon: "⚙️"),
        Self(id: "10", name: ".github", size: "8 KB", icon: "📁"),
        Self(id: "11", name: "Makefile", size: "0.8 KB", icon: "📄"),
        Self(id: "12", name: ".claude", size: "16 KB", icon: "📁"),
    ]
}

// MARK: - List Page

/// List component demo page.
///
/// Shows interactive list features including:
/// - Single selection with binding
/// - Multi-selection with binding
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Mouse-wheel scrolling (independent of selection — wheel
///   scrolls the viewport, arrow keys move the selection)
/// - Unfocused selection visibility (`.automatic` vs `.hidden`)
/// - Scroll indicators
struct ListPage: View {
    @State var singleSelection: String?
    @State var multiSelection: Set<String> = []
    @State var transientSelection: String?
    @State var multiLineSelection: String?
    @State var browserURL: URL = FileBrowser.seedDirectory()

    var body: some View {
        // The page is taller than most terminals, so it's wrapped in a
        // ScrollView (greedy on both axes) — scroll the wheel, or Tab through the
        // controls and the viewport follows focus. The two selection lists below
        // are given a fixed height so they don't consume the whole viewport
        // (an unconstrained List fills its available height).
        ScrollView {
            content
        }
        .appHeader {
            DemoAppHeader(L("page.list.title"))
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            HStack(spacing: 2) {
                // A real file browser: single-click selects a row, double-click
                // opens a folder in place; the ".." row (↰) navigates up. The
                // per-row .onMouseEvent out-ranks the List's own click handling,
                // so it drives both selection and the double-click navigation.
                VStack(alignment: .leading, spacing: 0) {
                    Text(browserURL.path).dim()
                    List(L("page.list.singleSelection"), selection: $singleSelection) {
                        ForEach(FileBrowser.entries(at: browserURL)) { entry in
                            HStack(spacing: 1) {
                                Text(entry.icon)
                                Text(entry.name)
                            }
                            .onMouseEvent { event in
                                guard event.button == .left else { return false }
                                switch event.phase {
                                case .pressed:
                                    return true
                                case .released:
                                    if event.clickCount >= 2 {
                                        if entry.isDirectory { browserURL = entry.url }
                                    } else {
                                        singleSelection = entry.id
                                    }
                                    return true
                                default:
                                    return false
                                }
                            }
                        }
                    }
                    .frame(height: 10)
                }
                .frame(maxWidth: .infinity)

                List(
                    L("page.list.multiSelection"),
                    selection: $multiSelection
                ) {
                    ForEach(FileItem.sampleFiles) { file in
                        HStack(spacing: 1) {
                            Text(file.icon)
                            Text(file.name)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 10)
            }

            DemoSection(L("page.list.currentSelections")) {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow(L("page.list.single"), singleSelection ?? L("page.list.none"))
                    ValueDisplayRow(
                        L("page.list.multi"),
                        multiSelection.isEmpty
                            ? L("page.list.none")
                            : multiSelection.sorted().joined(separator: ", ")
                    )
                }
            }

            DemoSection(
                L("page.list.wheelSection")
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.list.wheelBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    List("\(longLines.count) \(L("page.list.linesSuffix"))") {
                        ForEach(longLines, id: \.self) { line in
                            Text(line)
                        }
                    }
                    .frame(height: 8)
                    .scrollbarVisibility(.visible)
                }
            }

            DemoSection(
                L("page.list.unfocusedSection")
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.list.unfocusedBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    List(
                        L("page.list.transientPicker"),
                        selection: $transientSelection
                    ) {
                        ForEach(FileItem.sampleFiles) { file in
                            HStack(spacing: 1) {
                                Text(file.icon)
                                Text(file.name)
                            }
                        }
                    }
                    .frame(height: 8)
                    .unfocusedSelectionVisibility(.hidden)

                    ValueDisplayRow(
                        L("page.list.boundValue"),
                        transientSelection ?? L("page.list.none")
                    )
                }
            }

            DemoSection(L("page.list.stylesSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.list.stylesBody"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    // Untitled lists so the styles read purely as their box
                    // chrome: `.plain` is borderless (rows flush, no walls),
                    // `.insetGrouped` wraps the rows in a bordered container.
                    // The label is a Text above each.
                    HStack(spacing: 2) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(".plain").dim()
                            List {
                                ForEach(FileItem.sampleFiles.prefix(3)) { file in
                                    HStack(spacing: 1) {
                                        Text(file.icon)
                                        Text(file.name)
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(".insetGrouped").dim()
                            List {
                                ForEach(FileItem.sampleFiles.prefix(3)) { file in
                                    HStack(spacing: 1) {
                                        Text(file.icon)
                                        Text(file.name)
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            // Rows can be any height — a `List` measures each row's rendered
            // height and windows/scrolls by lines, so a two-line cell just works.
            // 12 items in an 8-row frame → it scrolls, with a scrollbar.
            DemoSection(L("page.list.multiLineSection")) {
                List(selection: $multiLineSelection) {
                    ForEach(FileItem.sampleFiles) { file in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 1) {
                                Text("\(file.icon) \(file.name)").bold()
                                Spacer()
                                // An animated cell inside a scrolling List row —
                                // it must keep spinning even though the row is
                                // memoized (see SpinnerRowAnimationTests).
                                Spinner(style: .dots)
                            }
                            Text(file.size).foregroundStyle(.palette.foregroundSecondary)
                        }
                    }
                }
                .frame(height: 8)
                .scrollbarVisibility(.visible)
            }

            KeyboardHelpSection(
                L("page.list.navigation"),
                shortcuts: [
                    L("page.list.help.navigate"),
                    L("page.list.help.jump"),
                    L("page.list.help.fastScroll"),
                    L("page.list.help.select"),
                    L("page.list.help.switch"),
                    L("page.list.help.wheel"),
                ]
            )
        }
    }

    /// A long list of numbered lines used by the wheel-scrolling
    /// demo. Long enough that the viewport always overflows so
    /// wheel scrolling is visible.
    private var longLines: [String] {
        (1...100).map { "Line \($0) — scroll the wheel to move past me." }
    }
}
