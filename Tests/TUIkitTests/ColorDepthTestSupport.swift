//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorDepthTestSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@testable import TUIkit

/// Runs `body` with `ColorDepth.current` pinned to `depth` for the current
/// task only.
///
/// Wrap the whole colour-dependent portion of a test — the render/convert
/// call *and* its expectations — so the pinned depth is observed throughout.
///
/// The pin is task-local (`ColorDepth.withCurrent`), so parallel tests are
/// unaffected: no lock, no restore, no bleed. (An earlier version mutated the
/// process-global under a lock shared by `withColorDepth` callers — but every
/// OTHER colour-asserting test still raced it, and a `.noColor` window here
/// occasionally made an unrelated control render colourless mid-suite.)
///
/// - Parameters:
///   - depth: The colour depth to pin `ColorDepth.current` to for the
///     duration of `body`.
///   - body: The colour-dependent work to run under the pin.
/// - Returns: Whatever `body` returns.
@discardableResult
func withColorDepth<T>(_ depth: ColorDepth, _ body: () throws -> T) rethrows -> T {
    try ColorDepth.withCurrent(depth, operation: body)
}

// MARK: - Task isolation of the pin

import Testing

@Suite("ColorDepth pin task isolation")
struct ColorDepthPinIsolationTests {

    @Test("A pinned depth is visible inside the pin and invisible to other tasks")
    func pinIsTaskScoped() async {
        let ambient = ColorDepth.current
        // Pin a depth guaranteed to differ from the ambient one.
        let pinned: ColorDepth = ambient == .noColor ? .truecolor : .noColor

        await ColorDepth.withCurrent(pinned) {
            #expect(ColorDepth.current == pinned, "the pin is visible on the pinning task")

            // A detached task inherits no task-locals: it must see the
            // ambient process value, NOT the pin. (This is the parallel-test
            // bleed that once made an unrelated Picker render colourless
            // while an ImageTests case held a .noColor pin.)
            let elsewhere = await Task.detached { ColorDepth.current }.value
            #expect(elsewhere == ambient, "other tasks see the ambient depth, got \(elsewhere)")
        }

        #expect(ColorDepth.current == ambient, "the pin ends with its scope")
    }
}
