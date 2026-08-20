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
    @AppStorage("spinners.editorColour") private var editorColorName = "theme accent"

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // The full style catalogue — every SpinnerStyle in declaration
            // order. The labels are the API case names (an API surface, left
            // untranslated), like the ProgressView catalogue.
            DemoSection("page.spinners.styles") {
                VStack(alignment: .leading, spacing: 0) {
                    spinnerRow("dots", .dots)
                    spinnerRow("line", .line)
                    spinnerRow("bouncing", .bouncing)
                    spinnerRow("pie", .pie)
                    spinnerRow("beachball", .beachball)
                    spinnerRow("box", .box)
                    spinnerRow("bars", .bars)
                    spinnerRow("blockWedge", .blockWedge)
                    spinnerRow("moon", .moon)
                    spinnerRow("earth", .earth)
                    spinnerRow("clock", .clock)
                    spinnerRow("custom(\"123432\")", .custom("123432"))
                }
            }

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
                // A literal colour, deliberately distinct from the theme accent
                // (the default spinner colour) so the customisation is visible —
                // the green theme's `.palette.success` is nearly identical to its
                // `.palette.accent`, which made this look uncustomised.
                Spinner("page.spinners.installing", style: .bouncing, color: .magenta)
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.spinners")
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
            Picker("page.spinners.editorColour", selection: $editorColorName) {
                ForEach(Self.colourChoices, id: \.name) { choice in
                    Text(verbatim: choice.name).tag(choice.name)
                }
            }
            Toggle("page.spinners.editorUseCustom", isOn: $editorUsesCustom)
        }
        HStack(alignment: .top, spacing: 3) {
            VStack(alignment: .leading, spacing: 0) {
                // A `.custom` spinner IS its frame sequence — one character per
                // frame — so this field is the whole of that API.
                caption("page.spinners.editorFrames")
                TextField("page.spinners.editorFrames", text: $editorFrames)
                    .frame(width: 18)
                    .disabled(!editorUsesCustom)
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

    /// The colours the editor offers: the theme's own default first (so
    /// "unset" is a choice you can come back to), then a few unmistakable ones.
    private static let colourChoices: [(name: String, color: Color?)] = [
        ("theme accent", nil),
        ("magenta", .magenta),
        ("cyan", .cyan),
        ("yellow", .yellow),
        ("red", .red),
        ("green", .green),
    ]

    private var editedStyle: SpinnerStyle {
        editorUsesCustom
            ? .custom(editorFrames.isEmpty ? "123432" : editorFrames)
            : (SpinnerStyleChoice(rawValue: editorStyle) ?? .dots).style
    }

    private var editedColor: Color? {
        Self.colourChoices.first { $0.name == editorColorName }?.color
    }

    private var editedLabel: String? {
        editorLabel.isEmpty ? nil : editorLabel
    }

    /// A `[spinner  style-name]` row for the style catalogue.
    @ViewBuilder
    private func spinnerRow(_ name: String, _ style: SpinnerStyle) -> some View {
        HStack(spacing: 1) {
            Spinner(style: style)
            Text(name).foregroundStyle(.palette.foregroundSecondary)
        }
    }
}
