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
