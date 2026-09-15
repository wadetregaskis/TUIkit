//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIRendererFullTests.swift
//
//  Comprehensive tests for ANSIRenderer: style rendering, color codes,
//  cursor control, screen control, and convenience methods.
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

// MARK: - Style Rendering Tests

@MainActor
@Suite("ANSIRenderer Style Rendering Tests")
struct ANSIRendererStyleTests {

    @Test("Plain text without style returns unchanged")
    func plainText() {
        let result = ANSIRenderer.render("Hello", with: TextStyle())
        #expect(result == "Hello")
    }

    @Test("Bold text wraps with bold code")
    func boldText() {
        var style = TextStyle()
        style.isBold = true
        let result = ANSIRenderer.render("Bold", with: style)
        #expect(result.contains("\u{1B}[1m"))
        #expect(result.contains("Bold"))
        #expect(result.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Dim text wraps with ESC[2m dim code")
    func dimText() {
        var style = TextStyle()
        style.isDim = true
        let result = ANSIRenderer.render("Dim", with: style)
        #expect(result.contains("\u{1B}[2m"))
        #expect(result.contains("Dim"))
        #expect(result.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Italic text wraps with ESC[3m italic code")
    func italicText() {
        var style = TextStyle()
        style.isItalic = true
        let result = ANSIRenderer.render("Italic", with: style)
        #expect(result.contains("\u{1B}[3m"))
        #expect(result.contains("Italic"))
        #expect(result.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Underlined text wraps with ESC[4m underline code")
    func underlinedText() {
        var style = TextStyle()
        style.isUnderlined = true
        let result = ANSIRenderer.render("Underline", with: style)
        #expect(result.contains("\u{1B}[4m"))
        #expect(result.contains("Underline"))
        #expect(result.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Blink text wraps with ESC[5m blink code")
    func blinkText() {
        var style = TextStyle()
        style.isBlink = true
        let result = ANSIRenderer.render("Blink", with: style)
        #expect(result.contains("\u{1B}[5m"))
        #expect(result.contains("Blink"))
        #expect(result.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Inverted text wraps with ESC[7m inverse code")
    func invertedText() {
        var style = TextStyle()
        style.isInverted = true
        let result = ANSIRenderer.render("Inv", with: style)
        #expect(result.contains("\u{1B}[7m"))
        #expect(result.contains("Inv"))
        #expect(result.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Strikethrough text wraps with ESC[9m strikethrough code")
    func strikethroughText() {
        var style = TextStyle()
        style.isStrikethrough = true
        let result = ANSIRenderer.render("Strike", with: style)
        #expect(result.contains("\u{1B}[9m"))
        #expect(result.contains("Strike"))
        #expect(result.hasSuffix(ANSIRenderer.reset))
    }

    @Test("Combined styles produce semicolon-separated codes")
    func combinedStyles() {
        var style = TextStyle()
        style.isBold = true
        style.isUnderlined = true
        let result = ANSIRenderer.render("Both", with: style)
        #expect(result.contains("\u{1B}[1;4m"))
    }

    @Test("Foreground color produces correct code")
    func foregroundColor() {
        var style = TextStyle()
        style.foregroundColor = .ansi(.red)
        let result = ANSIRenderer.render("Red", with: style)
        #expect(result.contains("\u{1B}[31m"))
    }

    @Test("Background color produces correct code")
    func backgroundColor() {
        var style = TextStyle()
        style.backgroundColor = .ansi(.blue)
        let result = ANSIRenderer.render("Blue", with: style)
        #expect(result.contains("\u{1B}[44m"))
    }

    @Test("RGB foreground uses 38;2;r;g;b format at truecolor depth")
    func rgbForeground() {
        let codes = Color.rgb(255, 128, 0).foregroundCodes(depth: .truecolor)
        #expect(codes == ["38", "2", "255", "128", "0"])
    }

    @Test("RGB background uses 48;2;r;g;b format at truecolor depth")
    func rgbBackground() {
        let codes = Color.rgb(0, 255, 128).backgroundCodes(depth: .truecolor)
        #expect(codes == ["48", "2", "0", "255", "128"])
    }

    @Test("Palette256 foreground uses 38;5;n format")
    func palette256Foreground() {
        var style = TextStyle()
        style.foregroundColor = Color.palette(42)
        withColorDepth(.palette256) {
            let result = ANSIRenderer.render("Pal", with: style)
            #expect(result.contains("38;5;42"))
        }
    }

    @Test("Palette256 background uses 48;5;n format")
    func palette256Background() {
        var style = TextStyle()
        style.backgroundColor = Color.palette(200)
        withColorDepth(.palette256) {
            let result = ANSIRenderer.render("Pal", with: style)
            #expect(result.contains("48;5;200"))
        }
    }

    @Test("Bright foreground uses correct code")
    func brightForeground() {
        var style = TextStyle()
        style.foregroundColor = .ansi(.brightRed)
        let result = ANSIRenderer.render("Bright", with: style)
        #expect(result.contains("\u{1B}[91m"))
    }

    @Test("Bright background uses correct code")
    func brightBackground() {
        var style = TextStyle()
        style.backgroundColor = .ansi(.brightBlue)
        let result = ANSIRenderer.render("Bright", with: style)
        #expect(result.contains("\u{1B}[104m"))
    }
}

// MARK: - Convenience Methods Tests

@MainActor
@Suite("ANSIRenderer Convenience Tests")
struct ANSIRendererConvenienceTests {

    @Test("colorize with foreground applies color")
    func colorizeForeground() {
        let result = ANSIRenderer.colorize("Hello", foreground: .ansi(.green))
        #expect(result.contains("\u{1B}[32m"))
        #expect(result.stripped == "Hello")
    }

    @Test("colorize with background applies color")
    func colorizeBackground() {
        let result = ANSIRenderer.colorize("Hello", background: .ansi(.red))
        #expect(result.contains("\u{1B}[41m"))
    }

    @Test("colorize with bold applies bold")
    func colorizeBold() {
        let result = ANSIRenderer.colorize("Hello", bold: true)
        #expect(result.contains("\u{1B}[1m"))
    }

    @Test("colorize with all options applies foreground, background, and bold")
    func colorizeAll() {
        let result = ANSIRenderer.colorize("Hello", foreground: .ansi(.white), background: .ansi(.blue), bold: true)
        #expect(result.stripped == "Hello")
        #expect(result.contains("\u{1B}[1;37;44m"))
    }

    @Test("colorize without options returns plain text")
    func colorizeNoOptions() {
        let result = ANSIRenderer.colorize("Plain")
        #expect(result == "Plain")
    }

    @Test("backgroundCode produces correct sequence")
    func backgroundCodeMethod() {
        let code = ANSIRenderer.backgroundCode(for: .ansi(.green))
        #expect(code == "\u{1B}[42m")
    }

    @Test("applyPersistentBackground wraps with bg code")
    func persistentBackground() {
        let result = ANSIRenderer.applyPersistentBackground("Text", color: .ansi(.blue))
        #expect(result.contains("\u{1B}[44m"))
    }

    @Test("applyPersistentBackground replaces inner resets")
    func persistentBackgroundReplacesResets() {
        let input = "Before\(ANSIRenderer.reset)After"
        let result = ANSIRenderer.applyPersistentBackground(input, color: .ansi(.red))
        // After reset, the bg code should be re-applied
        let bgCode = ANSIRenderer.backgroundCode(for: .ansi(.red))
        // The reset in the middle should be followed by the bg code
        #expect(result.contains(ANSIRenderer.reset + bgCode))
    }
}

// MARK: - Persistent Reverse Tests

/// `applyPersistentReverse(_:ink:field:)`: SGR 7 with the ink and field restated after
/// every reset. A bare 7 exchanges the TERMINAL's colours, not the palette's, so a cell
/// after a child's reset, or plain padding, would fill with the terminal's foreground.
@MainActor
@Suite("ANSIRenderer persistent reverse")
struct ANSIRendererPersistentReverseTests {

    private static let ink = Color.rgb(10, 20, 30)
    private static let field = Color.ansi(.blue)

    /// The state `ESC[7;<ink>;<field>m` puts the terminal in from its defaults.
    private static var reversed: SGRState {
        var state = SGRState()
        state.apply("\u{1B}[7;38;2;10;20;30;44m")
        return state
    }

    private func wrapped(_ line: String) -> String {
        ColorDepth.withCurrent(.truecolor) {
            ANSIRenderer.applyPersistentReverse(line, ink: Self.ink, field: Self.field)
        }
    }

    @Test("It opens with 7, the ink and the field, and closes with a reset")
    func opensAndCloses() {
        #expect(wrapped("ab") == "\u{1B}[7;38;2;10;20;30;44mab\u{1B}[0m")
    }

    @Test("A cell after a child's reset is reversed in the stated pair")
    func survivesAnInnerReset() {
        let line = wrapped("\u{1B}[31mab\u{1B}[0mcd")
        for column in 2...3 {
            #expect(line.ansiSGRStateAt(visibleColumn: column) == Self.reversed, "\(column): \(line.debugDescription)")
        }
        // The child's own colour stays its own, still reversed over the stated field.
        var child = Self.reversed
        child.apply("\u{1B}[31m")
        #expect(line.ansiSGRStateAt(visibleColumn: 0) == child, "\(line.debugDescription)")
    }

    @Test("A collapsed reset restates the pair before the child's colour")
    func survivesACollapsedReset() {
        let line = wrapped("x\u{1B}[0;38;5;9my")
        var child = Self.reversed
        child.apply("\u{1B}[38;5;9m")
        #expect(line.ansiSGRStateAt(visibleColumn: 0) == Self.reversed, "\(line.debugDescription)")
        #expect(line.ansiSGRStateAt(visibleColumn: 1) == child, "\(line.debugDescription)")
    }

    /// The trap the ink and field are restated for: padding is plain spaces after the
    /// content's last reset.
    @Test("Padding after a child's reset carries the stated ink and field")
    func paddingCarriesThePair() {
        let line = wrapped("\u{1B}[0;38;5;9mchild\u{1B}[0m   ")
        for column in 5...7 {
            #expect(line.ansiSGRStateAt(visibleColumn: column) == Self.reversed, "\(column): \(line.debugDescription)")
        }
    }

    @Test("Nothing reversed is left in force after the line")
    func leavesNoTrailingReverse() {
        for line in ["ab", "\u{1B}[31mab\u{1B}[0m", "x\u{1B}[0;38;5;9my", "\u{1B}[7mz"] {
            var state = SGRState()
            for segment in wrapped(line).ansiSegments() {
                if case .ansi(let sequence, true) = segment { state.apply(sequence) }
            }
            #expect(state == SGRState(), "\(line.debugDescription)")
        }
    }
}

// MARK: - Cursor Control Tests

@MainActor
@Suite("ANSIRenderer Cursor Control Tests")
struct ANSIRendererCursorTests {

    @Test("moveCursor generates correct sequence")
    func moveCursor() {
        let result = ANSIRenderer.moveCursor(toRow: 5, column: 10)
        #expect(result == "\u{1B}[5;10H")
    }

    @Test("hideCursor and showCursor codes")
    func cursorVisibility() {
        #expect(ANSIRenderer.hideCursor == "\u{1B}[?25l")
        #expect(ANSIRenderer.showCursor == "\u{1B}[?25h")
    }

    @Test("Alternate screen codes")
    func alternateScreen() {
        #expect(ANSIRenderer.enterAlternateScreen == "\u{1B}[?1049h")
        #expect(ANSIRenderer.exitAlternateScreen == "\u{1B}[?1049l")
    }
}
