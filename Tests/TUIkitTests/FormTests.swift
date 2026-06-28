//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FormTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Form")
struct FormTests {
    private func lines(_ view: some View, width: Int = 50, height: Int = 20) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    // MARK: - Columns (default)

    @Test("Columns form right-aligns labels to a shared pillar")
    func columnsPillarAlignment() {
        let out = lines(
            Form {
                LabeledContent("Name", value: "Alice")
                LabeledContent("Email", value: "a@b.c")
            })
        let nameRow = out.first { $0.contains("Alice") } ?? ""
        let emailRow = out.first { $0.contains("a@b.c") } ?? ""
        // Pillar = widest label ("Email" = 5). "Name" (4) is right-aligned, so its
        // row gains a leading space; the values then start at the same column.
        #expect(nameRow.hasPrefix(" Name "))
        #expect(emailRow.hasPrefix("Email "))
        let aliceCol = nameRow.firstRange(of: "Alice").map { nameRow.distance(from: nameRow.startIndex, to: $0.lowerBound) }
        let valueCol = emailRow.firstRange(of: "a@b.c").map { emailRow.distance(from: emailRow.startIndex, to: $0.lowerBound) }
        #expect(aliceCol != nil && aliceCol == valueCol, "value column aligns: \(out)")
    }

    @Test("Form defaults to the columns style (no border)")
    func defaultStyleIsColumns() {
        let out = lines(
            Form {
                LabeledContent("Name", value: "Alice")
            }).joined(separator: "\n")
        #expect(out.contains("Name") && out.contains("Alice"))
        // Columns draws no box border.
        #expect(!out.contains("─") && !out.contains("│"))
    }

    // MARK: - Grouped

    @Test("Grouped form draws sections as bordered boxes")
    func groupedDrawsBoxes() {
        let out = lines(
            Form {
                Section("General") {
                    LabeledContent("Name", value: "Alice")
                }
            }
            .formStyle(.grouped)
        ).joined(separator: "\n")
        #expect(out.contains("General"))
        #expect(out.contains("Name") && out.contains("Alice"))
        // Grouped draws a border around the section's rows.
        #expect(out.contains("─") || out.contains("│"))
    }

    // MARK: - LabeledContent standalone

    @Test("LabeledContent renders its label and value standalone")
    func labeledContentStandalone() {
        let out = lines(LabeledContent("Version", value: "1.0.3")).joined(separator: "\n")
        #expect(out.contains("Version") && out.contains("1.0.3"))
    }

    // MARK: - Custom FormStyle

    @Test("A custom FormStyle.makeBody is used")
    func customFormStyle() {
        let out = lines(
            Form {
                LabeledContent("Name", value: "Alice")
            }
            .formStyle(BannerFormStyle())
        ).joined(separator: "\n")
        #expect(out.contains("== FORM =="))
    }

    // MARK: - Sections + varied controls

    @Test("Form sections render headers, varied controls, and full-width rows")
    func sectionsWithVariedControls() {
        let out = lines(
            Form {
                Section("Profile") {
                    LabeledContent("Name") { TextField("", text: .constant("Ada")) }
                    LabeledContent("Password") { SecureField("", text: .constant("x")) }
                }
                Section("Settings") {
                    LabeledContent("Theme") {
                        Picker("", selection: .constant(0)) {
                            Text("Light").tag(0)
                            Text("Dark").tag(1)
                        }
                    }
                    LabeledContent("Volume") { Slider(value: .constant(50.0), in: 0...100) }
                    LabeledContent("Count") { Stepper("", value: .constant(3), in: 0...10) }
                    Toggle("Push", isOn: .constant(true))   // native: box-first control column
                    Button("Sign Out") {}
                }
            },
            width: 60, height: 30
        ).joined(separator: "\n")

        for label in ["Profile", "Name", "Password", "Settings", "Theme", "Volume", "Count", "Push", "Sign Out"] {
            #expect(out.contains(label), "missing '\(label)' in:\n\(out)")
        }
    }

    // MARK: - macOS columns conventions

