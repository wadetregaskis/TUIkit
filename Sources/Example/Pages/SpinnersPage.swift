//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SpinnersPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A demo page showing all Spinner styles.
struct SpinnersPage: View {
    @AppStorage("spinners.editorStyle") private var editorStyle = "dots"
    @AppStorage("spinners.editorCustom") private var editorUsesCustom = false
    @AppStorage("spinners.editorFrames") private var editorFrames = "123432"
    @AppStorage("spinners.editorLabel") private var editorLabel = ""
    /// The edited colour, as hex — the same spelling the track editor and the
    /// ProgressView page persist theirs in. A six-choice picker was here before;
    /// a spinner's colour is an ordinary `Color`, so the ordinary editor for one
    /// is what belongs.
    @AppStorage("spinners.editorColour") private var editorColorHex = "FF00FF"
    /// Whether the spinner takes the theme's own accent instead — the default a
    /// `Spinner` has when nobody names a colour, and a state you can come back
    /// to rather than an approximation of it in the hex field.
    @AppStorage("spinners.editorThemeColour") private var editorUsesThemeColor = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // A twelve-row catalogue twenty-five columns wide, then an editor
            // eighty-five wide, one under the other: 45% of a wide terminal
            // used and the catalogue's own shape wasted. Preferred arrangement
            // first, then progressively narrower ones — the
            // `ViewThatFits(in: .horizontal)` shape the Animation page and the
            // track editor use.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    stylesCatalogue(columns: 2)
                    editorAndColour
                }
                HStack(alignment: .top, spacing: 4) {
                    stylesCatalogue(columns: 1)
                    editorAndColour
                }
                VStack(alignment: .leading, spacing: 1) {
                    stylesCatalogue(columns: 1)
                    editorAndColour
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
    /// Column count is a parameter rather than a second copy of the list: a
    /// spinner is a live animation, and two lists of twelve would be
    /// twenty-four clocks where twelve will do.
    @ViewBuilder
    private func stylesCatalogue(columns: Int) -> some View {
        // The catalogue's custom row IS the editor's frame field: one custom
        // spinner on the page, edited in one place, rather than a second one
        // frozen at whatever the field happened to say when this list was
        // written.
        let frames = editedFrames
        // The colour is part of each row's IDENTITY, not just of its drawing.
        // A row whose id does not move is a row the value memo may serve from
        // the last frame's buffer, and the colour it reads is captured from the
        // page rather than passed in as data — so without this the catalogue
        // went on showing the theme's accent while every other spinner on the
        // page had changed.
        let colorKey = editorUsesThemeColor ? "theme" : editorColorHex
        let styles: [CatalogueEntry] = [
            ("dots", SpinnerStyle.dots), ("line", .line), ("bouncing", .bouncing),
            ("pie", .pie), ("beachball", .beachball), ("box", .box), ("bars", .bars),
            ("blockWedge", .blockWedge), ("moon", .moon), ("earth", .earth),
            ("clock", .clock), ("custom(\"\(frames)\")", .custom(frames)),
        ].map { CatalogueEntry(name: $0.0, style: $0.1, colorKey: colorKey) }
        let perColumn = (styles.count + columns - 1) / columns
        DemoSection("page.spinners.styles") {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(0..<columns), id: \.self) { column in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(
                            Array(styles[
                                min(column * perColumn, styles.count)
                                    ..< min((column + 1) * perColumn, styles.count)])
                        ) { entry in
                            spinnerRow(entry.name, entry.style)
                        }
                    }
                }
            }
        }
    }

    /// The editor and the custom-colour example, which always travel together:
    /// both are about choosing how one spinner looks, and the second is the
    /// answer to a question the first raises.
    @ViewBuilder
    private var editorAndColour: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection("page.spinners.editorSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.spinners.editorHint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    editorControls
                    // The thing being edited, at the size it will be used —
                    // beside a label, which is how a spinner is nearly always
                    // written.
                    Spinner(editedLabel, style: editedStyle, color: editedColor)
                        .padding(.leading, 1)
                }
            }

            DemoSection("page.spinners.customColorSection") {
                // The editor's colour, beside a label, at the size a spinner is
                // nearly always used at. It used to be a literal magenta, which
                // said "a spinner can take a colour" and nothing about the one
                // being chosen two lines above.
                Spinner("page.spinners.installing", style: .bouncing, color: editedColor)
            }
        }
    }

    /// The editor's controls: the pickers on one row, the two free-text fields
    /// on another. Two rows rather than three columns because a `TextField`
    /// needs a caption above it (its title is a placeholder, as in SwiftUI, and
    /// vanishes the moment the field has anything in it) while a `Picker` draws
    /// its own label inline — so mixing them in one row leaves the row ragged.
    @ViewBuilder private var editorControls: some View {
        HStack(spacing: 3) {
            SpinnerStylePicker(titleKey: "page.spinners.editorStyle", selection: $editorStyle)
            Toggle("page.spinners.editorThemeColour", isOn: $editorUsesThemeColor)
            Toggle("page.spinners.editorUseCustom", isOn: $editorUsesCustom)
        }
        // The whole colour, not six of them: the same `ColorPicker` the Theme
        // page edits a palette with, disabled while the theme's accent is in
        // force so the control still says what the spinner is showing.
        ColorPicker("page.spinners.editorColour", selection: colorBinding)
            .disabled(editorUsesThemeColor)
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

    /// The edited colour as a binding the `ColorPicker` can drive, hex in the
    /// persisted store and a `Color` in the control.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color.hex(editorColorHex) ?? .magenta },
            set: { editorColorHex = GradientStopsCodec.encode([$0]) })
    }

    /// The frames the custom spinner runs — the field's, unless it is empty, in
    /// which case the sequence this page has always shown.
    private var editedFrames: String {
        editorFrames.isEmpty ? "123432" : editorFrames
    }

    private var editedStyle: SpinnerStyle {
        editorUsesCustom
            ? .custom(editedFrames)
            : (SpinnerStyleChoice(rawValue: editorStyle) ?? .dots).style
    }

    /// `nil` means "whatever a Spinner does by default", which is the theme's
    /// accent — an absence rather than a copy of it.
    private var editedColor: Color? {
        editorUsesThemeColor ? nil : Color.hex(editorColorHex)
    }

    private var editedLabel: String? {
        editorLabel.isEmpty ? nil : editorLabel
    }

    /// One row of the style catalogue. Its `id` carries the colour so a colour
    /// change moves it — see `stylesCatalogue(columns:)`.
    private struct CatalogueEntry: Identifiable {
        let name: String
        let style: SpinnerStyle
        let colorKey: String
        var id: String { "\(name)|\(colorKey)" }
    }

    /// A `[spinner  style-name]` row for the style catalogue, in the colour the
    /// editor is on — "apply to all the examples on the page" being what makes
    /// a colour choice something you can actually judge.
    ///
    /// - Note: the catalogue currently redraws a frame late: the rows are
    ///   rebuilt with the new colour (and the new frame sequence) but the
    ///   buffer on screen is the previous one until the page is left and
    ///   re-entered. Not this page's doing — the same lag appears with a plain
    ///   `Text` in the row — and tracked separately.
    @ViewBuilder
    private func spinnerRow(_ name: String, _ style: SpinnerStyle) -> some View {
        HStack(spacing: 1) {
            Spinner(style: style, color: editedColor)
            Text(name).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
