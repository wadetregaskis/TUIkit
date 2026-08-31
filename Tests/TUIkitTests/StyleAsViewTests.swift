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

    /// A flat fill and `.background(_:)` over the same rectangle must produce
    /// the same bytes.
    ///
    /// They are two code paths now — `Color`'s conformance lives in
    /// `TUIkitView`, which cannot reach `.background(_:)` — and the whole point
    /// of the original single path was that they could not disagree. This is
    /// what keeps that true.
    @Test("A colour fill is byte-identical to the same colour as a background")
    func fillMatchesTheBackgroundModifier() {
        for colour in [red, Color.rgb(0, 255, 0), Color.palette.accent] {
            let asView = render(colour, width: 7, height: 2)
            let asBackground = render(_StyleFillBlock().background(colour), width: 7, height: 2)
            #expect(
                asView == asBackground,
                "\(colour): \(asView.map(\.debugDescription)) vs \(asBackground.map(\.debugDescription))")
        }
    }

    /// A fill under a sibling in a `ZStack` shows everywhere the sibling draws
    /// nothing AND behind the cells it does draw: a glyph and a field are two
    /// statements, and a `Text` that sets only a foreground has said nothing
    /// about the field it lands on. This is the whole point of a fill as a
    /// view, and it did not work — the letters used to punch a hole in the red.
    @Test("A fill lies behind its ZStack siblings, glyph cells included")
    func fillShowsThroughGlyphCells() {
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
        #expect(
            backgrounds(lines[1]) == Array(repeating: "255;0;0", count: 10),
            "the glyphs punched a hole: \(lines[1].debugDescription)")
    }

    /// …and the sibling's own background still wins where it states one, since
    /// its escapes are the later statement about the same cells.
    ///
    /// The bare `Color` beside a generic sibling is also the shape that used to
    /// segfault the debug runtime, so this doubles as the regression test for
    /// the conformance living in `TUIkitView` — see `ColorAsView.swift`.
    @Test("A sibling that names its own background keeps it")
    func siblingBackgroundWins() {
        let lines = render(
            ZStack {
                red
                Text(verbatim: "hi").background(Color.rgb(0, 255, 0))
            }, width: 10, height: 3)
        let row = backgrounds(lines[1])
        #expect(row.count == 10)
        #expect(row[4] == "0;255;0" && row[5] == "0;255;0", "the sibling lost its own: \(row)")
        #expect(row[0] == "255;0;0" && row[9] == "255;0;0", "the fill stopped: \(row)")
    }
}

// MARK: - The background style

@MainActor
@Suite("Background style")
struct BackgroundStyleTests {

    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        return environment
    }

    private func context(width: Int, height: Int) -> RenderContext {
        let tui = TUIContext()
        var values = environment()
        values.focusManager = FocusManager()
        values.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: values, tuiContext: tui)
    }

    /// Nothing named, so the surface is the palette's own — a terminal's
    /// answer to SwiftUI's system background material.
    @Test("With nothing named, the background style is the palette's background")
    func defaultsToThePalette() {
        let values = environment()
        #expect(BackgroundStyle().paint(in: values) == .color(values.palette.background))
        #expect(
            BackgroundStyle().paint(in: values) == AnyShapeStyle(.background).paint(in: values),
            "the static member is the same style")
    }

    @Test("`backgroundStyle(_:)` is what `.background` then resolves to")
    func namedStyleWins() {
        var values = environment()
        values.backgroundStyle = .color(.rgb(9, 8, 7))
        #expect(BackgroundStyle().paint(in: values) == .color(.rgb(9, 8, 7)))

        let gradient = Gradient(colors: [.rgb(1, 0, 0), .rgb(0, 0, 1)])
        values.backgroundStyle = .gradient(GradientPaint(gradient, .linear(from: .top, to: .bottom)))
        #expect(BackgroundStyle().paint(in: values).solid == nil, "a gradient survives the slot")
    }

    /// The pair, end to end: one modifier names the surface, another paints it,
    /// and a plain `.background()` a whole subtree away picks it up.
    @Test("The style set above is the fill drawn below")
    func publishedStyleReachesTheFill() {
        let lines = renderToBuffer(
            VStack(spacing: 0) {
                Text(verbatim: "ab").background()
            }
            .backgroundStyle(Color.rgb(20, 30, 40)),
            context: context(width: 2, height: 1)
        ).lines
        #expect(lines.count == 1)
        #expect(lines[0].contains("48;2;20;30;40"), "the named surface: \(lines[0].debugDescription)")
    }

    @Test("A gradient background style paints a ramp under the words")
    func gradientBackgroundStyle() {
        let lines = renderToBuffer(
            Text(verbatim: "abcd").background()
                .backgroundStyle(
                    LinearGradient(
                        colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)], startPoint: .leading,
                        endPoint: .trailing)),
            context: context(width: 4, height: 1)
        ).lines
        #expect(lines.count == 1)
        #expect(lines[0].contains("48;2;255;0;0"), "the ramp's start")
        #expect(lines[0].contains("48;2;0;0;255"), "and its end: \(lines[0].debugDescription)")
    }

    /// With nothing named it still paints — the palette's background, which is
    /// what makes `.background()` worth writing over a dimmed backdrop.
    @Test("`background()` with nothing named paints the palette's background")
    func bareBackgroundPaints() {
        let palette = SystemPalette.green
        let lines = renderToBuffer(
            Text(verbatim: "x").background(), context: context(width: 1, height: 1)
        ).lines
        guard let components = palette.background.resolve(with: palette).rgbComponents else {
            Issue.record("the palette's background is not concrete")
            return
        }
        #expect(
            lines[0].contains("48;2;\(components.red);\(components.green);\(components.blue)"),
            "\(lines[0].debugDescription)")
    }
}
