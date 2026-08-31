// swiftc -c -Onone Crash.swift
//
// Asserts in the LoadableByAddress SIL pass on an assertions-enabled compiler:
//
//   Assertion failed: (srcType == tgtType && "Source and target type do not
//   match"), function rewriteFunction, file LoadableByAddress.cpp, line 2445.
//
// The property alone is enough — the synthesized setter is what the pass
// chokes on, so nothing has to assign to it.

/// Three words, so that `(Region, (Event) -> Bool)` — three plus a two-word
/// thick function — comes to five, and is "large loadable" (over four words).
struct Region {
    var a = 0, b = 0, c = 0
}

/// Five words, so the CLOSURE'S PARAMETER is large loadable too, and the
/// function type is itself rewritten to take it indirectly.
struct Event {
    var a = 0, b = 0, c = 0, d = 0, e = 0
}

final class Box {
    var pending: (region: Region, handler: (Event) -> Bool)?
}
