//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextFormatTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Text(_:format:)")
struct TextFormatTests {
    @Test("The formatted init delegates to the format style")
    func delegatesToFormatStyle() {
        // Locale-independent: whatever the style produces, the init must display
        // verbatim. Comparing against the same style sidesteps locale specifics.
        let percent: FloatingPointFormatStyle<Double>.Percent = .percent
        #expect(Text(0.5, format: percent).content == percent.format(0.5))

        let number: IntegerFormatStyle<Int> = .number
        #expect(Text(1234, format: number).content == number.format(1234))
    }

    @Test("The formatted init produces the expected string for a pinned locale")
    func pinnedLocaleOutput() {
        let enUS = Locale(identifier: "en_US")
        #expect(Text(0.5, format: .percent.locale(enUS)).content == "50%")
        #expect(Text(1234, format: .number.locale(enUS)).content == "1,234")
    }
}
