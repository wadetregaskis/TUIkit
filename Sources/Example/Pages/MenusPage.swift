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
                    ValueDisplayRow(L("page.menus.chose"), pullDownChoice)
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
            .border(color: borderColor)
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
