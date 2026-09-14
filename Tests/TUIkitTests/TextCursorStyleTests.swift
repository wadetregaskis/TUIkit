//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextCursorStyleTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@Suite("TextCursorStyle")
struct TextCursorStyleTests {
    // MARK: - Shape Character Tests

    @Test("Block shape returns full block character")
    func blockShapeCharacter() {
        #expect(TextCursorStyle.Shape.block.character == "█")
    }

    @Test("Bar shape returns a left-edge insertion bar")
    func barShapeCharacter() {
        #expect(TextCursorStyle.Shape.bar.character == "▎")
    }

    @Test("Underscore shape returns lower block")
    func underscoreShapeCharacter() {
        #expect(TextCursorStyle.Shape.underscore.character == "▁")
    }

    // MARK: - Default Values

    @Test("Default style uses block shape with pulse animation")
    func defaultStyle() {
        let style = TextCursorStyle()
        #expect(style.shape == .block)
        #expect(style.animation == .pulse)
    }

    /// The presets are named for a shape, not an animation, so each takes the
    /// default animation rather than picking one of its own.
    @Test("Static block convenience uses block shape with the default pulse")
    func staticBlockConvenience() {
        let style = TextCursorStyle.block
        #expect(style.shape == .block)
        #expect(style.animation == .pulse)
    }

    @Test("Static bar convenience uses bar shape with the default pulse")
    func staticBarConvenience() {
        let style = TextCursorStyle.bar
        #expect(style.shape == .bar)
        #expect(style.animation == .pulse)
    }

    @Test("Static underscore convenience uses underscore shape with the default pulse")
    func staticUnderscoreConvenience() {
        let style = TextCursorStyle.underscore
        #expect(style.shape == .underscore)
        #expect(style.animation == .pulse)
    }

    // MARK: - Custom Initialization

    @Test("Custom style with bar and blink")
    func customStyleBarBlink() {
        let style = TextCursorStyle(shape: .bar, animation: .blink)
        #expect(style.shape == .bar)
        #expect(style.animation == .blink)
    }

    @Test("Custom style with underscore and no animation")
    func customStyleUnderscoreNone() {
        let style = TextCursorStyle(shape: .underscore, animation: .none)
        #expect(style.shape == .underscore)
        #expect(style.animation == .none)
    }

    // MARK: - Equatable

    @Test("Styles with same values are equal")
    func equalityWithSameValues() {
        let style1 = TextCursorStyle(shape: .bar, animation: .blink)
        let style2 = TextCursorStyle(shape: .bar, animation: .blink)
        #expect(style1 == style2)
    }

    @Test("Styles with different shapes are not equal")
    func inequalityWithDifferentShapes() {
        let style1 = TextCursorStyle(shape: .block, animation: .pulse)
        let style2 = TextCursorStyle(shape: .bar, animation: .pulse)
        #expect(style1 != style2)
    }

    @Test("Styles with different animations are not equal")
    func inequalityWithDifferentAnimations() {
        let style1 = TextCursorStyle(shape: .block, animation: .pulse)
        let style2 = TextCursorStyle(shape: .block, animation: .blink)
        #expect(style1 != style2)
    }

    // MARK: - Shape CaseIterable

    @Test("Shape has exactly three cases")
    func shapeHasThreeCases() {
        #expect(TextCursorStyle.Shape.allCases.count == 3)
    }

    @Test("Shape cases are block, bar, underscore")
    func shapeCasesCorrect() {
        let cases = TextCursorStyle.Shape.allCases
        #expect(cases.contains(.block))
        #expect(cases.contains(.bar))
        #expect(cases.contains(.underscore))
    }

    // MARK: - Animation CaseIterable

    @Test("Animation has exactly three cases")
    func animationHasThreeCases() {
        #expect(TextCursorStyle.Animation.allCases.count == 3)
    }

    @Test("Animation cases are none, blink, pulse")
    func animationCasesCorrect() {
        let cases = TextCursorStyle.Animation.allCases
        #expect(cases.contains(.none))
        #expect(cases.contains(.blink))
        #expect(cases.contains(.pulse))
    }

    // MARK: - Environment Default

    @Test("Environment default is block with pulse")
    func environmentDefaultValue() {
        let env = EnvironmentValues()
        let style = env.textCursorStyle
        #expect(style.shape == .block)
        #expect(style.animation == .pulse)
    }

    // MARK: - What an unstyled field draws

