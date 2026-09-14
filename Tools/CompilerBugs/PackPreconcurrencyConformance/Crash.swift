//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftc -parse-as-library -swift-version 6 -emit-library -o /dev/null Crash.swift
//
// Aborts SILGen on an assertions-enabled compiler, while emitting the witness
// thunk for `==`:
//
//   Assertion failed: (isPreconcurrency), function emitProtocolWitness,
//   file SILGenPoly.cpp, line 7521.
//
// No use of `==` is needed; declaring the conformance is enough.

/// Main-actor isolated, so a conforming type's `==` is main-actor isolated and
/// the nonisolated `Equatable` requirement needs `@preconcurrency` (or an
/// isolated conformance) to accept it.
@MainActor protocol View {}

/// A struct that stores a parameter pack.
struct Pack<each V: View>: View {
    let children: (repeat each V)
}

/// A `@preconcurrency` conformance. Its pack condition is not one of the
/// ingredients: `variants.sh` asserts without it too.
extension Pack: @preconcurrency Equatable where repeat each V: Equatable {
    static func == (lhs: Pack, rhs: Pack) -> Bool {
        func isEqual<T: Equatable>(_ left: T, _ right: T) -> Bool { left == right }
        var result = true
        repeat result = result && isEqual(each lhs.children, each rhs.children)
        return result
    }
}
