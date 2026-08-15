//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MediumGuaranteedModifierTests.swift
//
//  `monospaced(_:)`, `monospacedDigit()` and `autocorrectionDisabled(_:)`
//  return `self`. Asserting THAT would prove nothing — every unimplemented
//  modifier passes such a test.
//
//  So these assert the guarantee instead: that equal character counts really
//  do occupy equal cell counts, and that a `TextField` binding really does
//  receive exactly what was typed. If the medium ever stopped holding up its
//  end, these fail and the modifiers stop being honest.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Modifiers the medium already satisfies")
struct MediumGuaranteedModifierTests {

    private func width(_ text: String) -> Int {
        measureChild(
            Text(verbatim: text), proposal: ProposedSize(width: 80, height: 1),
            context: makeRenderContext()
        ).width
    }

    // MARK: - The guarantee behind monospaced() / monospacedDigit()

    /// Every digit is one cell, so a number that changes cannot change width —
    /// which is the jitter `monospacedDigit()` exists to prevent.
    @Test("every digit occupies exactly one cell")
    func digitsAreUniform() {
        for digit in "0123456789" {
            #expect(width(String(digit)) == 1, "digit \(digit)")
        }
        // The case that actually bites in a proportional font: 1 vs 8.
        #expect(width("111111") == width("888888"))
        #expect(width("10%") == width("88%"))
    }

    /// …and the wider claim behind `monospaced(_:)`: it is not only digits.
    /// Narrow and wide ASCII advance the same, so a column of text lines up
    /// without anyone asking for a font.
    @Test("equal ASCII character counts occupy equal cell counts")
    func asciiIsUniform() {
        #expect(width("iiii") == 4)
        #expect(width("MMMM") == 4)
        #expect(width("il1|") == width("WM@%"))
    }

    /// The boundary worth stating: the guarantee is about the FONT, not about
    /// Unicode. An emoji is still two cells — `monospaced()` never promised
    /// otherwise, and pretending it did is the cells-not-characters bug.
    @Test("the guarantee is per-cell, not per-character")
    func wideCharactersStillTakeTwoCells() {
        #expect(width("🖥") == 2, "a wide glyph is still wide")
        #expect(width("ab") == 2)
    }

    // MARK: - The guarantee behind autocorrectionDisabled()

    /// A misspelling, an unusual capitalisation and a double space all arrive
    /// exactly as typed. Nothing between the key event and the binding rewrites
    /// them, which is why there is no autocorrection to disable.
    @Test("a text field receives exactly what was typed")
    func typedTextIsNeverRewritten() {
        let box = StateBox("")
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let focusManager = FocusManager()
        let context = makeRenderContext { environment, _ in
            environment.focusManager = focusManager
        }
        let view = TextField("Notes", text: binding).autocorrectionDisabled()

        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()

        // "teh" is the canonical autocorrect target; the lone "i" is the
        // canonical autocapitalisation target.
        for character in "teh  i" {
            _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character(character)))
        }
        #expect(box.value == "teh  i", "got \(box.value)")
    }
}

@MainActor
@Suite("Text's monospaced pair")
struct TextMonospacedTests {

    private func rendered(_ text: Text) -> String {
        renderToBuffer(text, context: makeRenderContext(width: 20, height: 1)).lines.first ?? ""
    }

    /// Identity, and that is why adding them alongside the `View` spellings is
    /// safe: which overload a call binds to cannot change what it does. The
    /// style toggles are NOT like this — see Parity-decisions-pending.md §9.
    @Test("both return the text unchanged")
    func monospacedIsIdentity() {
        let plain = rendered(Text(verbatim: "10%"))
        #expect(rendered(Text(verbatim: "10%").monospaced()) == plain)
        #expect(rendered(Text(verbatim: "10%").monospaced(false)) == plain)
        #expect(rendered(Text(verbatim: "10%").monospacedDigit()) == plain)
    }
}
