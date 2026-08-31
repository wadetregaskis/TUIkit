//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StyleAsViewTests.swift
//
//  `Color` and the gradient types used where a VIEW is expected. SwiftUI's
//  `Color: View`, and the same for the four gradients — a style used as a view
//  fills the space it is offered.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("A style as a view")
struct StyleAsViewTests {

    private let red = Color.rgb(255, 0, 0)
    private let blue = Color.rgb(0, 0, 255)

    private func context(width: Int, height: Int) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    private func render(_ view: some View, width: Int, height: Int) -> [String] {
        renderToBuffer(view, context: context(width: width, height: height)).lines
    }

    /// The background of every visible CELL of a line, `nil` where none — so a
    /// run of four cells in one colour is four entries. Cells, not runs,
    /// because what a fill has to get right is which cells it covers.
    private func backgrounds(_ line: String) -> [String?] {
        var out: [String?] = []
        var current: String?
        var rest = Substring(line)
        while let escape = rest.firstIndex(of: "\u{1B}") {
            for character in rest[rest.startIndex..<escape] {
                out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
            }
            rest = rest[escape...]
            guard let end = rest.firstIndex(of: "m") else { break }
            let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<end]
            if let range = body.range(of: "48;2;") {
                current =
                    body[range.upperBound...].split(separator: ";").prefix(3)
                    .joined(separator: ";")
            } else if body == "0" {
                current = nil
            }
            rest = rest[rest.index(after: end)...]
        }
        for character in rest {
            out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
        }
        return out
    }

    // MARK: - Filling

    @Test("A colour fills the space it is offered")
    func colourFills() {
        let lines = render(red, width: 10, height: 3)
        #expect(lines.count == 3)
        for line in lines {
            #expect(
                backgrounds(line) == Array(repeating: "255;0;0", count: 10),
                "every cell of the row: \(line.debugDescription)")
            #expect(line.strippedLength == 10, "the full width")
        }
    }

    /// It claims the slack and never demands any — the ``Spacer`` contract, and
    /// what makes `HStack { Text("a"); Color.red; Text("b") }` behave.
    @Test("It takes the leftover space in a stack, and only the leftover")
    func fillsTheSlack() {
        let column = render(
            VStack(spacing: 0) {
                Text(verbatim: "hi")
                red
            }, width: 10, height: 3)
        #expect(column.count == 3)
        #expect(column[0].contains("hi"), "the text kept its row")
        let filled = Array(repeating: "255;0;0", count: 10)
        #expect(backgrounds(column[1]) == filled && backgrounds(column[2]) == filled)

        let row = render(
            HStack(spacing: 0) {
                Text(verbatim: "a")
                red
                Text(verbatim: "b")
            }, width: 8, height: 1)
        #expect(row.count == 1)
        #expect(row[0].strippedLength == 8)
        #expect(row[0].stripped == "a      b", "the fill took exactly the middle: |\(row[0].stripped)|")
    }

    @Test("A frame gives it exactly that size")
    func framedFill() {
        let lines = render(red.frame(width: 4, height: 2), width: 20, height: 9)
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.strippedLength == 4 })
    }

    /// The viewport bounds it: a fill inside a scroll view takes the height the
    /// scroll view is showing, not the extent it could scroll to.
    @Test("A scroll view does not let it balloon")
    func boundedInsideAScrollView() {
        let lines = render(ScrollView { red }, width: 6, height: 3)
        #expect(lines.count == 3, "got \(lines.count) rows")
    }

    // MARK: - The gradients

    @Test("A gradient view runs its ramp across the fill")
    func gradientFills() {
        let lines = render(
            LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing),
            width: 8, height: 2)
        #expect(lines.count == 2)
        let colours = backgrounds(lines[0])
        #expect(colours.count == 8, "a run per cell across the ramp: \(colours)")
        #expect(colours.first == "255;0;0" && colours.last == "0;0;255")
        #expect(Set(colours.compactMap { $0 }).count == 8, "every cell its own step")
        #expect(backgrounds(lines[1]) == colours, "both rows of a horizontal ramp agree")
    }

    /// The geometry resolves over the FILL's rectangle, which is what makes a
    /// radial gradient a ring rather than four unrelated stripes.
    @Test("A radial gradient view is symmetric about its centre")
    func radialFills() {
        let lines = render(
            RadialGradient(colors: [red, blue], center: .center, startRadius: 0, endRadius: 4),
            width: 9, height: 3)
        let middle = backgrounds(lines[1])
        #expect(middle.count == 9)
        #expect(middle == middle.reversed(), "not symmetric: \(middle)")
        #expect(middle[4] == "255;0;0", "the centre is the ramp's start")
    }

    // MARK: - Layering

    /// A fill under a sibling in a `ZStack` shows everywhere the sibling draws
    /// nothing — and NOT under the cells it does draw, because compositing is
    /// opaque per cell (`FrameBuffer.composited(with:at:)`, where the rule is
    /// deliberate: dialog interiors and the modal dim depend on blank cells
    /// painting). So the glyph cells take the sibling's own styling, with no
    /// background of their own, rather than the fill showing through them.
    @Test("A fill lies behind its ZStack siblings, opaquely per cell")
    func layeringIsOpaquePerCell() {
        let lines = render(
            ZStack {
                red
                Text(verbatim: "hi")
            }, width: 10, height: 3)
        #expect(lines.count == 3)
        #expect(
            backgrounds(lines[0]) == Array(repeating: "255;0;0", count: 10),
            "the row above the text is all fill")
        #expect(lines[1].contains("hi"), "the sibling drew")
        // Four filled cells, the two the glyphs took, then four more.
        #expect(
            backgrounds(lines[1]) == Array(repeating: "255;0;0", count: 4) + [nil, nil]
                + Array(repeating: "255;0;0", count: 4),
            "either side of the glyphs and not under them: \(lines[1].debugDescription)")
    }
}
