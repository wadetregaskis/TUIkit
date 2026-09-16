//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// ./variants.sh is the way to run this; it needs a toolchain's own swift-testing,
// which is easiest to get through SwiftPM. To drive one by hand, put this file in
// a package's test target and run:
//
//   tc=~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain
//   "$tc/usr/bin/swift" test
//
// Two closure literals of the SAME type, in the SAME enclosing closure, are
// lowered to a SINGLE SIL function when the first is inside a macro expansion
// buffer (#expect/#require) and the second follows it in ordinary source. They
// are given the same local discriminator, hence the same mangled name, so
// SILGen's getOrCreateFunction hands back the function it already made and the
// second closure's body is NEVER EMITTED.
//
// Swift 6.3.3 and Xcode's 6.2.4 do this silently: `flagged` below is computed by
// the `#expect` line's predicate instead of its own, so it is every cell rather
// than just the flagged ones, and only RUNNING the test reveals it. Either of the
// two closures can be the one that loses its body, so the assertions here are
// chosen so that a swap in EITHER direction flips an answer.
//
// Swift 6.4 turns the same collision into a hard compile error, because the
// standard library's Sequence.filter is now typed-throws while allSatisfy still
// rethrows, so the two demanded types visibly disagree:
//
//   error: function type mismatch, declared as '@convention(thin) @substituted
//   <τ_0_0> (@in_guaranteed τ_0_0) -> (Bool, @error any Error) for <(character:
//   Character, state: State)>' but used as '@convention(thin) @substituted
//   <τ_0_0, τ_0_1> (@in_guaranteed τ_0_0) -> (Bool, @error_indirect τ_0_1) for
//   <(character: Character, state: State), Never>'
//
// So 6.4 is refusing to emit the wrong code that the others emit without a word.

import Testing

struct State { var flag = false }

func withCurrent<T>(_ body: () throws -> T) rethrows -> T { try body() }

@Suite struct Reduction {
    // "a" is not flagged; "b" and "c" are. No cell's character is "z".
    func cells() -> [(character: Character, state: State)] {
        [("a", State(flag: false)), ("b", State(flag: true)), ("c", State(flag: true))]
    }

    @Test func closuresAreNotConflated() {
        withCurrent {
            let drawn = cells()
            // The macro expansion's closure comes first. It is true of every cell, and
            // the filter's predicate is not, so borrowing either body flips a result.
            #expect(drawn.allSatisfy { $0.character != "z" }, "the closure inside the macro")
            // This one, of the same type, in the same enclosing closure, is the one
            // dropped here: it really runs `{ $0.character != "z" }`, so it keeps all
            // three cells instead of the two that are flagged.
            let flagged = drawn.filter { $0.state.flag }
            #expect(
                flagged.map(\.character) == ["b", "c"],
                "the filter ran the wrong closure: \(flagged.map(\.character))")
        }
    }
}
