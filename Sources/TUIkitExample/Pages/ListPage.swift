//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListPage.swift
//
//  Created by LAYERED.work
//  License: MIT

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
/// - Empty state placeholder
struct ListPage: View {
    @State var singleSelection: String?
    @State var multiSelection: Set<String> = []
    @State var transientSelection: String?

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
            DemoAppHeader("List Demo")
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            HStack(spacing: 2) {
                List(
                    "Single Selection",
                    selection: $singleSelection
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

                List(
                    "Multi Selection",
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

            DemoSection("Current Selections") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("Single:", singleSelection ?? "(none)")
                    ValueDisplayRow(
                        "Multi:",
                        multiSelection.isEmpty
                            ? "(none)"
                            : multiSelection.sorted().joined(separator: ", ")
                    )
                }
            }

            DemoSection(
                "Wheel scrolling — long list, no live selection"
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Scroll the wheel anywhere over the list below. "
                            + "It scrolls even when the list doesn't have "
                            + "focus — wheel events go to the viewport, "
                            + "not the selection. (Arrow keys still move "
                            + "the selection, but only when the list is "
                            + "focused.)"
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    List("\(longLines.count) lines") {
                        ForEach(longLines, id: \.self) { line in
                            Text(line)
                        }
                    }
                    .frame(height: 8)
                }
            }

            DemoSection(
                "Unfocused-selection visibility: .hidden"
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Click an item, then click somewhere else on the "
                            + "page so the list loses focus. The selection "
                            + "highlight disappears, but the underlying "
                            + "binding is still set — focus the list again "
                            + "(Tab / click) and the highlight returns."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    List(
                        "Transient picker",
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
                        "Bound value:",
                        transientSelection ?? "(none)"
                    )
                }
            }

            DemoSection("Empty state") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "A List with no rows shows a placeholder instead of a blank "
                            + "box. Customise the text with .listEmptyPlaceholder(_:)."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    // A genuinely empty list: an empty data set, so it has zero
                    // rows and shows the placeholder. (`{ EmptyView() }` would be
                    // treated as one blank row, not an empty list.)
                    List("Tasks") {
                        ForEach([String](), id: \.self) { task in
                            Text(task)
                        }
                    }
                    .listEmptyPlaceholder("No tasks yet — you're all caught up!")
                    .frame(height: 5)
                }
            }

            KeyboardHelpSection(
                "Navigation",
                shortcuts: [
                    "Use [↑/↓] to navigate items",
                    "Use [Home/End] to jump to first/last",
                    "Use [PageUp/PageDown] for fast scrolling",
                    "Use [Enter/Space] to select/deselect",
                    "Use [Tab] to switch between lists",
                    "Use the mouse wheel to scroll any list "
                        + "(works whether or not the list has focus, "
                        + "and whether or not it has a selection binding)",
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
