//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProcessWideState.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// The one place a test in this target may change what every test in the
/// process reads — and only from inside an exit test.
///
/// This target's copy of `TUIkitTests`' `ProcessWideState`, which says why at
/// length; the per-module test targets link only their own module, so the two
/// cannot share one. In short: swift-testing runs every suite of every test
/// target concurrently in ONE process, so a process-wide value written by one
/// test is in force for all of them, on every thread, for as long as it stays
/// written — and restoring it afterwards still moves the generation every
/// cache compares. `.serialized` orders a suite's own tests, never other
/// suites. A test that is about the process-wide publication itself therefore
/// runs it in an exit test, `#expect(processExitsWith:)`, whose body runs in a
/// child process where nothing else does; a write from anywhere else is
/// refused here, recorded as an issue against the test that tried it, and the
/// value is left alone.
enum ProcessWideState {

    /// Whether this process is an exit test's child — the only place a
    /// process-wide write cannot reach another test. Records an issue when not.
    static func mayWrite(_ what: String) -> Bool {
        if ExitTest.current != nil { return true }
        Issue.record(
            """
            \(what) is read by every test in this process, on every thread, while \
            it stays written. Write it inside an exit test — #expect(processExitsWith:) — \
            whose body runs in a process of its own, or pin it for this task instead.
            """)
        return false
    }

    /// `TerminalColors.current`, the colours the terminal reported: read by
    /// every render in the process, and its setter moves the generation the
    /// render cache clears on.
    static var colours: TerminalColors {
        get { TerminalColors.current }
        set { if mayWrite("TerminalColors.current") { TerminalColors.current = newValue } }
    }
}
