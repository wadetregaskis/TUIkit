//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorDepthCapTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Colour-depth cap")
struct ColorDepthCapTests {

    @Test("A cap only ever removes colour")
    func capIsACeiling() {
        ColorDepth.withCurrent(.truecolor) {
            #expect(ColorDepth.current == .truecolor)
            ColorDepth.withCap(.palette256) { #expect(ColorDepth.current == .palette256) }
            ColorDepth.withCap(.basic16) { #expect(ColorDepth.current == .basic16) }
        }
        // The direction that matters: a cap ABOVE what the terminal can do
        // changes nothing, because it is a ceiling and not an override. This is
        // the whole reason it is a second knob — assigning `current` would
        // upgrade a terminal that cannot honour it.
        ColorDepth.withCurrent(.basic16) {
            ColorDepth.withCap(.truecolor) { #expect(ColorDepth.current == .basic16) }
            ColorDepth.withCap(.palette256) { #expect(ColorDepth.current == .basic16) }
        }
    }

    @Test("The default cap is no cap")
    func defaultIsUncapped() {
        #expect(ColorDepth.cap == .truecolor)
        ColorDepth.withCurrent(.truecolor) { #expect(ColorDepth.current == .truecolor) }
    }

    @Test("A cap composes with detection rather than replacing it")
    func capComposes() {
        // Two terminals, one cap: each renders at its own ceiling. Expressing
        // this by assigning `current` would need the cap re-derived every time
        // detection changed.
        ColorDepth.withCap(.palette256) {
            ColorDepth.withCurrent(.truecolor) { #expect(ColorDepth.current == .palette256) }
            ColorDepth.withCurrent(.basic16) { #expect(ColorDepth.current == .basic16) }
            ColorDepth.withCurrent(.noColor) { #expect(ColorDepth.current == .noColor) }
        }
    }

    @Test("The pin is task-local, so it leaves the process alone")
    func pinIsScoped() {
        let before = ColorDepth.cap
        ColorDepth.withCap(.basic16) { #expect(ColorDepth.cap == .basic16) }
        #expect(ColorDepth.cap == before)
    }
}

// MARK: - A main-actor caller can pin the depth around suspending work

/// A COMPILE-time guard, deliberately never run.
///
/// Before the async pins were marked `nonisolated(nonsending)` *themselves*,
/// this body did not build: the wrapper hopped to the generic executor before
/// invoking the closure, so handing it a main-actor-isolated closure was
/// "sending value of non-Sendable type '() async -> ()' risks causing data
/// races". Compiling is the whole assertion, which is why this is not a
/// `@Test` — as one it has to wait for the main actor that the rest of the
/// suite keeps busy, and occupying the main actor perturbs the timing-sensitive
/// tests elsewhere in the run.
@MainActor
private func mainActorCanPinAroundSuspension() async {
    let counter = MainActorCounter()

    await ColorDepth.withCurrent(.basic16) {
        // Load-bearing: a genuine suspension is what selects the ASYNC
        // overload. With a closure that never suspends, the synchronous
        // overload wins and the `await` is vacuous, so this proves nothing.
        await Task.yield()

        // Load-bearing too: touching main-actor state with no `await` only
        // compiles because the closure kept the caller's isolation rather than
        // hopping off it.
        counter.n += 1
    }

    _ = counter.n
}

/// Main-actor state for `mainActorCanPinAroundSuspension()` to touch from
/// inside the pinned operation.
@MainActor
private final class MainActorCounter {
    var n = 0
}
