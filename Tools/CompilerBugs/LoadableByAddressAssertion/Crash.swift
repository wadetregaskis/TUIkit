//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftc -c -Onone -o /dev/null Crash.swift
//
// That is enough for a swift.org toolchain on macOS. Xcode's swiftc, called by
// its path, also needs `-sdk`, from an xcrun that DEVELOPER_DIR points at Xcode
// (a prefix assignment would not reach the xcrun inside `$(...)`):
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -c -Onone \
//       -sdk "$(xcrun --sdk macosx --show-sdk-path)" -o /dev/null Crash.swift
//
// Aborts in the LoadableByAddress SIL pass, on the way to IRGen, on an
// assertions-enabled compiler (swift.org's 6.2.4 prints line 2199):
//
//   Assertion failed: (srcType == tgtType && "Source and target type do not
//   match"), function rewriteFunction, file LoadableByAddress.cpp, line 2199.
//
// A compiler without assertions compiles it, but with
// `-Xfrontend -sil-verify-all` it rejects the SIL instead.
//
// The property alone is enough — the synthesized setter is what the pass
// chokes on, so nothing has to assign to it.

/// Three words, so that `(Region, (Event) -> Bool)` — three plus a two-word
/// thick function — comes to five, and is "large loadable" (over four words).
struct Region {
    var one = 0, two = 0, three = 0
}

/// Five words, so the CLOSURE'S PARAMETER is large loadable too, and the
/// function type is itself rewritten to take it indirectly.
struct Event {
    var one = 0, two = 0, three = 0, four = 0, five = 0
}

final class Box {
    var pending: (region: Region, handler: (Event) -> Bool)?
}
