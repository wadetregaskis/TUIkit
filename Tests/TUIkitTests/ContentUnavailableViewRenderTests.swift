//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContentUnavailableViewRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

@MainActor
private func createTestContext(width: Int = 30, height: Int = 8) -> RenderContext {
    makeRenderContext(width: width, height: height)
}

@MainActor
private func strippedLines<V: View>(_ view: V, width: Int = 30, height: Int = 8) -> [String] {
    renderToBuffer(view, context: createTestContext(width: width, height: height))
        .lines.map { $0.stripped }
}

// MARK: - ContentUnavailableView Rendering Tests

@MainActor
@Suite("ContentUnavailableView rendering")
struct ContentUnavailableViewRenderTests {

    // MARK: Single label

    @Test("String title renders on a single centred line")
    func stringTitleSingleLine() {
        let lines = strippedLines(ContentUnavailableView("Empty"))

        #expect(lines.count == 1)
        #expect(lines[0].contains("Empty"))
        // Centred: the title is preceded by leading whitespace.
        #expect(lines[0].hasPrefix(" "))
        #expect(lines[0].trimmingCharacters(in: .whitespaces) == "Empty")
    }

    // MARK: Label + description

    @Test("Title and description stack with a single blank spacer between them")
    func titleAndDescription() {
        let lines = strippedLines(ContentUnavailableView("No Items", description: "Add some."))

        #expect(lines.count == 3)
        #expect(lines[0].trimmingCharacters(in: .whitespaces) == "No Items")
        // One blank spacer row (appendVertically spacing: 1).
        #expect(lines[1].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(lines[2].trimmingCharacters(in: .whitespaces) == "Add some.")
    }

    // MARK: Full (label + description + actions)

    @Test("Full layout stacks label, description and actions with blank spacers")
    func fullLayout() {
        let lines = strippedLines(ContentUnavailableView {
            Text("Title")
        } description: {
            Text("Desc")
        } actions: {
            Text("[A]")
        })

        #expect(lines.count == 5)
        #expect(lines[0].trimmingCharacters(in: .whitespaces) == "Title")
        #expect(lines[1].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(lines[2].trimmingCharacters(in: .whitespaces) == "Desc")
        #expect(lines[3].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(lines[4].trimmingCharacters(in: .whitespaces) == "[A]")
    }

    @Test("Label-only ViewBuilder renders just the label, no spacer rows")
    func labelOnlyViewBuilder() {
        let lines = strippedLines(ContentUnavailableView { Text("Only Label") })
        #expect(lines.count == 1)
        #expect(lines[0].trimmingCharacters(in: .whitespaces) == "Only Label")
    }

    // MARK: Search presets

    @Test("Search preset renders the canned label and description")
    func searchPreset() {
        let view = ContentUnavailableView<Text, Text, EmptyView>.search
        let lines = strippedLines(view, width: 40, height: 8)

        #expect(lines.count == 3)
        #expect(lines[0].trimmingCharacters(in: .whitespaces) == "No Results")
        #expect(lines[1].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(lines[2].trimmingCharacters(in: .whitespaces) == "Check the spelling or try a new search.")
    }

    @Test("Search-with-text interpolates the query into the title")
    func searchWithText() {
        let view = ContentUnavailableView<Text, Text, EmptyView>.search(text: "swift")
        let lines = strippedLines(view, width: 40, height: 8)

        #expect(lines[0].trimmingCharacters(in: .whitespaces) == "No Results for 'swift'")
        #expect(lines[2].trimmingCharacters(in: .whitespaces) == "Check the spelling or try a new search.")
    }

    // MARK: Empty

    @Test("Truly-empty content (EmptyView label) produces an empty buffer")
    func emptyViewLabelProducesNothing() {
        let buffer = renderToBuffer(ContentUnavailableView { EmptyView() }, context: createTestContext())
        #expect(buffer.isEmpty)
        #expect(buffer.height == 0)
    }

    @Test("An empty-string title (a blank Text label) draws no line")
    func emptyStringTitleProducesNothing() {
        // The label is Text("") which pads to blanks rather than zero length;
        // it must still be dropped (blank, not merely empty) so no row shows.
        let buffer = renderToBuffer(ContentUnavailableView(""), context: createTestContext())
        #expect(buffer.isBlank, "no visible content for an empty title")
        #expect(strippedLines(ContentUnavailableView("")).allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: Centring

    @Test("Content is horizontally centred via a uniform block shift")
    func uniformBlockCentring() {
        // Block centring applies one identical left-pad to every line, so a
        // title shorter than the description shares the description's offset.
        let buffer = renderToBuffer(
            ContentUnavailableView("Hi", description: "A longer description line"),
            context: createTestContext(width: 40, height: 8))
        let lines = buffer.lines

        let titleLeadingSpaces = lines[0].prefix { $0 == " " }.count
        let descLeadingSpaces = lines[2].prefix { $0 == " " }.count
        // Same uniform shift for both rows (not per-line centring).
        #expect(titleLeadingSpaces == descLeadingSpaces)
        #expect(titleLeadingSpaces > 0)
    }

    @Test("Wide context centres the block further right than a narrow one")
    func widerContextShiftsRight() {
        let narrow = renderToBuffer(ContentUnavailableView("Hi"), context: createTestContext(width: 20, height: 6))
        let wide = renderToBuffer(ContentUnavailableView("Hi"), context: createTestContext(width: 60, height: 6))
        let narrowPad = narrow.lines[0].prefix { $0 == " " }.count
        let widePad = wide.lines[0].prefix { $0 == " " }.count
        #expect(widePad > narrowPad)
    }

    @Test("No stray blank lines bookend the content")
    func noBookendBlankLines() {
        let lines = strippedLines(ContentUnavailableView("No Items", description: "Add some."))
        #expect(!lines.first!.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(!lines.last!.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
