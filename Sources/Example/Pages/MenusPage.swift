//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenusPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Menus demo page.
///
/// The two menu idioms TUIkit ships today:
///   - `.contextMenu { … }` — a right-click (or Ctrl-click) pop-up of Buttons,
///     anchored at the click cell.
///   - `Menu(title:items:selection:)` — a combo button: a titled control that
///     pops its items open in place.
///
/// Menu-bar demos join them once menu bars exist.
struct MenusPage: View {
    @State private var contextAction: String = "—"
    @State private var comboSelection: Int = 0
    @State private var comboChoice: String = "—"

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
                    Text(L("page.menus.contextTarget"))
                        .padding(.horizontal, 1)
                        .border()
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
                    Menu(
                        title: L("page.menus.comboTitle"),
                        items: comboItems.map { MenuItem(label: $0, shortcut: nil) },
                        selection: $comboSelection,
                        onSelect: { index in
                            comboChoice = comboItems[index]
                        },
                        selectedColor: .palette.accent,
                        borderColor: .palette.border
                    )
                    ValueDisplayRow(L("page.menus.chose"), comboChoice)
                }
            }
        }
    }
}
