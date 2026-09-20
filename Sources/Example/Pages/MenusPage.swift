//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        // `.appHeader`, not `.navigationTitle`: this page is not inside a
        // `NavigationStack`, so the title it set was drawn by nothing at all
        // and the page was the only one in the app with no header.
        .appHeader {
            DemoAppHeader("menu.item.menus")
        }
    }

    /// One row of the sticky menu: a `Toggle`, which inside a pop-up menu draws
    /// as a menu row carrying its own mark and leaves the menu up when it fires.
    ///
    /// This used to hand-roll the row as a `Button` whose label was a
    /// ``ToggleCharacterSet`` mark glued to the localized title, because a
    /// `Toggle` written here drew a checkbox the menu could not reach. The
    /// hand-rolled version also read the RAW `\.toggleCharacterSet`, so
    /// `.automatic` never resolved against the terminal the way a real toggle's
    /// mark does.
    private func stickyItem(_ titleKey: LocalizedStringKey, _ flag: Binding<Bool>) -> some View {
        Toggle(titleKey, isOn: flag)
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
            DemoSection("page.menus.contextSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.menus.contextInstruction")
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
                        ContextMenuTarget("page.menus.contextTarget")
                            .contextMenu {
                                Button("page.menus.context.cut") {
                                    contextAction = L("page.menus.context.cut")
                                }
                                Button("page.menus.context.copy") {
                                    contextAction = L("page.menus.context.copy")
                                }
                                Divider()
                                Button("page.menus.context.delete", role: .destructive) {
                                    contextAction = L("page.menus.context.delete")
                                }
                            }
                        ContextMenuTarget("page.menus.contextTarget2")
                            .contextMenu {
                                Button("page.menus.context.paste") {
                                    contextAction = L("page.menus.context.paste")
                                }
                                Button("page.menus.context.selectAll") {
                                    contextAction = L("page.menus.context.selectAll")
                                }
                                Divider()
                                Button("page.menus.context.properties") {
                                    contextAction = L("page.menus.context.properties")
                                }
                            }
                    }
                    .onMenuOpen { contextAction = "—" }
                    Text("page.menus.contextSwapNote")
                        .foregroundStyle(.palette.foregroundSecondary)
                    ValueDisplayRow("page.menus.chose", contextAction)
                }
            }

            DemoSection("page.menus.pullDownSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.menus.pullDownInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A pop-up Menu: the label is a collapsed control, and
                    // the items — plain Buttons, as in SwiftUI — open over the
                    // page and close again when one fires.
                    Menu("page.menus.pullDownTitle") {
                        ForEach(pullDownItems, id: \.self) { item in
                            Button(item) { pullDownChoice = item }
                        }
                    }
                    // As above: the read-out clears as the menu opens, so
                    // choosing `Rename` twice shows two distinct choices.
                    .onMenuOpen { pullDownChoice = "—" }
                    ValueDisplayRow("page.menus.chose", pullDownChoice)
                }
            }

            DemoSection("page.menus.stickySection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.menus.stickyInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A menu of SETTINGS rather than of commands. The
                    // `.menuActionDismissBehavior(.disabled)` is written on the
                    // three toggles (inside `stickyItem`), NOT on the `Menu`, so
                    // `Done` below them closes it the ordinary way — the modifier
                    // scopes to whatever subtree it is applied to.
                    Menu("page.menus.stickyTitle") {
                        stickyItem("page.menus.sticky.hidden", $showsHidden)
                        stickyItem("page.menus.sticky.sizes", $showsSizes)
                        stickyItem("page.menus.sticky.previews", $showsPreviews)
                        Divider()
                        Button("page.menus.sticky.done") {}
                    }
                    ValueDisplayRow("page.menus.showing", showingSummary)
                }
            }

            DemoSection("page.menus.boxSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.menus.boxInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField("page.menus.boxLabel", text: $editor)
                        .textInputSuggestions {
                            ForEach(editors, id: \.self) { Text($0) }
                        }
                        .frame(width: 24)
                    ValueDisplayRow(
                        "page.menus.typed", editor.isEmpty ? "—" : editor)
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
///
/// `\.appearsActive` is the one other thing to ask. `\.isFocused` stays true
/// while the terminal window is not the one taking input, because the focus is
/// still here when the user comes back; the built-in controls stop LOOKING
/// focused meanwhile, and this does the same by breathing only for
/// `isFocused && appearsActive`.
///
/// `animatedColor` rather than `emphasis(isFocused).color(…)`: the latter is
/// this tick's colour and reads the clock to get it, so advancing the pulse
/// means re-rendering the whole page. This hands `.border` every frame of the
/// cycle, and the border — which is the only thing that knows where its cells
/// are — leaves them for the run loop. See the `AnimatingYourOwnView` article.
private struct ContextMenuTarget: View {
    let title: LocalizedStringKey

    @Environment(\.isFocused) private var isFocused
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    init(_ title: LocalizedStringKey) {
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
    /// at all. Unfocused it is one frame, so the border simply sits still.
    ///
    /// Both ends from `breathEnds`, which spends a faded accent at each of them.
    /// A dim end composited over the page beside a bright end that kept the
    /// accent's alpha would breathe between two alphas, and a border at two
    /// alphas cannot be blended — see the `AnimatingYourOwnView` article.
    private var borderColor: AnimatedColor {
        guard isFocused && appearsActive else { return AnimatedColor(palette.border) }
        let ends = palette.accent.breathEnds(
            dimmedTo: ViewConstants.focusBorderDim, over: palette.background)
        return emphasis.animatedColor(true, dim: ends.dim, bright: ends.bright)
    }
}
