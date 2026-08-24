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

    /// A longer list for the multi-line follow-margin demo — enough rows that the
    /// viewport overflows substantially, so the difference between the edge,
    /// "2 lines early", and centred follow margins is clearly visible while
    /// paging the selection down through the list.
    static let manyFiles: [Self] = {
        let icons = ["📄", "📦", "📁", "⚙️", "🖼️", "🎬", "🎵", "🗜️"]
        let stems = ["report", "config", "assets", "module", "notes", "draft", "archive", "backup", "index", "manifest"]
        let exts = ["md", "swift", "txt", "json", "png"]
        return (1...40).map { i in
            Self(
                id: "m\(i)",
                name: "\(stems[i % stems.count])-\(i).\(exts[i % exts.count])",
                size: "\((i * 37) % 900 + 1).\(i % 10) KB",
                icon: icons[i % icons.count])
        }
    }()
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
    @State var treeSelection: String?
    @State var multiLineByLine = true
    /// Whether the multi-line demo's list has a selection at all — see the
    /// toggle's comment.
    @State var multiLineSelectable = true
    @State var multiLineFollowMargin = FollowMarginChoice.none.rawValue
    @State var browserURL: URL = FileBrowser.seedDirectory()
    @State private var searchQuery = ""
    @State private var editableItems = [
        "🍎 Apple", "🍌 Banana", "🍒 Cherry", "🍇 Grape", "🍑 Peach", "🍋 Lemon",
    ]
    @State private var editableSelection: Set<String> = []
    @State private var reorderFeedback = ReorderFeedbackChoice.live.rawValue

    private static let fruits = [
        "Apple", "Apricot", "Banana", "Blueberry", "Cherry",
        "Grape", "Lemon", "Mango", "Orange", "Peach",
    ]

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
            DemoAppHeader("menu.item.lists")
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.list.searchableSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.list.searchableExplain")
                        .foregroundStyle(.palette.foregroundSecondary)

                    let matches = searchQuery.isEmpty
                        ? Self.fruits
                        : Self.fruits.filter { $0.localizedCaseInsensitiveContains(searchQuery) }
                    Group {
                        if matches.isEmpty {
                            Text("page.list.searchableEmpty").dim()
                        } else {
                            List {
                                ForEach(matches, id: \.self) { Text($0) }
                            }
                            .frame(height: 6)
                        }
                    }
                    // The .searchable field filters `Self.fruits` above (app-driven).
                    .searchable(text: $searchQuery)
                }
            }

            DemoSection("page.list.editableSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.list.editableInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.rows.keyboardMoveHint")
                        .foregroundStyle(.palette.foregroundTertiary)
                        .dim()
                    Picker("page.list.reorderFeedback", selection: $reorderFeedback) {
                        ForEach(ReorderFeedbackChoice.allCases, id: \.rawValue) { choice in
                            Text(choice.label).tag(choice.rawValue)
                        }
                    }
                    // A SET binding: several rows can be selected, and then
                    // they reorder together — grab any one of them.
                    List(selection: $editableSelection) {
                        ForEach(editableItems, id: \.self) { Text($0) }
                            .onMove { editableItems.move(fromOffsets: $0, toOffset: $1) }
                            .onDelete { editableItems.remove(atOffsets: $0) }
                    }
                    .frame(height: 8)
                    // Drag a row and watch the difference: .live reorders under
                    // the cursor, .dimmed shows the row itself, faint, in the slot
                    // it would land in, .cursor leaves that slot empty and carries
                    // the row on the pointer instead.
                    .rowReorderFeedback(
                        ReorderFeedbackChoice(rawValue: reorderFeedback)?.feedback ?? .live)
                }
            }

            // The other way rows move: a value the app defines, dragged to
            // wherever accepts it. Reordering and moving between lists, in one
            // section — see RowTransferDemoSection for why it cannot be the
            // section above with extra modifiers.
            RowTransferDemoSection()

            // Bottom-aligned: the browser column is one line taller (its path
            // caption sits above the list), and both lists are equally tall —
            // aligning bottoms therefore aligns the LIST tops exactly.
            HStack(alignment: .bottom, spacing: 2) {
                // A real file browser: single-click (or Space) selects a row;
                // double-click OR Return/Enter on the focused row activates it
                // (`.onRowActivate`) — opening a folder in place; the ".." row
                // (↰) navigates up.
                VStack(alignment: .leading, spacing: 0) {
                    Text(browserURL.path).dim()
                    List("page.list.singleSelection", selection: $singleSelection) {
                        ForEach(FileBrowser.entries(at: browserURL)) { entry in
                            HStack(spacing: 1) {
                                Text(entry.icon)
                                Text(entry.name)
                            }
                        }
                    }
                    .onRowActivate { id in
                        if let entry = FileBrowser.entries(at: browserURL)
                            .first(where: { $0.id == id }), entry.isDirectory
                        {
                            browserURL = entry.url
                        }
                    }
                    .frame(height: 10)
                }
                .frame(maxWidth: .infinity)

                List(
                    "page.list.multiSelection",
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

            DemoSection("page.list.currentSelections") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("page.list.single", singleSelection ?? L("page.list.none"))
                    ValueDisplayRow(
                        "page.list.multi",
                        multiSelection.isEmpty
                            ? L("page.list.none")
                            : multiSelection.sorted().joined(separator: ", ")
                    )
                    Text("component.multiSelectHint")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
            }

            DemoSection(
                "page.list.unfocusedSection"
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.list.unfocusedBody")
                    .foregroundStyle(.palette.foregroundSecondary)

                    List(
                        "page.list.transientPicker",
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
                        "page.list.boundValue",
                        transientSelection ?? L("page.list.none")
                    )
                }
            }

            DemoSection("page.list.stylesSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.list.stylesBody")
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
            DemoSection("page.list.multiLineSection") {
                VStack(alignment: .leading, spacing: 0) {
                    // Line- vs row-centric scrolling, live: with two-line rows,
                    // a wheel tick moves three LINES (the top row can rest
                    // partially clipped) or three whole ROWS.
                    Toggle("demo.scrollGranularity.line", isOn: $multiLineByLine)
                    // Granularity is a property of a SCROLL, not of a
                    // selection: there is no such thing as half a selected row,
                    // so the cursor always moves whole rows whatever this says.
                    // Turning selection off is the only way to see that —
                    // otherwise every wheel tick is followed by the list
                    // scrolling to keep the cursor in view, and the two
                    // behaviours are impossible to tell apart.
                    Toggle("page.list.selectable", isOn: $multiLineSelectable)
                    // How early the list scrolls to follow the moving
                    // selection: at the edge (default), 2 lines early, or
                    // keeping the selection centred.
                    FollowMarginPicker(selection: $multiLineFollowMargin)
                        .disabled(!multiLineSelectable)
                    multiLineList
                }
            }

            // A tree as the list's OWN rows: every visible node is a row, so
            // the cursor walks nodes, the selection binding holds a node's id,
            // and scrolling addresses nodes. The triangle opens a branch; the
            // rest of the row belongs to the list, to select — and the keyboard
            // divides the same way, Space to the selection and Return (or
            // Right / Left) to the disclosure.
            DemoSection("page.list.treeSection") {
                List(outlineDemoTree, children: \.children, selection: $treeSelection) { node in
                    Text(verbatim: node.id)
                }
                .frame(height: 8)
            }

            KeyboardHelpSection(
                "page.list.navigation",
                shortcuts: [
                    "page.list.help.navigate",
                    "page.list.help.jump",
                    "page.list.help.fastScroll",
                    "page.list.help.select",
                    "page.list.help.tree",
                    "page.list.help.switch",
                    "page.list.help.wheel",
                ]
            )
        }
    }

    /// The multi-line cells list — extracted so the granularity toggle can
    /// re-apply `.scrollGranularity` to it without deepening the section body.
    @ViewBuilder private var multiLineList: some View {
        multiLineListBody
            // Five rows of content: 5 × 2 lines, plus the border's two. Four
            // would do to show scrolling, but not to show the follow margin —
            // in a three-row viewport "one row of margin" and "centred" pick
            // the same row, so the picker above looked inert between those two
            // settings.
            .frame(height: 12)
            .scrollIndicators(.visible)
            .scrollGranularity(multiLineByLine ? .line : .row)
            .scrollFollowMargin(
                FollowMarginChoice(rawValue: multiLineFollowMargin)?.margin ?? .none)
    }

    /// The list itself, with or without a selection binding — two different
    /// `List` initializers, so this is a branch rather than an optional.
    @ViewBuilder private var multiLineListBody: some View {
        if multiLineSelectable {
            List(selection: $multiLineSelection) { multiLineRows }
        } else {
            List { multiLineRows }
        }
    }

    @ViewBuilder private var multiLineRows: some View {
        ForEach(FileItem.manyFiles) { file in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 1) {
                    Text("\(file.icon) \(file.name)").bold()
                    Spacer()
                    // An animated cell inside a scrolling List row — it must
                    // keep spinning even though the row is memoized (see
                    // SpinnerRowAnimationTests).
                    Spinner(style: .dots)
                }
                Text(file.size).foregroundStyle(.palette.foregroundSecondary)
            }
        }
    }
}
