//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SignalFlagsTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Tests for `SignalFlags` — the pure flag-state logic behind
/// `SignalManager`.
///
/// These exercise a freshly-constructed `SignalFlags` value in isolation,
/// so there is no contact with the process-global instance, no installed
/// signal handlers, and no cross-test interference. `SignalManager.install()`
/// itself (which registers real SIGINT/SIGWINCH handlers, a process-global
/// side effect) is intentionally not unit-tested — it's covered by
/// manual/end-to-end runs; the consume-on-read semantics that the main loop
/// actually depends on all live here.
@Suite("SignalFlags")
struct SignalFlagsTests {

    // MARK: - Fresh state

    @Test("A fresh value has every flag clear")
    func freshIsClear() {
        var flags = SignalFlags()
        #expect(flags.needsRerender == false)
        #expect(flags.terminalResized == false)
        #expect(flags.needsShutdown == false)
        #expect(flags.consumeRerender() == false)
        #expect(flags.consumeResize() == false)
    }

    // MARK: - Consume-on-read: rerender

    @Test("consumeRerender returns true once, then false (consume-on-read)")
    func consumeRerenderIsOneShot() {
        var flags = SignalFlags()
        flags.needsRerender = true
        #expect(flags.consumeRerender() == true)
        #expect(flags.consumeRerender() == false)
        #expect(flags.needsRerender == false)
    }

    @Test("consumeRerender returns false when never set")
    func consumeRerenderUnsetIsFalse() {
        var flags = SignalFlags()
        #expect(flags.consumeRerender() == false)
    }

    // MARK: - Consume-on-read: resize

    @Test("consumeResize returns true once, then false (consume-on-read)")
    func consumeResizeIsOneShot() {
        var flags = SignalFlags()
        flags.terminalResized = true
        #expect(flags.consumeResize() == true)
        #expect(flags.consumeResize() == false)
        #expect(flags.terminalResized == false)
    }

    @Test("consumeResize returns false when never set")
    func consumeResizeUnsetIsFalse() {
        var flags = SignalFlags()
        #expect(flags.consumeResize() == false)
    }

    // MARK: - Shutdown is sticky (no consume)

    @Test("needsShutdown stays set — it is read, never consumed")
    func shutdownIsSticky() {
        var flags = SignalFlags()
        flags.needsShutdown = true
        #expect(flags.needsShutdown == true)
        // Consuming the other flags must not clear shutdown.
        _ = flags.consumeRerender()
        _ = flags.consumeResize()
        #expect(flags.needsShutdown == true)
    }

    // MARK: - Independence

    @Test("The three flags are independent")
    func flagsAreIndependent() {
        var flags = SignalFlags()

        // Setting/consuming rerender leaves resize and shutdown untouched.
        flags.needsRerender = true
        #expect(flags.consumeRerender() == true)
        #expect(flags.terminalResized == false)
        #expect(flags.needsShutdown == false)

        // Setting/consuming resize leaves rerender and shutdown untouched.
        flags.terminalResized = true
        #expect(flags.consumeResize() == true)
        #expect(flags.needsRerender == false)
        #expect(flags.needsShutdown == false)
    }

    @Test("SIGWINCH semantics: setting both rerender and resize, each consumes once independently")
    func resizeAndRerenderTogether() {
        var flags = SignalFlags()
        // SIGWINCH sets both.
        flags.needsRerender = true
        flags.terminalResized = true

        #expect(flags.consumeRerender() == true)
        // Resize still pending after rerender consumed.
        #expect(flags.consumeResize() == true)
        // Both now drained.
        #expect(flags.consumeRerender() == false)
        #expect(flags.consumeResize() == false)
    }
}
