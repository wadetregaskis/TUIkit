//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SpacerRenderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Buffer-level render audit for `Spacer`. A standalone Spacer renders as
//  blank space (a single space-filled row by default, `minLength` rows when
//  given). Its real job is expanding inside a stack: these tests assert that
//  it pushes siblings apart along the stack's main axis and reports the
//  correct flexible-size contract.

import Testing

@testable import TUIkit

@MainActor
@Suite("Spacer rendering")
struct SpacerRenderTests {

    private func context(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    // MARK: - Standalone

    @Test("Default standalone spacer renders a single blank row")
    func defaultStandalone() {
        let buffer = renderToBuffer(Spacer(), context: context())
        #expect(buffer.lines.count == 1, "Default standalone spacer should be one row, got \(buffer.lines.count)")
        // Blank: no visible glyphs.
        #expect(buffer.lines[0].stripped.trimmingCharacters(in: .whitespaces).isEmpty,
                "Spacer row must be blank, got >>\(buffer.lines[0].stripped)<<")
    }

    @Test("minLength controls the standalone spacer's row count")
    func minLengthRows() {
        let buffer = renderToBuffer(Spacer(minLength: 3), context: context())
        #expect(buffer.lines.count == 3, "Spacer(minLength: 3) should render 3 rows, got \(buffer.lines.count)")
        #expect(buffer.lines.allSatisfy { $0.stripped.trimmingCharacters(in: .whitespaces).isEmpty },
                "Every spacer row must be blank")
    }

    // MARK: - sizeThatFits contract

    @Test("Spacer advertises full flexibility")
    func flexibleContract() {
        let size = Spacer().sizeThatFits(proposal: .unspecified, context: context())
        #expect(size.isWidthFlexible, "Spacer must be width-flexible")
        #expect(size.isHeightFlexible, "Spacer must be height-flexible")
        #expect(size.width == 0, "Default spacer has no minimum width, got \(size.width)")
        #expect(size.height == 0, "Default spacer has no minimum height, got \(size.height)")
    }

    @Test("minLength becomes the spacer's minimum size")
    func minLengthIsMinimum() {
        let size = Spacer(minLength: 4).sizeThatFits(proposal: .unspecified, context: context())
        #expect(size.width == 4, "minLength should set the minimum width, got \(size.width)")
        #expect(size.height == 4, "minLength should set the minimum height, got \(size.height)")
        #expect(size.isWidthFlexible && size.isHeightFlexible)
    }

    // MARK: - In an HStack

    @Test("Spacer pushes HStack siblings to opposite edges")
    func spacerInHStack() {
        let view = HStack(spacing: 0) {
            Text("L")
            Spacer()
            Text("R")
        }
        let buffer = renderToBuffer(view, context: context(width: 10, height: 1))
        #expect(buffer.lines.count == 1, "Single-row HStack expected, got \(buffer.lines.count)")
        let line = buffer.lines[0].stripped
        #expect(line.strippedLength == 10, "HStack with a spacer should fill the width, got \(line.strippedLength)")
        #expect(line.hasPrefix("L"), "Left text must sit at the left edge, got >>\(line)<<")
        #expect(line.hasSuffix("R"), "Right text must be pushed to the right edge, got >>\(line)<<")
        // The gap between them must be blank.
        let middle = String(line.dropFirst().dropLast())
        #expect(middle.trimmingCharacters(in: .whitespaces).isEmpty, "The spacer gap must be blank, got >>\(middle)<<")
    }

    // MARK: - In a VStack

    @Test("Spacer pushes VStack siblings to top and bottom")
    func spacerInVStack() {
        let view = VStack(spacing: 0) {
            Text("Top")
            Spacer()
            Text("Bottom")
        }
        let buffer = renderToBuffer(view, context: context(width: 10, height: 5))
        #expect(buffer.lines.count == 5, "VStack with a spacer should fill 5 rows, got \(buffer.lines.count)")
        // VStack centres horizontally by default, so the text may be padded;
        // what the spacer must guarantee is the vertical distribution: the
        // top text on the first row, the bottom text on the last row.
        #expect(buffer.lines.first?.stripped.contains("Top") == true,
                "First row must carry the top text, got >>\(buffer.lines.first?.stripped ?? "")<<")
        #expect(buffer.lines.last?.stripped.contains("Bottom") == true,
                "Last row must carry the bottom text, got >>\(buffer.lines.last?.stripped ?? "")<<")
        // The interior rows are the expanded spacer and must be blank.
        for row in buffer.lines[1..<4] {
            #expect(row.stripped.trimmingCharacters(in: .whitespaces).isEmpty,
                    "Interior spacer rows must be blank, got >>\(row.stripped)<<")
        }
    }
}
