//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftc -emit-silgen -o /dev/null Crash.swift
//
// Aborts SILGen on an assertions-enabled compiler, while it emits the protocol
// witness thunk for `run()`:
//
//   Assertion failed: (isPreconcurrency), function emitProtocolWitness,
//   file SILGenPoly.cpp, line 7521.
//
// Declaring the conformance is enough. Nothing calls `run()`.

/// Nonisolated, with a synchronous requirement.
protocol Runner {
    func run()
}

/// A type parameter pack on the conforming type, a `@preconcurrency`
/// conformance, and an actor-isolated witness: a method of an actor. Nothing
/// has to be stored, and no protocol is main-actor isolated.
actor Holder<each Element>: @preconcurrency Runner {
    func run() {}
}