    @Test("A bare Toggle is box-first in the control column (its label is clickable)")
    func toggleBoxFirstInControlColumn() {
        let out = lines(Form { Toggle("Wi-Fi", isOn: .constant(true)) })
        let row = out.first { $0.contains("Wi-Fi") } ?? ""
        // Box first: the row leads with the checkbox glyph, not the label. (The
        // native Toggle's hit region — covering box, gap, and label — is what
        // makes the whole row clickable.)
        #expect(!row.hasPrefix("Wi-Fi"))
        #expect(row.contains("Wi-Fi"))
    }

    @Test("A Button is right-aligned in the columns layout")
    func buttonRightAlignedColumns() {
        let out = lines(
            Form {
                LabeledContent("Account email", value: "ada@example.com")
                Button("Sign Out") {}
            })
        let buttonRow = out.first { $0.contains("Sign Out") } ?? ""
        // Right-aligned to the content edge → leading whitespace before the button.
        #expect(buttonRow.hasPrefix(" "))
        #expect(buttonRow.contains("Sign Out"))
    }

    @Test("formRowAlignment(.leading) overrides a button's default right-alignment")
    func formRowAlignmentOverridesButton() {
        // A field gives the form a content width wider than the button, so a
        // right-aligned button gains leading whitespace and a left-aligned one
        // does not — letting us tell the two apart.
        let defaultOut = lines(
            Form {
                LabeledContent("Account email", value: "ada@example.com")
                Button("Reset") {}
            })
        let overriddenOut = lines(
            Form {
                LabeledContent("Account email", value: "ada@example.com")
                Button("Reset") {}.formRowAlignment(.leading)
            })
        let defaultRow = defaultOut.first { $0.contains("Reset") } ?? ""
        let overriddenRow = overriddenOut.first { $0.contains("Reset") } ?? ""
        // Default: right-aligned → leading whitespace. Override: left-aligned → the
        // button (its chrome) starts at column 0, so no leading whitespace.
        #expect(defaultRow.hasPrefix(" "), "default button should be right-aligned: \(defaultOut)")
        #expect(!overriddenRow.hasPrefix(" ") && overriddenRow.contains("Reset"),
                "overridden button should be left-aligned: \(overriddenOut)")
    }

    @Test("A columns section header is right-aligned to the pillar")
    func sectionHeaderRightAligned() {
        let out = lines(
            Form {
                Section("On") {
                    LabeledContent("Notifications", value: "all")
                }
            })
        // "On" (capital O) only appears in the header; the field row has "Notifications".
        let headerRow = out.first { $0.contains("On") && !$0.contains("Notifications") } ?? ""
        // Right-aligned to the "Notifications" pillar → leading whitespace.
        #expect(headerRow.hasPrefix(" "))
        #expect(headerRow.contains("On"))
    }

    @Test("A Toggle's click zone in a form covers its label (full row clickable)")
    func toggleClickZoneCoversLabel() {
        // A field label gives the toggle a non-zero control-column indent; the
        // toggle's native hit region (box + gap + label) must shift with it.
        let ctx = makeRenderContext(width: 50, height: 10) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let buffer = renderToBuffer(
            Form {
                LabeledContent("Account name", value: "ada")
                Toggle("Wi-Fi", isOn: .constant(true))
            },
            context: ctx)
        let toggleRow = buffer.lines.firstIndex { $0.stripped.contains("Wi-Fi") } ?? -1
        let stripped = toggleRow >= 0 ? buffer.lines[toggleRow].stripped : ""
        let labelCol = stripped.range(of: "Wi-Fi").map {
            stripped.distance(from: stripped.startIndex, to: $0.lowerBound)
        } ?? -1
        let covered = buffer.hitTestRegions.contains { region in
            region.offsetY <= toggleRow && toggleRow < region.offsetY + region.height
                && region.offsetX <= labelCol && labelCol < region.offsetX + region.width
        }
        #expect(toggleRow >= 0 && labelCol >= 0)
        #expect(covered, "a hit region should cover the label at row \(toggleRow), col \(labelCol)")
    }
}

/// A custom form style exercising ``FormStyle/makeBody(configuration:)``.
private struct BannerFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("== FORM ==")
            configuration.content
        }
    }
}
