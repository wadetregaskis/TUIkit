//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenusPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Menus demo page.
///
/// The three menu idioms TUIkit ships today:
///   - `.contextMenu { … }` — a right-click (or Ctrl-click) pop-up of Buttons,
///     anchored at the click cell.
///   - `Menu(_:content:)` — a pull-down button: a collapsed label whose items
///     open over the page. Its label never changes and it holds no selection
///     (that is a `Picker`'s job) — SwiftUI draws exactly the same
///     distinction.
///   - `TextField` + `.textInputSuggestions { … }` — a combo box: free text
///     with a menu of suggestions beside it.
///
/// Menu-bar demos join them once menu bars exist.
struct MenusPage: View {
    @State private var contextAction: String = "—"
    @State private var pullDownChoice: String = "—"
    @State private var editor: String = ""
    @State private var showsHidden = false
    @State private var showsSizes = true
    @State private var showsPreviews = false

    /// The on/off marks the terminal can actually draw, so the sticky menu's
    /// rows are ticked with the same glyphs a `Toggle` would use rather than a
    /// hard-coded ✓ that some fonts lack.
    @Environment(\.toggleCharacterSet) private var marks

    /// Suggestions for the combo box. Editor names are proper nouns, so the
    /// menu reads the same in every language — the point on show is the
    /// control, not the words.
    private let editors = ["Vim", "Neovim", "Emacs", "Nano", "Helix", "Xcode", "VS Code"]

    /// The pull-down button's items — deliberately mixed lengths, so the
    /// pop-up visibly hugs its widest item.
    private var pullDownItems: [String] {
        [
            L("page.menus.pullDown.open"),
            L("page.menus.pullDown.duplicate"),
            L("page.menus.pullDown.rename"),
            L("page.menus.pullDown.export"),
        ]
    }

    var body: some View {
        ScrollView {
            content
        }
        .navigationTitle(L("page.menus.title"))
    }

    /// One row of the sticky menu: a `Button` whose label carries the flag's
    /// current mark, and which leaves the menu up when it fires.
    ///
    /// The mark comes from ``ToggleCharacterSet`` so it degrades with the
    /// terminal exactly as a `Toggle`'s does — and both marks of a set are the
    /// same cell width, so the labels stay in one column as the flags change.
    private func stickyItem(_ title: String, _ flag: Binding<Bool>) -> some View {
        Button(
            marks.openBracket
                + (flag.wrappedValue ? marks.onMark : marks.offMark)
                + marks.closeBracket + " " + title
        ) {
            flag.wrappedValue.toggle()
        }
        .menuActionDismissBehavior(.disabled)
    }

