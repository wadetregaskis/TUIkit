//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftc -emit-silgen -o /dev/null Crash.swift
//
// That is enough for a swift.org toolchain on macOS. Xcode's swiftc, called by
// its path, also needs `-sdk`, from an xcrun that DEVELOPER_DIR points at Xcode
// (a prefix assignment would not reach the xcrun inside `$(...)`):
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -emit-silgen \
//       -sdk "$(xcrun --sdk macosx --show-sdk-path)" -o /dev/null Crash.swift
//
// Aborts SILGen on an assertions-enabled compiler, while it builds the
// reabstraction thunk for the conversion:
//
//   Assertion failed: (!type->hasTypeParameter() && "no generic environment
//   provided for type with type parameters"), function mapTypeIntoContext,
//   file GenericEnvironment.cpp, line 337.
//
// swiftlang/swift#86118, fixed on main by #86131 and on release/6.3 by #86159.

/// A generic context. `Element` is never used.
func convert<Element>(_: Element) {
    // An opaque result whose underlying type, `Int`, does not involve `Element`.
    func zero() -> some Any { 0 }
    // A function conversion, which needs a reabstraction thunk.
    _ = zero as () -> Any
}
