//  The reduction: `import Foundation`, and a conditional cast of an ARRAY to a
//  protocol existential the array's element does not conform to is reported as
//  one that "always succeeds". It does not — the cast fails at runtime, which
//  is the whole reason the code is written with `as?`.
//
//  `Plain` is a concrete struct with no conformances at all, so there is
//  nothing conditional left to reason about: `[Plain]` cannot be `Equatable`
//  under any substitution. Remove the `import Foundation` and the warning goes
//  with it.
//
//  Not named `Crash.swift` like the others in this directory: nothing crashes.
//  What it costs is a false report that a check is redundant, in the one place
//  it is load-bearing — a reader who believes it and reaches for `as!` gets a
//  trap in exchange.

import Foundation

struct Plain {
    let x: Int
}

func isComparable(_ rows: [Plain]) -> Bool {
    (rows as? any Equatable) != nil  // warning: conditional cast … always succeeds
}

func isComparableGenerically<Row>(_ rows: [Row]) -> Bool {
    (rows as? any Equatable) != nil  // warning: conditional cast … always succeeds
}