    /// The flags that are on, in menu order — or a dash when none are.
    private var showingSummary: String {
        let on = [
            (showsHidden, L("page.menus.sticky.hidden")),
            (showsSizes, L("page.menus.sticky.sizes")),
            (showsPreviews, L("page.menus.sticky.previews")),
        ].filter(\.0).map(\.1)
        return on.isEmpty ? "—" : on.joined(separator: ", ")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection(L("page.menus.contextSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.menus.contextInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    // TWO targets, because the gestures worth trying are the ones
                    // that involve a menu already being up: right-clicking the
                    // other box swaps to its menu in the one click, and
                    // right-clicking the same box re-opens its own where the
                    // click landed. Neither is visible with a single target.
                    // Their items differ — and so, deliberately, do their widths
                    // — so the read-out below says which menu you picked from.
                    // Opening either menu clears the read-out, so picking the
                    // same item twice running still reads as two choices
                    // rather than as nothing having happened.
                    HStack(spacing: 2) {
                        // The items are Buttons — SwiftUI's API — but they render
                        // as menu rows, and the pop-up hugs its widest item.
                        ContextMenuTarget(L("page.menus.contextTarget"))
                            .contextMenu {
                                Button(L("page.menus.context.cut")) {
                                    contextAction = L("page.menus.context.cut")
                                }
                                Button(L("page.menus.context.copy")) {
                                    contextAction = L("page.menus.context.copy")
                                }
                                Divider()
                                Button(L("page.menus.context.delete"), role: .destructive) {
                                    contextAction = L("page.menus.context.delete")
                                }
                            }
                        ContextMenuTarget(L("page.menus.contextTarget2"))
                            .contextMenu {
                                Button(L("page.menus.context.paste")) {
                                    contextAction = L("page.menus.context.paste")
                                }
                                Button(L("page.menus.context.selectAll")) {
                                    contextAction = L("page.menus.context.selectAll")
                                }
                                Divider()
                                Button(L("page.menus.context.properties")) {
                                    contextAction = L("page.menus.context.properties")
                                }
                            }
                    }
                    .onMenuOpen { contextAction = "—" }
                    Text(L("page.menus.contextSwapNote"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    ValueDisplayRow(L("page.menus.chose"), contextAction)
                }
            }

            DemoSection(L("page.menus.pullDownSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.menus.pullDownInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A pop-up Menu: the label is a collapsed control, and
                    // the items — plain Buttons, as in SwiftUI — open over the
                    // page and close again when one fires.
                    Menu(L("page.menus.pullDownTitle")) {
                        ForEach(pullDownItems, id: \.self) { item in
                            Button(item) { pullDownChoice = item }
                        }
                    }
                    // As above: the read-out clears as the menu opens, so
                    // choosing `Rename` twice shows two distinct choices.
                    .onMenuOpen { pullDownChoice = "—" }
                    ValueDisplayRow(L("page.menus.chose"), pullDownChoice)
                }
            }

            DemoSection(L("page.menus.stickySection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.menus.stickyInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A menu of SETTINGS rather than of commands. The
                    // `.menuActionDismissBehavior(.disabled)` is written on the
                    // three toggles (inside `stickyItem`), NOT on the `Menu`, so
                    // `Done` below them closes it the ordinary way — the modifier
                    // scopes to whatever subtree it is applied to.
                    Menu(L("page.menus.stickyTitle")) {
                        stickyItem(L("page.menus.sticky.hidden"), $showsHidden)
                        stickyItem(L("page.menus.sticky.sizes"), $showsSizes)
                        stickyItem(L("page.menus.sticky.previews"), $showsPreviews)
                        Divider()
                        Button(L("page.menus.sticky.done")) {}
                    }
                    ValueDisplayRow(L("page.menus.showing"), showingSummary)
                }
            }

            DemoSection(L("page.menus.boxSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.menus.boxInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField(L("page.menus.boxLabel"), text: $editor)
                        .textInputSuggestions {
                            ForEach(editors, id: \.self) { Text($0) }
                        }
                        .frame(width: 24)
                    ValueDisplayRow(
                        L("page.menus.typed"), editor.isEmpty ? "—" : editor)
                }
            }
        }
    }
}

// MARK: - Context-menu target

/// The `.contextMenu` target — and the answer to "my view is the focusable
/// thing here, so how does it show that it has the focus?".
///
/// `\.isFocused` says whether the focus stop that `.contextMenu` registered
/// currently holds the focus; `\.selectionEmphasis` turns that into the same
/// affordance every built-in control uses, on the same clock, honouring
/// whatever `.selectionIndicatorStyle` is in force — pulse, blink, or a static
/// accent. Neither decision is made here.
private struct ContextMenuTarget: View {
    let title: String

    @Environment(\.isFocused) private var isFocused
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .padding(.horizontal, 1)
            .border(borderColor)
    }

    /// The same two endpoints the framework's own focused frames breathe
    /// between — deliberately not `palette.border` at the dim end, or the
    /// bottom of every pulse would be indistinguishable from not being focused
    /// at all.
    private var borderColor: Color {
        guard isFocused else { return palette.border }
        return emphasis(true).color(
            dim: palette.accent.opacity(ViewConstants.focusBorderDim, over: palette.background),
            bright: palette.accent)
    }
}
