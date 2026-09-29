//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalSizeFallbackTests.swift
//
//  `Terminal.getSize()` falls back to the `COLUMNS` / `LINES` environment
//  variables when `TIOCGWINSZ` is unavailable. Those are ordinary environment
//  variables — a shell's `checkwinsize`, a multiplexer, a CI runner, or a stale
//  export from a since-resized window can all set them — and `Int("0")` parses
//  fine, so an unvalidated read handed back a zero-row terminal from the very
//  path that exists because the real size was unknown.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Terminal size environment fallback")
struct TerminalSizeFallbackTests {

    @Test(
        "Only a positive value is a size",
        arguments: [
            ("40", 40),          // ordinary
            ("1", 1),            // degenerate but real
            ("0", nil),          // parses as Int — must NOT become a size
            ("-1", nil),         // ditto
            ("-100", nil),
            ("", nil),           // unset-ish
            ("abc", nil),        // garbage
            ("40x100", nil),     // wrong shape
            (" 40", nil),        // Int(" 40") is nil — no silent trimming
        ] as [(String, Int?)])
    func onlyPositiveValuesAreSizes(raw: String, expected: Int?) {
        let terminal = Terminal()
        #expect(terminal.terminalDimension(fromEnvironment: "LINES", in: ["LINES": raw]) == expected)
    }

    @Test("An unset variable is not a size")
    func unsetIsNil() {
        let terminal = Terminal()
        #expect(terminal.terminalDimension(fromEnvironment: "LINES", in: ["COLUMNS": "40"]) == nil)
    }

    /// The tests above pose the parse on a dictionary, so they would all still
    /// pass if the fallback stopped reading the real environment. This one sets
    /// the variable for real — in a process of its own, since the environment
    /// is the whole process's — and asks with the default.
    @Test("With no dictionary given, the process environment is what is read")
    func defaultReadsTheProcessEnvironment() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("LINES", to: "37")
                #expect(Terminal().terminalDimension(fromEnvironment: "LINES") == 37)
            }
        }
    }
}
