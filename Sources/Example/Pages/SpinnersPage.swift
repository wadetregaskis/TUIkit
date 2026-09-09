//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpinnersPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A demo page showing all Spinner styles.
struct SpinnersPage: View {
    @AppStorage("spinners.editorFrames") private var editorFrames = "123432"
    @AppStorage("spinners.editorLabel") private var editorLabel = ""
    /// The edited colour, as hex — the same spelling the track editor and the
    /// ProgressView page persist theirs in. A six-choice picker was here before;
    /// a spinner's colour is an ordinary `Color`, so the ordinary editor for one
    /// is what belongs.
    @AppStorage("spinners.editorColour") private var editorColorHex = "FF00FF"
    /// Whether the spinners take the theme's own accent instead — the default a
    /// `Spinner` has when nobody names a colour, and a state you can come back
    /// to rather than an approximation of it in the hex field.
    @AppStorage("spinners.editorThemeColour") private var editorUsesThemeColor = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // A twelve-row catalogue twenty-five columns wide, then the
            // customiser, one under the other: 45% of a wide terminal used and
            // the catalogue's own shape wasted. Preferred arrangement first,
            // then progressively narrower ones — the
            // `ViewThatFits(in: .horizontal)` shape the Animation page and the
            // track editor use.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    stylesCatalogue(columns: 2)
                    customiser
                }
                HStack(alignment: .top, spacing: 4) {
                    stylesCatalogue(columns: 1)
                    customiser
                }
                VStack(alignment: .leading, spacing: 1) {
                    stylesCatalogue(columns: 1)
                    customiser
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.spinners")
        }
    }

    /// The full style catalogue — every `SpinnerStyle` in declaration order,
    /// dealt into `columns` columns. The labels are the API case names (an API
    /// surface, left untranslated), like the ProgressView catalogue.
    ///
    /// This IS the page's set of examples, and the customiser edits all of it:
    /// a colour you can only see on one spinner is a colour you cannot judge.
    /// Column count is a parameter rather than a second copy of the list — a
    /// spinner is a live animation, and two lists of twelve would be
    /// twenty-four clocks where twelve will do.
    @ViewBuilder
    private func stylesCatalogue(columns: Int) -> some View {
        let color = editedColor
        let dealt = catalogueColumns(columns: columns, color: color)
        DemoSection("page.spinners.styles") {
            HStack(alignment: .top, spacing: 3) {
                ForEach(dealt) { column in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(column.entries) { entry in
                            spinnerRow(entry, color: color)
                        }
                    }
                }
            }
        }
    }

    /// The catalogue's rows, dealt into `columns` columns.
    ///
    /// Everything the customiser touches travels INSIDE the elements, and the
    /// columns are elements too. `ForEach`'s value memo keys on the element,
    /// and its documented hole is exactly the shape this used to be:
    /// `ForEach(0..<columns)` with the rows built from data captured outside
    /// the closure. The column's buffer was then reused for a column whose
    /// contents had changed — the catalogue went on showing the theme's accent,
    /// and the previous frame sequence, while every other spinner on the page
    /// had followed the editor.
    private func catalogueColumns(columns: Int, color: Color?) -> [CatalogueColumn] {
        let colorKey = color.map { String(describing: $0) } ?? "theme"
        let frames = editedFrames
        // The catalogue's custom row IS the customiser's frame and label
        // fields: one custom spinner on the page, edited in one place, rather
        // than a second one frozen at whatever the fields happened to say when
        // this list was written. It is the only row they reach, which is why it
        // is built apart from the eleven fixed ones.
        let styles: [CatalogueEntry] =
            SpinnerStyleChoice.allCases.map {
                CatalogueEntry(
                    name: $0.rawValue, style: $0.style, label: nil, colorKey: colorKey)
            }
            + [
                CatalogueEntry(
                    name: "custom(\"\(frames)\")", style: .custom(frames),
                    label: editedLabel, colorKey: colorKey)
            ]
        let perColumn = (styles.count + columns - 1) / columns
        return (0..<columns).map { column in
            CatalogueColumn(
                index: column,
                entries: Array(
                    styles[
                        min(column * perColumn, styles.count)
                            ..< min((column + 1) * perColumn, styles.count)]))
        }
    }

    /// Everything you can change about the spinners on the left.
    @ViewBuilder
    private var customiser: some View {
        DemoSection("page.spinners.editorSection") {
            VStack(alignment: .leading, spacing: 1) {
                // Wrapped, not run on: `ViewThatFits` chooses on IDEAL width,
                // so one long line of prose is enough on its own to rule out
                // every side-by-side arrangement of the page.
                Text("page.spinners.editorHint")
                    .frame(width: 44, alignment: .leading)
                    .foregroundStyle(.palette.foregroundSecondary)

                // Two states of one choice, so two radio buttons rather than a
                // checkbox: "theme accent" is not a modifier on the colour
                // below it, it is the alternative to it. As a `Toggle` the two
                // controls read as unrelated, and nothing said that switching
                // it off is what makes the colour take effect.
                RadioButtonGroup(selection: colorSourceBinding) {
                    RadioButtonItem(ColorSource.theme, "page.spinners.editorThemeColour")
                    RadioButtonItem(ColorSource.custom, "page.spinners.editorCustomColour") {
                        // The option's own content, so the group indents it to
                        // the label and disables it while the other option is
                        // chosen — the two together are what say "this is the
                        // colour that option means". It was a hand-written
                        // indent and a hand-written `disabled` beside the
                        // group, which is the same thing said twice and once
                        // wrong: the indent is the INDICATOR's width, not 2.
                        //
                        // Swatch only: the inline R/G/B sliders are ninety
                        // cells wide, which alone decided this page's layout —
                        // no side-by-side arrangement could fit, so the
                        // customiser fell below the catalogue. The swatch still
                        // focuses and still opens the full editor on Return,
                        // Space or a click.
                        ColorPicker("page.spinners.editorColour", selection: colorBinding)
                            .colorPickerChannels(.hidden)
                            .colorPickerLabelWidth(8)
                    }
                }

                customFields
            }
        }
    }

    /// The two fields that reach the `custom` row alone. Side by side, each
    /// under its own caption: a `TextField`'s title is a placeholder, as in
    /// SwiftUI, and vanishes the moment the field has anything in it.
    @ViewBuilder private var customFields: some View {
        HStack(alignment: .top, spacing: 3) {
            VStack(alignment: .leading, spacing: 0) {
                // A `.custom` spinner IS its frame sequence — one character per
                // frame — so this field is the whole of that API.
                caption("page.spinners.editorFrames")
                TextField("page.spinners.editorFrames", text: $editorFrames)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 0) {
                caption("page.spinners.editorLabel")
                TextField("page.spinners.editorLabel", text: $editorLabel)
                    .frame(width: 18)
            }
        }
    }

    /// A field's own label, in the page's quiet caption colour.
    private func caption(_ textKey: LocalizedStringKey) -> some View {
        Text(textKey).foregroundStyle(.palette.foregroundSecondary)
    }

    /// Where the spinners' colour comes from.
    private enum ColorSource: Hashable {
        case theme
        case custom
    }

    /// The radio group's selection, over the stored flag. Stored as the flag it
    /// has always been so the preference survives this page's rearrangement.
    private var colorSourceBinding: Binding<ColorSource> {
        Binding(
            get: { editorUsesThemeColor ? .theme : .custom },
            set: { editorUsesThemeColor = $0 == .theme })
    }

    /// The colour the store holds, however it happens to spell it.
    ///
    /// Read through the gradient codec, which takes both a bare `RRGGBB` and a
    /// positioned `RRGGBB@0.000` stop — the two spellings this key has had.
    /// `Color.hex` alone rejects the second, which is what broke: the picker's
    /// setter wrote a one-stop gradient while both readers expected bare hex,
    /// so touching the picker made the custom colour stop applying and left
    /// the radio saying "Custom colour" over spinners in the theme accent.
    private var storedColor: Color {
        GradientStopsCodec.decode(editorColorHex, fallback: Gradient(colors: [.magenta]))
            .stops.first?.color ?? .magenta
    }

    /// The edited colour as a binding the `ColorPicker` can drive, hex in the
    /// persisted store and a `Color` in the control. One colour, so one stop's
    /// worth of hex goes back.
    private var colorBinding: Binding<Color> {
        Binding(get: { storedColor }, set: { editorColorHex = GradientStopsCodec.hex($0) })
    }

    /// The frames the custom spinner runs — the field's, unless it is empty, in
    /// which case the sequence this page has always shown.
    private var editedFrames: String {
        editorFrames.isEmpty ? "123432" : editorFrames
    }

    /// `nil` means "whatever a Spinner does by default", which is the theme's
    /// accent — an absence rather than a copy of it.
    private var editedColor: Color? {
        editorUsesThemeColor ? nil : storedColor
    }

    private var editedLabel: String? {
        editorLabel.isEmpty ? nil : editorLabel
    }

    /// One row of the style catalogue. Its `id` carries everything the
    /// customiser can change about it, so a change moves it — see
    /// `stylesCatalogue(columns:)`.
    private struct CatalogueEntry: Identifiable, Equatable {
        let name: String
        let style: SpinnerStyle
        let label: String?
        let colorKey: String
        var id: String { "\(name)|\(label ?? "")|\(colorKey)" }

        /// The row is what its id says it is — which is what lets the value
        /// memo tell a changed row from an unchanged one.
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    /// One column of the catalogue, carrying its own rows.
    ///
    /// The column has to BE its contents rather than an index into them: an
    /// index never changes, so a memo keyed on one serves the column it built
    /// the first time, whatever the rows have become since.
    private struct CatalogueColumn: Identifiable, Equatable {
        let index: Int
        let entries: [CatalogueEntry]
        var id: String { "\(index)|\(entries.map(\.id).joined(separator: ","))" }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    /// A `[spinner  style-name]` row for the style catalogue, in the colour the
    /// customiser is on — "apply to all the examples on the page" being what
    /// makes a colour choice something you can actually judge.
    @ViewBuilder
    private func spinnerRow(_ entry: CatalogueEntry, color: Color?) -> some View {
        HStack(spacing: 1) {
            Spinner(entry.label, style: entry.style, color: color)
            Text(entry.name).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
