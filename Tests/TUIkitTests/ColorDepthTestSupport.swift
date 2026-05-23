//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorDepthTestSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@testable import TUIkit

// MARK: - Color Depth Test Serialization

/// Serializes the tests that depend on the process-global `ColorDepth.current`.
///
/// `ColorDepth.current` is shared, mutable, process-wide state. The Swift
/// Testing runner executes tests in parallel, so a test that sets it — or
/// that renders colour through it and asserts on the result — must not
/// overlap another such test, or one observes the colour depth the other
/// established.
///
/// Swift Testing's `.serialized` trait only serializes tests *within a
/// single suite*; the affected tests live in several suites across several
/// files, so a shared lock is used to serialize them against one another
/// regardless of which suite they belong to.
private let colorDepthLock = NSLock()

/// Runs `body` with `ColorDepth.current` pinned to `depth`, serialized
/// against every other `withColorDepth(_:_:)` call, and restores the
/// previous value afterwards.
///
/// Wrap the whole colour-dependent portion of a test — the render/convert
/// call *and* its expectations — so the pinned depth is observed throughout.
///
/// - Parameters:
///   - depth: The colour depth to pin `ColorDepth.current` to for the
///     duration of `body`.
///   - body: The colour-dependent work to run exclusively.
/// - Returns: Whatever `body` returns.
@discardableResult
func withColorDepth<T>(_ depth: ColorDepth, _ body: () throws -> T) rethrows -> T {
    colorDepthLock.lock()
    defer { colorDepthLock.unlock() }

    let previous = ColorDepth.current
    defer { ColorDepth.current = previous }

    ColorDepth.current = depth
    return try body()
}
