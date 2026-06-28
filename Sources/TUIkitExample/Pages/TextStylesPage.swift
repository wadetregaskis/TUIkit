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
            DemoAppHeader(L("page.textStyles.header"))
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection(L("page.textStyles.section.basic")) {
                Text(L("page.textStyles.normal"))
                Text(L("page.textStyles.bold")).bold()
                Text(L("page.textStyles.italic")).italic()
                Text(L("page.textStyles.underline")).underline()
                Text(L("page.textStyles.strikethrough")).strikethrough()
                Text(L("page.textStyles.dimmed")).dim()
            }

            DemoSection(L("page.textStyles.section.combined")) {
                Text(L("page.textStyles.boldItalic")).bold().italic()
                Text(L("page.textStyles.boldUnderline")).bold().underline()
                Text(L("page.textStyles.boldColor")).bold().foregroundStyle(.palette.accent)
                Text(L("page.textStyles.italicDim")).italic().dim()
                Text(L("page.textStyles.allCombined")).bold().italic().underline().foregroundStyle(.palette.accent)
            }

            DemoSection(L("page.textStyles.section.special")) {
                Text(L("page.textStyles.blinking")).blink()
                Text(L("page.textStyles.inverted")).inverted()
            }

            DemoSection(L("page.textStyles.section.fontWeight")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.fontWeightExplain"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    Text(L("page.textStyles.thin")).fontWeight(.thin)
                    Text(L("page.textStyles.regular")).fontWeight(.regular)
                    Text(L("page.textStyles.semibold")).fontWeight(.semibold)
                    Text(L("page.textStyles.black")).fontWeight(.black)
                }
            }

            DemoSection(L("page.textStyles.section.truncation")) {
                VStack(alignment: .leading, spacing: 1) {
                    let long = L("page.textStyles.longLine")
                    // Single-line truncation, cut at different ends (note the ellipsis).
                    // `lineLimit`/`truncationMode` are Text modifiers, so they come
                    // before `.frame` (which returns `some View`).
                    Text(long).lineLimit(1).truncationMode(.tail).frame(width: 30)
                    Text(long).lineLimit(1).truncationMode(.head).frame(width: 30)
                    Text(long).lineLimit(1).truncationMode(.middle).frame(width: 30)
                    // Multi-line wrap clamped to two lines.
                    Text(L("page.textStyles.wrapClamp"))
                    .lineLimit(2)
                    .frame(width: 46)
                }
            }

            DemoSection(L("page.textStyles.section.cascading")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.cascadingExplain"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    // .bold() on the VStack makes all three lines bold; the middle
                    // one opts out with .bold(false) (the closer modifier wins).
                    VStack(alignment: .leading) {
                        Text(L("page.textStyles.boldByInheritance"))
                        Text(L("page.textStyles.optsOut")).bold(false)
                        Text(L("page.textStyles.boldAgain"))
                    }
                    .bold()

                    // A whole block uppercased via .textCase.
                    VStack(alignment: .leading) {
                        Text(L("page.textStyles.uppercasedBlock"))
                        Text(L("page.textStyles.viaTextCase"))
                    }
                    .textCase(.uppercase)

                    // Role-scoped: dim ALL secondary-coloured text in this block,
                    // without touching the primary line.
                    VStack(alignment: .leading) {
                        Text(L("page.textStyles.primaryStaysNormal"))
                        Text(L("page.textStyles.secondaryDimmed"))
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                    .style(.semanticColor(.foregroundSecondary)) { $0.dim = true }
                }
            }

            DemoSection(L("page.textStyles.section.chrome")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.chromeExplain"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    Section {
                        Text(L("page.textStyles.bodyLine"))
                    } header: {
                        Text(L("page.textStyles.defaultHeader"))
                    }

                    // The same header, re-themed: uppercased and not bold.
                    Section {
                        Text(L("page.textStyles.bodyLine"))
                    } header: {
                        Text(L("page.textStyles.themedHeader"))
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