    /// The caret run a focused view hands over, with nothing else on the page.
    @MainActor
    private func caretRun(_ view: some View) -> AnimatedCellRun? {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 6)).animatedCells.first
    }

    /// The environment's default decides what a field with no `.textCursor` draws,
    /// so this is pinned on the rendered caret rather than on the key: every caret
    /// with no style set runs the pulse's cycle — its frame count and its frame
    /// duration at the caret's speed — and draws exactly the frames an explicit
    /// `.pulse` draws.
    @Test("An unstyled field's caret pulses")
    @MainActor
    func unstyledCaretPulses() throws {
        let speed = EnvironmentValues().indicatorAnimationSpeeds.speed(for: .textCursor)
        let pulse = CursorTimer.cycleLayout(of: .pulse, speed: speed)
        #expect(pulse.frameCount > 2, "the premise: a pulse is not a blink's two frames")
        let text = Binding.constant("Ada")
        let fields: [(String, AnyView, AnyView)] = [
            (
                "TextField", AnyView(TextField("Name", text: text)),
                AnyView(TextField("Name", text: text).textCursor(.block, animation: .pulse))
            ),
            (
                "SecureField", AnyView(SecureField("Password", text: text)),
                AnyView(SecureField("Password", text: text).textCursor(.block, animation: .pulse))
            ),
            (
                "TextEditor", AnyView(TextEditor(text: text)),
                AnyView(TextEditor(text: text).textCursor(.block, animation: .pulse))
            ),
        ]
        for (name, unstyled, pulsing) in fields {
            let run = try #require(caretRun(unstyled), "\(name): a focused field hands over its caret")
            #expect(run.frames.count == pulse.frameCount, "\(name): \(run.frames.count) frames")
            #expect(run.frameTicks == pulse.timing.frameTicks, "\(name): \(run.frameTicks) ticks")
            #expect(run.frames == caretRun(pulsing)?.frames, "\(name): not the explicit pulse's frames")
        }
    }

    /// `.textCursor(_:animation:)`'s default, `TextCursorStyle`'s and the
    /// shape-named presets' are one default, not three that happen to agree today.
    @Test("The shape modifier's default animation is the presets' animation")
    @MainActor
    func shapeModifierMatchesPresets() {
        let text = Binding.constant("Ada")
        let presets: [(TextCursorStyle.Shape, TextCursorStyle)] = [
            (.block, .block), (.bar, .bar), (.underscore, .underscore),
        ]
        for (shape, preset) in presets {
            let byShape = caretRun(TextField("Name", text: text).textCursor(shape))
            let byPreset = caretRun(TextField("Name", text: text).textCursor(preset))
            #expect(byShape != nil, "\(shape): the caret animates")
            #expect(byShape?.frames == byPreset?.frames, "\(shape)")
            #expect(byShape?.frameTicks == byPreset?.frameTicks, "\(shape)")
        }
    }

    // MARK: - Over-the-top rendering (TextField)

    @Test("Thin field carets draw over the character, not in place of it")
    @MainActor
    func fieldCaretsPreserveContent() {
        func render(_ shape: TextCursorStyle.Shape) -> String {
            let context = makeRenderContext(width: 20, height: 3) { env, _ in
                env.textCursorStyle = TextCursorStyle(shape: shape, animation: .none)
                env.focusManager = FocusManager()
            }
            let field = TextField("", text: .constant("hi")).focusID("caret-field")
            _ = renderToBuffer(field, context: context)  // register focus
            context.environment.focusManager?.focus(id: "caret-field")
            return renderToBuffer(field, context: context).lines.first ?? ""
        }

        // A fresh field's caret sits at the END of "hi", over a space —
        // the standalone shape glyph territory. The text must be intact
        // with the caret appended after it (the over-a-character cases are
        // pinned by the TextEditor test, whose caret starts at position 0).
        let underscore = render(.underscore)
        #expect(underscore.stripped.contains("hi▁"), "|\(underscore.stripped)|")
        let bar = render(.bar)
        #expect(bar.stripped.contains("hi▎"), "|\(bar.stripped)|")
        // The block caret inverts its cell (character in the background
        // colour on a caret-coloured block) rather than stamping a `█`
        // glyph, matching TextEditor — over the end-of-text space that is
        // a space on the caret colour, so no block glyph appears anywhere.
        let block = render(.block)
        #expect(block.stripped.contains("hi "), "|\(block.stripped)|")
        #expect(!block.stripped.contains("█"), "|\(block.stripped)|")
    }
}
