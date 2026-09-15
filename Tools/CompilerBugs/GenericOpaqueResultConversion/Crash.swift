//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftc -parse-as-library -swift-version 6 -emit-library -o /dev/null Crash.swift
//
// Aborts SILGen on an assertions-enabled compiler, while emitting the closure:
//
//   Assertion failed: (!type->hasTypeParameter() && "no generic environment
//   provided for type with type parameters"), function mapTypeIntoContext,
//   file GenericEnvironment.cpp, line 337.

func each<T, R>(_ values: [T], _ transform: (T) -> R) -> [R] {
    values.map(transform)
}

/// Generic, so its methods have a generic environment. `Root` is never used.
struct Core<Root> {
    func bar(pairs: [(Int, String)]) -> [some Equatable] {
        // A closure that DESTRUCTURES its tuple parameter and calls a method
        // whose result type is opaque.
        each(pairs) { _, string in helper(string) }
    }

    func helper(_ string: String) -> some Equatable {
        string
    }
}
