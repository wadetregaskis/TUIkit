//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swift build --build-tests   (from the package directory)
//
// Aborts SILGen on an assertions-enabled compiler, while emitting a
// reabstraction thunk for the `#expect` expansion's comparison:
//
//   TYPE MISMATCH IN ARGUMENT 0 OF APPLY ... argument type: $*Int64
//   parameter type: $*Optional<Int64>

import Testing

/// An optional, so `==` compares an `Int64?` against a non-optional operand.
func value() -> Int64? { 1_050_000_003 }

@Test func product() {
    // The right-hand side is an arithmetic expression of integer literals, not a
    // single literal: `1_050_000_003` alone compiles.
    #expect(value() == 9 * 116_666_667)
}
