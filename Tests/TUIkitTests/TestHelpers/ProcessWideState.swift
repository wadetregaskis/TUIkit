//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProcessWideState.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The one place a test may change what every test in the process reads — and
/// only from inside an exit test.
///
/// # Why
///
/// swift-testing runs every suite of every test target concurrently in ONE
/// process (`parallel_test.py` splits them across several, and each of those is
/// still shared). A value published process-wide is therefore in force for
/// every test running at that moment, on every thread, for as long as it stays
/// written:
///
/// - `.serialized` orders a suite's OWN tests. It does nothing about other
///   suites, which is what the suites that relied on it were defending against.
/// - A main-actor test that writes and restores within one synchronous stretch
///   is invisible to other main-actor tests, but not to a nonisolated one on
///   another thread, which can read the value mid-window.
/// - Restoring does not undo a generation counter. `TerminalColors.generation`
///   and `TerminalWidthTraits.generation` move on every real change, and the
///   render cache clears everything when either has moved since its last pass.
///
/// Both flakes of 2026-09-28 were this. `ANSIPrefixKnownWidthTests`' fuzz, in
/// `TUIkitCoreTests`, compares two width walks over the process's width traits
/// and saw them disagree while the process-wide width-traits suite had moved
/// the traits between the two. `BackdropMemoTests` saw a frame it expected
/// served from the memo drawn afresh, because a colours test on another thread
/// moved `TerminalColors.generation` between two of its frames.
///
/// # How
///
/// - A test that is ABOUT a process-wide publication — the setter, what it
///   invalidates, a diagnostic knob that republishes — runs it in an exit test,
///   `#expect(processExitsWith: .success) { … }`. Its body runs in a child
///   process of its own, where no other test runs, so nothing needs restoring.
///   Writes go through this type, which refuses them anywhere else: the issue
///   is recorded against the test that tried, and the value is left alone.
/// - Everything else pins for its own task — `TerminalWidthTraits.withTraits`,
///   `TerminalColors.withCurrent`, `ColorDepth.withCurrent`,
///   `TerminalHyperlink.withSupport`, `KittyGraphics.withSupport` — or poses the
///   question on arguments.
///
/// SwiftLint's `process_wide_write_in_tests` forbids the writes this type wraps
/// everywhere in `Tests/` except here and in `TUIkitStylingTests`' copy.
///
/// An exit test is not free: its child loads this whole test bundle. That is
/// the price of a test whose subject is the process, so a test that is not
/// about the publication itself should pin or pass arguments instead.
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

    /// `TerminalWidthTraits.current`, the width the host claims for the
    /// clusters it draws wide: read by every width measurement in the process,
    /// on every thread, and its setter moves the generation the render cache
    /// and `TextWrapping`'s memos drop themselves on.
    static var widthTraits: TerminalWidthTraits {
        get { TerminalWidthTraits.current }
        set { if mayWrite("TerminalWidthTraits.current") { TerminalWidthTraits.current = newValue } }
    }

    /// `TerminalClient.simulated`. Main-actor state, but setting it republishes
    /// the width traits and link support process-wide, which is its point.
    @MainActor static var simulated: TerminalClient.Program? {
        get { TerminalClient.simulated }
        set { if mayWrite("TerminalClient.simulated") { TerminalClient.simulated = newValue } }
    }

    /// `TerminalClient.simulatedQuirks`, which republishes the width traits
    /// its switches imply.
    @MainActor static var simulatedQuirks: TerminalQuirks? {
        get { TerminalClient.simulatedQuirks }
        set { if mayWrite("TerminalClient.simulatedQuirks") { TerminalClient.simulatedQuirks = newValue } }
    }
}

/// The door's own check.
@Suite("Process-wide state is written only in a process of its own")
struct ProcessWideStateTests {

    /// Here, in the shared process, a write is refused and recorded, and
    /// nothing any other test reads moves.
    @Test("A write from outside an exit test is refused and recorded")
    func writeOutsideAnExitTestIsRefused() {
        let before = TerminalColors.generation
        withKnownIssue("refused: this is the shared test process") {
            ProcessWideState.colours = TerminalColors(prefersDark: true)
        }
        #expect(TerminalColors.current == .unknown)
        #expect(TerminalColors.generation == before)
    }
}
