//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextStylesPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Text styles demo page.
///
/// Shows various text styling options including:
/// - Basic styles (bold, italic, underline, etc.)
/// - Combined styles
/// - Special effects (blink, inverted)
/// - Cascading styles (container-level modifiers that apply to a whole subtree)
struct TextStylesPage: View {
    var body: some View {
        ScrollView {
            content
        }
        .appHeader {
            DemoAppHeader("Text Styles Demo")
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection("Basic Styles") {
                Text("Normal text - no styling applied")
                Text("Bold text").bold()
                Text("Italic text").italic()
                Text("Underlined text").underline()
                Text("Strikethrough text").strikethrough()
                Text("Dimmed text").dim()
            }

            DemoSection("Combined Styles") {
                Text("Bold + Italic").bold().italic()
                Text("Bold + Underline").bold().underline()
                Text("Bold + Color").bold().foregroundStyle(.palette.accent)
                Text("Italic + Dim").italic().dim()
                Text("All combined").bold().italic().underline().foregroundStyle(.palette.accent)
            }

            DemoSection("Special Effects") {
                Text("Blinking text (if terminal supports)").blink()
                Text("Inverted colors").inverted()
            }

            DemoSection("Font weight (.fontWeight)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "A terminal has only three weights, so the nine SwiftUI "
                            + "weights collapse: ultraLight/thin/light → dim, "
                            + "regular/medium → normal, semibold/bold/heavy/black → bold."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    Text("Thin").fontWeight(.thin)
                    Text("Regular").fontWeight(.regular)
                    Text("Semibold").fontWeight(.semibold)
                    Text("Black").fontWeight(.black)
                }
            }

            DemoSection("Truncation & Line Limits") {
                VStack(alignment: .leading, spacing: 1) {
                    let long = "A long line that will not fit inside a 30-column frame"
                    // Single-line truncation, cut at different ends (note the ellipsis).
                    // `lineLimit`/`truncationMode` are Text modifiers, so they come
                    // before `.frame` (which returns `some View`).
                    Text(long).lineLimit(1).truncationMode(.tail).frame(width: 30)
                    Text(long).lineLimit(1).truncationMode(.head).frame(width: 30)
                    Text(long).lineLimit(1).truncationMode(.middle).frame(width: 30)
                    // Multi-line wrap clamped to two lines.
                    Text(
                        "This paragraph wraps across several lines, but .lineLimit(2) "
                            + "clamps it to the first two and drops the rest of the text."
                    )
                    .lineLimit(2)
                    .frame(width: 46)
                }
            }

            DemoSection("Cascading styles — applied to a whole subtree") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "Container-level modifiers cascade to every descendant, "
                            + "like SwiftUI's — and a descendant can override."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    // .bold() on the VStack makes all three lines bold; the middle
                    // one opts out with .bold(false) (the closer modifier wins).
                    VStack(alignment: .leading) {
                        Text("Bold by inheritance")
                        Text("…but this line opts out").bold(false)
                        Text("Bold again")
                    }
                    .bold()

                    // A whole block uppercased via .textCase.
                    VStack(alignment: .leading) {
                        Text("uppercased as a block")
                        Text("via .textCase(.uppercase)")
                    }
                    .textCase(.uppercase)

                    // Role-scoped: dim ALL secondary-coloured text in this block,
                    // without touching the primary line.
                    VStack(alignment: .leading) {
                        Text("Primary text stays normal")
                        Text("Secondary text is dimmed by its role")
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                    .style(.semanticColor(.foregroundSecondary)) { $0.dim = true }
                }
            }

            DemoSection("Themeable chrome — section headers") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(
                        "A Section's header/footer styling is themeable via "
                            + ".style(.chrome(...)); headers are bold + dim by default."
                    )
                    .foregroundStyle(.palette.foregroundSecondary)

                    Section {
                        Text("Body line")
                    } header: {
                        Text("Default header")
                    }

                    // The same header, re-themed: uppercased and not bold.
                    Section {
                        Text("Body line")
                    } header: {
                        Text("Themed header")
                    }
                    .style(.chrome(.sectionHeader)) {
                        $0.textCase = .uppercase
                        $0.bold = false
                    }
                }
            }
        }
    }
}
