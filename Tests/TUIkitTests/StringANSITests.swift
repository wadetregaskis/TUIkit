//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StringANSITests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("String ANSI Extension Tests")
struct StringANSITests {

    // MARK: - stripped

    @Test("stripped removes ANSI codes from text")
    func strippedRemovesCodes() {
        let styled = "\u{1B}[31mHello\u{1B}[0m"
        #expect(styled.stripped == "Hello")
    }

    @Test("stripped on plain text returns unchanged")
    func strippedPlainText() {
        #expect("Hello World".stripped == "Hello World")
    }

    @Test("stripped on empty string returns empty")
    func strippedEmpty() {
        #expect("".stripped.isEmpty)
    }

    @Test("stripped removes nested ANSI codes")
    func strippedNested() {
        let text = "\u{1B}[1m\u{1B}[31mBold Red\u{1B}[0m"
        #expect(text.stripped == "Bold Red")
    }

    @Test("stripped removes multiple codes in one string")
    func strippedMultiple() {
        let text = "\u{1B}[32mGreen\u{1B}[0m and \u{1B}[34mBlue\u{1B}[0m"
        #expect(text.stripped == "Green and Blue")
    }

    @Test("stripped handles RGB color codes")
    func strippedRGB() {
        let text = "\u{1B}[38;2;255;0;0mRed\u{1B}[0m"
        #expect(text.stripped == "Red")
    }

    // MARK: - strippedLength

    @Test("strippedLength counts visible characters only")
    func strippedLengthVisible() {
        let styled = "\u{1B}[31mHello\u{1B}[0m"
        #expect(styled.strippedLength == 5)
    }

    @Test("strippedLength on plain text equals count")
    func strippedLengthPlain() {
        let text = "Hello"
        #expect(text.strippedLength == text.count)
    }

    @Test("strippedLength on empty string is zero")
    func strippedLengthEmpty() {
        #expect("".strippedLength == 0)
    }

    // MARK: - padToVisibleWidth

    @Test("padToVisibleWidth pads short string")
    func padShortString() {
        let result = "Hi".padToVisibleWidth(5)
        #expect(result == "Hi   ")
        #expect(result.count == 5)
    }

    @Test("padToVisibleWidth on exact width returns unchanged")
    func padExactWidth() {
        let result = "Hello".padToVisibleWidth(5)
        #expect(result == "Hello")
    }

    @Test("padToVisibleWidth on longer string returns unchanged")
    func padLongerString() {
        let result = "Hello World".padToVisibleWidth(5)
        #expect(result == "Hello World")
    }

    @Test("padToVisibleWidth with ANSI codes pads to visible width")
    func padWithANSI() {
        let styled = "\u{1B}[31mHi\u{1B}[0m" // "Hi" in red
        let result = styled.padToVisibleWidth(5)
        // Should pad based on visible width (2), not string length
        #expect(result.strippedLength == 5)
        #expect(result.stripped == "Hi   ")
    }

    @Test("padToVisibleWidth with zero target")
    func padZeroTarget() {
        let result = "Hi".padToVisibleWidth(0)
        #expect(result == "Hi") // unchanged, already wider
    }

    @Test("padToVisibleWidth on empty string")
    func padEmptyString() {
        let result = "".padToVisibleWidth(3)
        #expect(result == "   ")
    }

    // MARK: - Emoji width

    @Test("strippedLength of base emoji is 2")
    func baseEmojiWidth() {
        #expect("🤙".strippedLength == 2, "Base emoji should be 2 terminal cells wide")
    }

    @Test("strippedLength of skin-tone emoji equals base emoji width")
    func skinToneEmojiWidth() {
        // 🤙🏽 = base emoji + skin-tone modifier. The modifier should not add
        // extra width — the combined glyph is still 2 terminal cells wide.
        #expect("🤙🏽".strippedLength == 2, "Skin-tone emoji should be 2 terminal cells wide, same as the base")
    }

    @Test("strippedLength of skin-tone emoji matches base emoji across all tones")
    func allSkinToneEmojiWidths() {
        let tones = ["🤙🏻", "🤙🏼", "🤙🏽", "🤙🏾", "🤙🏿"]
        for tone in tones {
            #expect(tone.strippedLength == 2, "\(tone) should be 2 terminal cells wide")
        }
    }

    @Test("strippedLength of ANSI-styled skin-tone emoji is 2")
    func styledSkinToneEmojiWidth() {
        let styled = "\u{1B}[38;2;200;100;50m🤙🏽\u{1B}[0m"
        #expect(styled.strippedLength == 2, "ANSI-styled skin-tone emoji should still be 2 terminal cells wide")
    }

    // MARK: - strippedLength vs manual filtering

    @Test("strippedLength correctly handles ANSI-colored content")
    func strippedLengthWithANSI() {
        // Simulate ANSI-colored image output: "XX" in red
        let colored = "\u{1B}[38;2;255;0;0mXX\u{1B}[0m"
        #expect(colored.strippedLength == 2,
                "strippedLength should count only visible characters, not ANSI codes")
        // The old manual filter approach would have included ANSI digits/letters in the count
        let manualWidth = colored.filter { !$0.isASCII || ($0.asciiValue ?? 0) >= 32 }.count
        #expect(manualWidth != 2,
                "Manual filter incorrectly includes ANSI sequence characters in the count")
    }
}
