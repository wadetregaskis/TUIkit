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
///   - `Menu(_:content:)` — a pop-up button: a collapsed label whose items
///     open over the page.
///   - `TextField` + `.textInputSuggestions { … }` — a combo box: free text
///     with a menu of suggestions beside it.
///
/// Menu-bar demos join them once menu bars exist.
struct MenusPage: View {
    @State private var contextAction: String = "—"
    @State private var comboChoice: String = "—"
    @State private var editor: String = ""

    /// Suggestions for the combo box. Editor names are proper nouns, so the
    /// menu reads the same in every language — the point on show is the
    /// control, not the words.
    private let editors = ["Vim", "Neovim", "Emacs", "Nano", "Helix", "Xcode", "VS Code"]

    /// The combo button's items — deliberately mixed lengths, so the pop-up
    /// visibly hugs its widest item.
    private var comboItems: [String] {
        [
            L("page.menus.combo.open"),
            L("page.menus.combo.duplicate"),
            L("page.menus.combo.rename"),
            L("page.menus.combo.export"),
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
                    // The items are Buttons — SwiftUI's API — but they render as
                    // menu rows, and the pop-up hugs its widest item.
                    ContextMenuTarget()
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
                    ValueDisplayRow(L("page.menus.chose"), contextAction)
                }
            }

            DemoSection(L("page.menus.comboSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.menus.comboInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A pop-up Menu: the label is a collapsed control, and
                    // the items — plain Buttons, as in SwiftUI — open over the
                    // page and close again when one fires.
                    Menu(L("page.menus.comboTitle")) {
                        ForEach(comboItems, id: \.self) { item in
                            Button(item) { comboChoice = item }
                        }
                    }
                    ValueDisplayRow(L("page.menus.chose"), comboChoice)
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
    @Environment(\.isFocused) private var isFocused
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    var body: some View {
        Text(L("page.menus.contextTarget"))
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
