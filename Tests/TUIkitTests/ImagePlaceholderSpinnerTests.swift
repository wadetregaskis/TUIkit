//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImagePlaceholderSpinnerTests.swift
//
//  `.imagePlaceholderSpinner(style:color:)`: which spinner a loading `Image`
//  draws, and how it composes with `.imagePlaceholderSpinner(_:)`, which says
//  only whether one is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
@Suite("Image placeholder spinner style")
struct ImagePlaceholderSpinnerTests {

    /// A snapshot render with effects pinned off, as `ImageRenderTests` explains:
    /// a missing file's load could otherwise fail fast and land on the error path.
    private func render(_ view: some View, width: Int = 20, height: Int = 6) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        let tuiContext = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage())
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tuiContext
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    /// The glyphs of every frame the placeholder's run replays, without their styling.
    private func runGlyphs(_ buffer: FrameBuffer) -> [[String]] {
        buffer.animatedCells.map { $0.frames.map(\.stripped) }
    }

    private var image: Image { Image(.file("/nope.png")) }

    @Test("A .line placeholder spinner draws and animates .line's frames")
    func lineStyle() {
        let buffer = render(image.imagePlaceholderSpinner(style: .line))
        #expect(runGlyphs(buffer) == [SpinnerStyle.line.frames])
        // `.line`'s glyphs and `.dots`' share nothing, so this cannot pass on the default.
        #expect(buffer.lines.contains { $0.stripped.contains(SpinnerStyle.line.frames[0]) })
        #expect(!buffer.lines.contains { $0.stripped.contains("⠋") })
    }

    @Test("A colour given to the placeholder spinner is the colour it is drawn in")
    func colour() throws {
        let buffer = render(image.imagePlaceholderSpinner(color: .red))
        let red = Color.red.foregroundCodes().joined(separator: ";")
        let row = try #require(buffer.lines.first { $0.contains("⠋") })
        #expect(row.contains(red), "the glyph is red: \(row.debugDescription)")
    }

    @Test("imagePlaceholderSpinner() is the style overload: .dots, shown, even inside an outer false")
    func noArgumentsIsTheStyleOverload() {
        let buffer = render(image.imagePlaceholderSpinner().imagePlaceholderSpinner(false))
        #expect(runGlyphs(buffer) == [SpinnerStyle.dots.frames])
    }

    @Test("A style set inside an outer false shows the spinner")
    func innerStyleInsideOuterFalseShows() {
        let buffer = render(image.imagePlaceholderSpinner(style: .line).imagePlaceholderSpinner(false))
        #expect(runGlyphs(buffer) == [SpinnerStyle.line.frames])
    }

    @Test("An inner false hides the spinner an outer style chose")
    func innerFalseHides() {
        let buffer = render(
            image.imagePlaceholder("Wait…").imagePlaceholderSpinner(false)
                .imagePlaceholderSpinner(style: .line))
        #expect(buffer.animatedCells.isEmpty)
        let text = buffer.lines.map(\.stripped).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(text.map { $0.trimmingCharacters(in: .whitespaces) } == ["Wait…"])
    }

    @Test("An inner true keeps the style an outer modifier chose")
    func innerTrueKeepsTheStyle() {
        // The Bool overload sets only whether a spinner is shown. Were it to write the
        // whole value, this would fall back to `.dots`.
        let buffer = render(image.imagePlaceholderSpinner(true).imagePlaceholderSpinner(style: .line))
        #expect(runGlyphs(buffer) == [SpinnerStyle.line.frames])
    }

    @Test("Two descriptions are equal when they draw the same frames, at the same interval, in the same colour")
    func equalityIsByWhatIsDrawn() {
        // Two values built separately, so `==` is what decides and not identity.
        let first = ImagePlaceholderSpinner(style: .custom("ab"))
        let second = ImagePlaceholderSpinner(style: .custom("ab"))
        #expect(first == second)
        // `.line`'s frames as a `.custom` sequence step at `.custom`'s 7 ticks, not 8.
        #expect(
            ImagePlaceholderSpinner(style: .custom(SpinnerStyle.line.frames.joined()))
                != ImagePlaceholderSpinner(style: .line))
        #expect(ImagePlaceholderSpinner(style: .line) != ImagePlaceholderSpinner(style: .dots))
        #expect(ImagePlaceholderSpinner(color: .red) != ImagePlaceholderSpinner())
        #expect(ImagePlaceholderSpinner(isShown: false) != ImagePlaceholderSpinner())
    }
}
