//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextStylesPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Text styles demo page.
///
/// Shows various text styling options including:
/// - Basic styles (bold, italic, underline, etc.)
/// - Combined styles
/// - Special effects (blink, inverted)
/// - Cascading styles (container-level modifiers that apply to a whole subtree)
struct TextStylesPage: View {
    /// The live fade for the opacity demo, so it can be watched moving rather
    /// than only compared at fixed steps.
    @State private var opacity = 0.5

    var body: some View {
        ScrollView {
            content
        }
        .appHeader {
            DemoAppHeader(L("menu.item.textStyles"))
        }
    }

    /// A left-aligned label followed by a value view (a `Text(_:format:)`).
    @ViewBuilder private func formatRow<V: View>(
        _ label: String, @ViewBuilder value: () -> V
    ) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.palette.foregroundSecondary).frame(width: 16)
            value()
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

            DemoSection(L("page.textStyles.section.format")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.formatExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    // Each right-hand view IS a Text(value, format:) rendering.
                    formatRow(".percent") { Text(0.5, format: .percent) }
                    formatRow(".number") { Text(1_234_567, format: .number) }
                    formatRow(".currency(USD)") { Text(1299.99, format: .currency(code: "USD")) }
                }
            }

            DemoSection(L("page.textStyles.section.locale")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.localeExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    // The same value under three locales (via the format style's own
                    // locale). The \.locale environment re-locales Table/List number
                    // chrome the same way.
                    formatRow("en_US") { Text(1_234_567, format: .number.locale(Locale(identifier: "en_US"))) }
                    formatRow("de_DE") { Text(1_234_567, format: .number.locale(Locale(identifier: "de_DE"))) }
                    formatRow("fr_FR") { Text(1_234_567, format: .number.locale(Locale(identifier: "fr_FR"))) }
                }
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

            DemoSection(L("page.textStyles.section.font")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.fontExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    // Each style renders its OWN name, so the collapse onto
                    // three tiers is visible rather than described — and so is
                    // the fact that none of them changes a cell count.
                    Text(verbatim: ".largeTitle").font(.largeTitle)
                    Text(verbatim: ".title").font(.title)
                    Text(verbatim: ".title2").font(.title2)
                    Text(verbatim: ".title3").font(.title3)
                    Text(verbatim: ".headline").font(.headline)
                    Text(verbatim: ".subheadline").font(.subheadline)
                    Text(verbatim: ".body").font(.body)
                    Text(verbatim: ".callout").font(.callout)
                    Text(verbatim: ".footnote").font(.footnote)
                    Text(verbatim: ".caption").font(.caption)
                    Text(verbatim: ".caption2").font(.caption2)

                    // The axes that survive the medium, composed onto a style.
                    Text(L("page.textStyles.fontAxes"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(verbatim: ".caption.weight(.bold)").font(.caption.weight(.bold))
                    Text(verbatim: ".headline.bold(false)").font(.headline.bold(false))
                    Text(verbatim: ".headline.italic()").font(.headline.italic())

                    // The mapping is a default, so a theme can redefine one
                    // style without touching the others.
                    Text(L("page.textStyles.fontThemed"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    VStack(alignment: .leading) {
                        Text(verbatim: ".headline").font(.headline)
                        Text(verbatim: ".caption").font(.caption)
                    }
                    .style(.font(.headline)) { $0.underline = true }
                }
            }

            DemoSection(L("page.textStyles.section.truncation")) {
                VStack(alignment: .leading, spacing: 1) {
                    let long = L("page.textStyles.longLine")
                    // Single-line truncation, cut at different ends (note the ellipsis).
                    // `lineLimit`/`truncationMode` exist on both `Text` and `View`;
                    // written directly on a `Text` they bind to the `Text` ones, which
                    // is why they can come before `.frame` (which returns `some View`).
                    // The cascading forms are demoed in the next section.
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

                    // .lineLimit(2) on the VStack caps both paragraphs; the second
                    // opts back out with .lineLimit(nil), which means "no limit" —
                    // not "no opinion", or an inherited cap could never be lifted.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("page.textStyles.cappedByInheritance"))
                        Text(L("page.textStyles.uncapped")).lineLimit(nil)
                    }
                    .lineLimit(2)
                    .frame(width: 46)

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

            DemoSection(L("page.textStyles.section.concatenation")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.concatExplain"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    // Three fragments, three styles, one Text.
                    Text(L("page.textStyles.concatLabel")).bold()
                        + Text(L("page.textStyles.concatValue"))
                            .foregroundStyle(.palette.accent)
                        + Text(L("page.textStyles.concatNote")).dim()

                    // The same thing narrow enough to wrap: the break falls
                    // wherever the words need it, including inside a fragment,
                    // and each fragment keeps its styling on every line it
                    // reaches. An HStack of three Texts could not do that.
                    (Text(L("page.textStyles.concatLabel")).bold()
                        + Text(L("page.textStyles.concatLong"))
                            .foregroundStyle(.palette.accent))
                        .frame(width: 34)

                    // A modifier on the RESULT is the base beneath each
                    // fragment's own attributes — the first stays bold.
                    (Text(L("page.textStyles.concatLabel")).bold()
                        + Text(L("page.textStyles.concatValue")))
                        .italic()
                }
            }

            DemoSection(L("page.textStyles.section.opacity")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.textStyles.opacityExplain"))
                    .foregroundStyle(.palette.foregroundSecondary)

                    // One modifier fades a whole subtree — text, colours and
                    // controls alike — with each colour blended toward the
                    // background rather than replaced by a single grey.
                    Slider(value: $opacity, in: 0...1)
                    .frame(width: 40)

                    VStack(alignment: .leading) {
                        Text(L("page.textStyles.opacityHeading")).bold()
                        .foregroundStyle(.palette.error)
                        Text(L("page.textStyles.opacityBody"))
                        Text(L("page.textStyles.opacityAccent"))
                        .foregroundStyle(.palette.accent)
                    }
                    .opacity(opacity)

                    // A fixed ramp beside it: the same line at four fades, so
                    // the hues can be compared against each other directly.
                    HStack(spacing: 2) {
                        ForEach([1.0, 0.66, 0.33, 0.0], id: \.self) { step in
                            Text(L("page.textStyles.opacitySwatch"))
                            .foregroundStyle(.palette.success)
                            .opacity(step)
                        }
                    }
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
